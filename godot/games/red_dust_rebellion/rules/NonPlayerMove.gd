class_name RDRNonPlayerMove
extends RefCounted

## Motore di movimento delle Fazioni NP (§8.5.7 Move Priorities).
##
## Serve a Secure (§5.3), Recon (§5.4), March (§5.7), Travel (§5.8) e
## all'Attività Speciale Transport (§6.3).
##
## Il ciclo della tabella:
##   passo A — si sceglie la destinazione con le Space Selection Priorities
##             (i Reclaimer fanno il contrario: prima l'origine);
##   passo B — si sceglie l'altra estremità fra gli spazi a portata, quello con
##             più forze muovibili della Fazione che agisce;
##   keep    — leggendo la colonna della Fazione si decide quanto DEVE restare
##             nell'origine;
##   get     — sempre a colonna, quanto deve ARRIVARE a destinazione;
##   passo C — si torna al passo A o al passo B secondo l'esito.
##
## Le due parole del glossario sono precise e le rispettiamo alla lettera:
##   Get  — muovi APPENA QUANTO BASTA, contando ciò che c'è già; se non serve
##          nulla non muovere niente; se i pezzi non bastano muovi quel che puoi.
##   Keep — lascia APPENA QUANTO BASTA; se i pezzi non bastano, ignora l'istruzione.
##
## Quali pezzi muovere fra quelli ammessi lo decide la Piece Priorities (§8.5.8).

var state: GameState
var module: RDRModule
var np: RDRNonPlayer
var ops: RDROperations
var log_lines: Array[String] = []

## Colonna delle Space Selection Priorities da usare per la destinazione.
const DEST_COLUMN := {
	"secure": "secure_destination",
	"recon": "recon_destination",
	"march": "march_destination",
	"travel": "travel_destination",
	"transport": "transport_destination",
}


func _init(p_np: RDRNonPlayer, p_ops: RDROperations) -> void:
	np = p_np
	ops = p_ops
	state = p_np.state
	module = p_np.module


## Unità che la Fazione può davvero spostare con quell'Operazione.
func movable_types(faction: String, op_id: String) -> Array:
	match faction:
		"marsgov":
			var mg: Array = ["mg_troop"]
			if module.eg_controller(state) == "marsgov":
				mg.append("eg_troop")
			return mg
		"corporations":
			var corp: Array = ["security", "specops"]
			if module.eg_controller(state) == "corporations":
				corp.append("eg_troop")
			return corp
		"red_dust":
			return ["rd_rebel"]
		"reclaimer":
			# §5.8: il Travel muove anche le Basi.
			return ["cr_rebel", "cr_base"] if op_id == "travel" else ["cr_rebel"]
	return []


func _count_types(sid: String, types: Array, piece_state = null) -> int:
	var n := 0
	for t in types:
		n += module.count_in(state, sid, String(t), piece_state)
	return n


# ---------------------------------------------------------------------------
# Keep: quanto deve restare nell'origine
# ---------------------------------------------------------------------------

## Numero minimo di forze della Fazione che devono restare in `origin`.
## Si prende il massimo fra le istruzioni applicabili: sono tutte dei minimi.
func keep_in_origin(faction: String, origin: String, op_id: String,
		notes: Array = []) -> int:
	var types := movable_types(faction, op_id)
	var have := _count_types(origin, types)
	var keep := 0
	for entry in np.move_priorities.get("keep_in_origin", []):
		var rule: Dictionary = entry
		if not Array(rule.get("factions", [])).has(faction):
			continue
		if rule.has("only_if_player") and not np.is_player(String(rule["only_if_player"])):
			continue
		if rule.has("when") and not _condition(String(rule["when"]), faction, origin, ""):
			continue
		var want := _keep_rule(String(rule["rule"]), faction, origin, types)
		# "Keep": se i pezzi non bastano, l'istruzione si ignora.
		if want <= 0 or want > have:
			continue
		if want > keep:
			keep = want
			notes.append(String(rule["label"]))
	return keep


func _keep_rule(rule: String, faction: String, sid: String, types: Array) -> int:
	match rule:
		"keep_no_control_change":
			return _forces_to_hold_control(faction, sid, types)
		"keep_cubes_ge_active_rebels":
			return _count_types(sid, ["rd_rebel", "cr_rebel"], "active")
		"keep_mg_ge_corp":
			return _count_types(sid, ["security", "specops", "corp_base"])
		"keep_corp_gt_mg":
			return module.count_in(state, sid, "mg_troop") + 1
		"keep_cubes_eq_population":
			return module.population(state, sid)
		"keep_4_cubes_at_mg_base":
			return 4 if module.count_in(state, sid, "mg_base") > 0 else 0
		"keep_4_cubes_at_corp_base":
			return 4 if module.count_in(state, sid, "corp_base") > 0 else 0
		"keep_1_hidden_rebel_at_base":
			return 1 if module.count_in(state, sid, _base(faction)) > 0 else 0
		"keep_3_rebels_with_base_room":
			return 3 if (ops.act.can_place_base(sid) and module.available(state, _base(faction)) > 0) \
				else 0
		"keep_1_rebel_pop2_no_active_opposition":
			return 1 if (module.population(state, sid) >= 2
				and state.spaces[sid].support != CoinEnums.Support.ACTIVE_OPPOSITION) else 0
		"keep_1_rebel_populated":
			return 1 if module.population(state, sid) > 0 else 0
	return 0


## Quante forze bastano perché il Controllo dello spazio non cambi.
func _forces_to_hold_control(faction: String, sid: String, types: Array) -> int:
	var current: String = state.spaces[sid].control
	var mine := _count_types(sid, types)
	for stay in range(0, mine + 1):
		if _control_with(faction, sid, mine - stay) == current:
			return stay
	return mine


## Controllo che avrebbe lo spazio togliendo `gone` forze alla Fazione.
func _control_with(faction: String, sid: String, gone: int) -> String:
	var st: SpaceState = state.spaces[sid]
	var coin := module.coin_forces(state, st)
	var rd := module.control_forces(state, st, "red_dust")
	var cr := module.control_forces(state, st, "reclaimer")
	match faction:
		"marsgov", "corporations":
			coin -= gone
		"red_dust":
			rd -= gone
		"reclaimer":
			cr -= gone
	if coin > rd + cr:
		return "coin"
	if rd > coin + cr:
		return "red_dust"
	if cr > coin + rd:
		return "reclaimer"
	return ""


# ---------------------------------------------------------------------------
# Get: quanto deve arrivare a destinazione
# ---------------------------------------------------------------------------

## Quante forze servono in `dest`, e di quali tipi in particolare.
## Restituisce {total: int, by_type: {tipo: quantità}}: sono soglie, non somme.
func get_in_destination(faction: String, dest: String, op_id: String,
		notes: Array = []) -> Dictionary:
	var types := movable_types(faction, op_id)
	var out := {"total": 0, "by_type": {}}
	for entry in np.move_priorities.get("move_to_destination", []):
		var rule: Dictionary = entry
		if not Array(rule.get("factions", [])).has(faction):
			continue
		if rule.has("only_if_player") and not np.is_player(String(rule["only_if_player"])):
			continue
		if rule.has("when") and not _condition(String(rule["when"]), faction, "", dest):
			continue
		var got := _get_rule(String(rule["rule"]), faction, dest, types)
		if got.is_empty():
			continue
		if got.has("total") and int(got["total"]) > int(out["total"]):
			out["total"] = int(got["total"])
			notes.append(String(rule["label"]))
		if got.has("type"):
			var t := String(got["type"])
			var n := int(got["count"])
			if n > int((out["by_type"] as Dictionary).get(t, 0)):
				(out["by_type"] as Dictionary)[t] = n
				notes.append(String(rule["label"]))
	return out


func _get_rule(rule: String, faction: String, dest: String, types: Array) -> Dictionary:
	match rule:
		"get_1_base":
			return {"type": _base(faction), "count": 1}
		"get_1_unit":
			return {"total": 1}
		"get_units_eq_hidden_rebels":
			return {"total": _count_types(dest, ["rd_rebel", "cr_rebel"], "hidden")}
		"get_units_eq_twice_hidden_rebels":
			return {"total": _count_types(dest, ["rd_rebel", "cr_rebel"], "hidden") * 2}
		"get_mg_ge_corp":
			return {"total": _count_types(dest, ["security", "specops", "corp_base"])}
		"get_coin_control":
			return {"total": _forces_to_take_control(faction, dest, "coin")}
		"get_cubes_eq_population":
			return {"total": module.population(state, dest)}
		"get_corp_gt_mg":
			return {"total": module.count_in(state, dest, "mg_troop") + 1}
		"get_4_cubes_to_mg_base":
			return {"total": 4} if module.count_in(state, dest, "mg_base") > 0 else {}
		"get_4_cubes_to_corp_base":
			return {"total": 4} if module.count_in(state, dest, "corp_base") > 0 else {}
		"get_max_hidden_rebels":
			# "quanti più Ribelli Nascosti possibile": non c'è una soglia, prende tutto.
			return {"total": 99}
		"get_1_hidden_rebel":
			return {"type": _rebel(faction), "count": 1}
		"get_3_rebels":
			return {"type": _rebel(faction), "count": 3}
		"get_3_security":
			return {"type": "security", "count": 3}
		"get_1_security":
			return {"type": "security", "count": 1}
		"get_1_specops":
			return {"type": "specops", "count": 1}
		"get_faction_control":
			return {"total": _forces_to_take_control(faction, dest, faction)}
	return {}


## Quante forze in più servono perché lo spazio passi sotto il Controllo voluto.
func _forces_to_take_control(faction: String, sid: String, want: String) -> int:
	for extra in range(0, 13):
		if _control_with_added(faction, sid, extra) == want:
			return _count_types(sid, movable_types(faction, "")) + extra
	return 0


func _control_with_added(faction: String, sid: String, added: int) -> String:
	var st: SpaceState = state.spaces[sid]
	var coin := module.coin_forces(state, st)
	var rd := module.control_forces(state, st, "red_dust")
	var cr := module.control_forces(state, st, "reclaimer")
	match faction:
		"marsgov", "corporations":
			coin += added
		"red_dust":
			rd += added
		"reclaimer":
			cr += added
	if coin > rd + cr:
		return "coin"
	if rd > coin + cr:
		return "red_dust"
	if cr > coin + rd:
		return "reclaimer"
	return ""


# ---------------------------------------------------------------------------
# Condizioni in rosso della tabella
# ---------------------------------------------------------------------------

func _condition(cond: String, faction: String, origin: String, dest: String) -> bool:
	match cond:
		"cubes_ge_vulnerable_enemies":
			var cubes := _count_types(origin, ["mg_troop", "security", "eg_troop"])
			return cubes >= _count_types(origin, ["rd_rebel", "cr_rebel"], "active")
		"origin_at_support_with_corp_base":
			return state.spaces[origin].support > 0 \
				and module.count_in(state, origin, "corp_base") > 0
		"origin_populated_with_corp_base":
			return module.population(state, origin) > 0 \
				and module.count_in(state, origin, "corp_base") > 0
		"destination_is_desert":
			return module.is_desert(state, dest)
		"destination_is_wilderness":
			return dest == "wilderness"
		"destination_at_support_with_corp_base":
			return state.spaces[dest].support > 0 \
				and module.count_in(state, dest, "corp_base") > 0
		"destination_populated_with_corp_base":
			return module.population(state, dest) > 0 \
				and module.count_in(state, dest, "corp_base") > 0
		"destination_at_support":
			return state.spaces[dest].support > 0
		"acting_base_in_destination":
			return module.count_in(state, dest, _base(faction)) > 0
		"destination_has_room_for_available_base":
			return ops.act.can_place_base(dest) and module.available(state, _base(faction)) > 0
		"destination_no_corp_base_with_room":
			return module.count_in(state, dest, "corp_base") == 0 \
				and ops.act.can_place_base(dest) and module.available(state, "corp_base") > 0
		"destination_has_damage":
			return module.marker(state, dest, "damage") > 0
	return false


# ---------------------------------------------------------------------------
# Pianificazione degli spostamenti
# ---------------------------------------------------------------------------

## Costruisce gli spostamenti per UNA coppia origine → destinazione, rispettando
## il Keep dell'origine e il Get della destinazione, e scegliendo i pezzi con le
## Piece Priorities. Restituisce [{from, to, type, count}].
func plan_pair(faction: String, op_id: String, origin: String, dest: String,
		notes: Array = []) -> Array:
	var types := movable_types(faction, op_id)
	var keep := keep_in_origin(faction, origin, op_id, notes)
	var pool := maxi(0, _count_types(origin, types) - keep)
	if pool <= 0:
		return []
	var need := get_in_destination(faction, dest, op_id, notes)
	var moves: Array = []

	# Prima le soglie per tipo, poi il totale: "Get" conta ciò che c'è già.
	for t in (need["by_type"] as Dictionary).keys():
		var type_id := String(t)
		if not types.has(type_id):
			continue
		var missing := int(need["by_type"][type_id]) - module.count_in(state, dest, type_id)
		var take: int = mini(maxi(0, missing), mini(pool, module.count_in(state, origin, type_id)))
		if take > 0:
			moves.append({"from": origin, "to": dest, "type": type_id, "count": take})
			pool -= take

	var total_missing := int(need["total"]) - _count_types(dest, types)
	var still: int = mini(maxi(0, total_missing), pool)
	while still > 0:
		# Quale pezzo muovere lo dice la Piece Priorities.
		var pick := np.pick_piece(faction, origin, "friendly_place", types)
		if pick.is_empty():
			break
		var type_id2 := String(pick["type"])
		var already := 0
		for m in moves:
			if String(m["type"]) == type_id2:
				already += int(m["count"])
		var avail := module.count_in(state, origin, type_id2) - already
		if avail <= 0:
			break
		var take2: int = mini(still, avail)
		var merged := false
		for m in moves:
			if String(m["type"]) == type_id2:
				m["count"] = int(m["count"]) + take2
				merged = true
		if not merged:
			moves.append({"from": origin, "to": dest, "type": type_id2, "count": take2})
		still -= take2
		# Se il tipo scelto è esaurito la prossima iterazione ne troverà un altro;
		# se non ce ne sono più, `pick_piece` restituisce vuoto e si esce.
		if take2 == 0:
			break
	return moves


## Ciclo completo A → B → keep/get → C dell'Operazione di movimento.
## Restituisce {ok, pairs: [{from, to, moved}], trace}.
func run_operation(faction: String, op_id: String, activation_number: int,
		limited: bool = false) -> Dictionary:
	var column := String(DEST_COLUMN.get(op_id, ""))
	if column == "":
		return {"ok": false, "error": "%s non è un'Operazione di movimento." % op_id,
			"pairs": [], "trace": []}
	var steps: Dictionary = np.move_priorities.get("steps", {}).get(faction, {})
	# §8.5.7: i Reclaimer scelgono prima l'origine, gli altri la destinazione.
	var origin_first := String(steps.get("a", "destination")) == "origin"
	var pairs: Array = []
	var trace: Array[String] = []
	var used_dest: Array = []
	var used_origin: Array = []
	var cap: int = np.limited_space_cap(faction) if limited else 8

	while pairs.size() < cap:
		var dest := ""
		var origin := ""
		if origin_first:
			origin = _pick_origin_first(faction, op_id, used_origin)
			if origin == "":
				break
			dest = _pick_destination(faction, op_id, column, used_dest + [origin])
		else:
			dest = _pick_destination(faction, op_id, column, used_dest)
			if dest == "":
				break
			origin = choose_origin(faction, op_id, dest, used_origin + [dest])
		if dest == "" or origin == "":
			break

		var notes: Array = []
		var moves := plan_pair(faction, op_id, origin, dest, notes)
		if moves.is_empty():
			# Nessuna forza da muovere: quell'estremità non serve più.
			used_origin.append(origin)
			continue
		var res := _execute(faction, op_id, dest, origin, moves)
		if not res.get("ok", false):
			trace.append("%s → %s rifiutata: %s" % [origin, dest, res.get("error", "")])
			used_origin.append(origin)
			continue
		var moved := 0
		for m in moves:
			moved += int(m["count"])
		pairs.append({"from": origin, "to": dest, "moved": moved})
		trace.append("%s → %s: %d unità (%s)" % [
			_name(origin), _name(dest), moved, ", ".join(PackedStringArray(notes))])
		used_dest.append(dest)
		used_origin.append(origin)

		# §8.5.7 passo C: si torna al passo A o al passo B secondo l'esito.
		if not _step_c_new_destination(faction, dest, origin):
			used_dest.erase(dest)   # si riprova la stessa destinazione da un'altra origine
		if activation_number > 0:
			var check := np.activation_check(faction, activation_number, limited)
			if not bool(check["ok"]):
				break
	return {"ok": true, "pairs": pairs, "trace": trace}


## Passo C: true se si sceglie una nuova destinazione, false una nuova origine.
func _step_c_new_destination(faction: String, dest: String, origin: String) -> bool:
	match faction:
		"marsgov", "corporations":
			return state.spaces[dest].control == "coin"
		"red_dust":
			var ctrl: String = state.spaces[dest].control
			return ctrl == "" or ctrl == faction
		"reclaimer":
			# Se restano Ribelli muovibili nell'origine si cerca un'altra
			# destinazione, altrimenti una nuova origine.
			return _count_types(origin, ["cr_rebel"]) \
				- keep_in_origin(faction, origin, "travel") > 0
	return true


func _pick_destination(faction: String, op_id: String, column: String,
		exclude: Array) -> String:
	var pool: Array = []
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if exclude.has(s) or not ops.act.selectable(s, ops.act.storm_free(faction)):
			continue
		if op_id == "secure" and not module.is_labyrinth(state, s):
			continue
		if op_id == "recon" and not module.is_desert(state, s):
			continue
		if ops.legal_origins_for(op_id, faction, s, movable_types(faction, op_id)).is_empty():
			continue
		pool.append(s)
	if pool.is_empty():
		return ""
	return String(np.select_space(faction, column, pool)["space"])


## §5.8: il Travel dei Reclaimer sceglie prima l'origine, quella con più forze.
func _pick_origin_first(faction: String, op_id: String, exclude: Array) -> String:
	var types := movable_types(faction, op_id)
	var best := ""
	var best_n := 0
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if exclude.has(s):
			continue
		var n := _count_types(s, types) - keep_in_origin(faction, s, op_id)
		if n > best_n:
			best_n = n
			best = s
	return best


func _execute(faction: String, op_id: String, dest: String, origin: String,
		moves: Array) -> Dictionary:
	match op_id:
		"secure":
			return ops.secure({"faction": faction, "dest": [dest], "moves": moves})
		"recon":
			return ops.recon({"faction": faction, "dest": [dest], "moves": moves})
		"march":
			return ops.march({"dest": [dest], "moves": moves})
		"travel":
			return ops.travel({"origins": [origin], "moves": moves})
	return {"ok": false, "error": "Operazione '%s' non gestita." % op_id}


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid


## §8.5.7 passo B: fra gli spazi a portata, quello con più forze muovibili.
func choose_origin(faction: String, op_id: String, dest: String, exclude: Array) -> String:
	var types := movable_types(faction, op_id)
	var best := ""
	var best_n := 0
	for sid in ops.legal_origins_for(op_id, faction, dest, types):
		var s := String(sid)
		if exclude.has(s):
			continue
		var n := _count_types(s, types) - keep_in_origin(faction, s, op_id)
		if n > best_n:
			best_n = n
			best = s
	return best


func _rebel(faction: String) -> String:
	return "cr_rebel" if faction == "reclaimer" else "rd_rebel"


func _base(faction: String) -> String:
	match faction:
		"reclaimer": return "cr_base"
		"red_dust": return "rd_base"
		"corporations": return "corp_base"
	return "mg_base"
