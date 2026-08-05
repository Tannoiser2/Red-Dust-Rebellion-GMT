class_name RDRNonPlayerOps
extends RefCounted

## Esecuzione delle Operazioni Non-Player (§8.6) e delle Attività Speciali
## (§8.7): le procedure che il libretto *Curiosity* scrive per esteso.
##
## ARCHITETTURA. Una carta *Curiosity* non contiene procedure: contiene un
## ELENCO ORDINATO di istruzioni numerate ("① Place Bases where 3+ RD Rebels…",
## "② Select spaces using Place Rebels"). §8.6 e §8.7 dicono cosa significa
## ciascuna istruzione. Qui c'è quindi la **libreria delle istruzioni**, indicizzata
## per nome: quando arriveranno le 24 carte basterà elencarne i nomi in ordine e
## il motore le eseguirà. Le carte diventano dati, non codice.
##
## §8.5.4: le Fazioni NP non scelgono tutti gli spazi in blocco. Ne scelgono uno,
## eseguono, tirano l'Activation Number e solo se passa ne scelgono un altro.
## Per questo qui l'Operazione è eseguita uno spazio alla volta: le priorità
## rileggono la plancia dopo ogni spazio, come al tavolo.
##
## NON implementate perché serve la tabella Move Priorities, che non è nel
## libretto: Secure, Recon, March, Travel, Transport, Raid. `can_run()` lo dice.

## Operazioni che spostano pezzi: servono le Move Priorities (§8.5.7).
const NEEDS_MOVE_PRIORITIES := ["secure", "recon", "march", "travel", "transport", "raid"]

var state: GameState
var module: RDRModule
var np: RDRNonPlayer
var ops: RDROperations
var cards: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_np: RDRNonPlayer, p_ops: RDROperations) -> void:
	np = p_np
	ops = p_ops
	state = p_np.state
	module = p_np.module
	var path := RDRModule.DATA_DIR + "np_cards.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			cards = parsed.get("cards", {})


# ---------------------------------------------------------------------------
# §8.5.3 Lettura di una carta Curiosity
# ---------------------------------------------------------------------------

## Percorre l'albero della carta e dice cosa si esegue.
## I riquadri in cima si leggono dall'alto: se la condizione è vera si scende, se
## è falsa si pesca una carta nuova (`draw`) o si gira questa (`flip`).
## Restituisce {ok, outcome: "operation"|"draw"|"flip", operation, instructions,
## special_activities, trace}.
func read_card(card_id: String, faction: String, rng: RandomNumberGenerator) -> Dictionary:
	var card: Dictionary = cards.get(card_id, {})
	var trace: Array[String] = []
	if card.is_empty():
		return {"ok": false, "outcome": "missing", "trace": trace,
			"error": "Carta Curiosity «%s» non ancora trascritta." % card_id}

	for entry in card.get("checks", []):
		var check: Dictionary = entry
		var value := _card_condition(String(check["cond"]), faction, rng)
		trace.append("%s → %s" % [check.get("text", check["cond"]), "sì" if value else "no"])
		if not value:
			var no := String(check.get("no", "draw"))
			if no == "draw" or no == "flip":
				return {"ok": true, "outcome": no, "trace": trace,
					"next": String(card.get("flip", "")) if no == "flip" else ""}
			break  # ramo alternativo dichiarato dai blocchi

	# Blocchi: il primo che nomina un'Operazione decide l'Operazione.
	var op := ""
	var instructions: Array = []
	for entry2 in card.get("blocks", []):
		var block: Dictionary = entry2
		if block.has("branch"):
			var br: Dictionary = block["branch"]
			var yes := _card_condition(String(br["cond"]), faction, rng)
			trace.append("%s → %s" % [br["cond"], "sì" if yes else "no"])
			var chosen: Dictionary = br["yes"] if yes else br["no"]
			op = String(chosen.get("operation", ""))
			instructions = chosen.get("instructions", [])
			break
		if block.has("operation"):
			op = String(block["operation"])
			instructions = block.get("instructions", [])
			break
	if op == "":
		return {"ok": true, "outcome": "draw", "trace": trace,
			"error": "La carta non porta a nessuna Operazione eseguibile."}
	trace.append("Operazione: %s" % op)
	return {"ok": true, "outcome": "operation", "operation": op,
		"instructions": instructions,
		"special_activities": card.get("special_activities", []),
		"activation_number": int(card.get("activation_number", 0)),
		"limits": card.get("limits", {}), "trace": trace}


## Condizioni dei riquadri in cima alla carta.
func _card_condition(cond: String, faction: String, rng: RandomNumberGenerator) -> bool:
	var rebel := _rebel(faction)
	match cond:
		"available_bases":
			return module.available(state, _base(faction)) > 0
		"1d6_le_available_rebels":
			return rng.randi_range(1, 6) <= module.available(state, rebel)
		"2d6_le_available_rebels":
			return rng.randi_range(1, 6) + rng.randi_range(1, 6) \
				<= module.available(state, rebel)
		"base_without_hidden_rebel":
			for sid in module.mars_spaces(state):
				if module.count_in(state, String(sid), _base(faction)) > 0 \
						and module.count_in(state, String(sid), rebel, "hidden") == 0:
					return true
			return false
		"rebel_in_non_neutral_space":
			for sid in module.mars_spaces(state):
				if module.count_in(state, String(sid), rebel) > 0 \
						and state.spaces[String(sid)].support != CoinEnums.Support.NEUTRAL:
					return true
			return false
		"ten_rebels_on_map":
			var n := 0
			for sid in module.mars_spaces(state):
				n += module.count_in(state, String(sid), rebel)
			return n >= 10
		"three_rebels_in_a_space":
			for sid in module.mars_spaces(state):
				if module.count_in(state, String(sid), rebel) >= 3:
					return true
			return false
		"three_rebels_at_enemy_base_or_uncontrolled":
			for sid in module.mars_spaces(state):
				var s := String(sid)
				if module.count_in(state, s, rebel) < 3:
					continue
				if state.spaces[s].control != faction or _enemy_base_in(s, faction):
					return true
			return false
		"hidden_rebel_at_vulnerable_or_uncontrolled":
			for sid in module.mars_spaces(state):
				var s2 := String(sid)
				if module.count_in(state, s2, rebel, "hidden") == 0:
					continue
				if state.spaces[s2].control != faction:
					return true
				if np._vulnerable_enemy_base(s2, faction):
					return true
			return false
		"rebel_with_support_opposition_or_population":
			for sid in module.mars_spaces(state):
				var s3 := String(sid)
				if module.count_in(state, s3, rebel) == 0:
					continue
				if state.spaces[s3].support != CoinEnums.Support.NEUTRAL \
						or module.population(state, s3) > 0:
					return true
			return false
	return false


func _enemy_base_in(sid: String, faction: String) -> bool:
	for base_id in ["mg_base", "corp_base", "rd_base", "cr_base"]:
		if String(RDRModule.PIECE_OWNER[base_id]) == faction:
			continue
		if module.count_in(state, sid, base_id) > 0:
			return true
	return false


## Si può eseguire questa Operazione per questa Fazione NP, con i dati che ci sono?
func can_run(faction: String, op_id: String) -> Dictionary:
	if NEEDS_MOVE_PRIORITIES.has(op_id):
		return {"ok": false, "error":
			"%s sposta pezzi: serve la tabella Move Priorities (§8.5.7), non riprodotta nel libretto." % op_id}
	if not np.has_table(faction):
		return {"ok": false, "error":
			"manca la tabella Space Selection Priorities di NP %s." % faction}
	return {"ok": true, "error": ""}


# ---------------------------------------------------------------------------
# Ciclo di selezione degli spazi (§8.5.4 + §8.5.6)
# ---------------------------------------------------------------------------

## Esegue `body` in uno spazio alla volta: sceglie con le priorità, esegue, tira
## l'Activation Number e continua finché il tiro passa. `candidates` è chiamata a
## ogni giro perché la plancia cambia. Restituisce gli spazi usati davvero.
func run_by_space(faction: String, column: String, candidates: Callable, body: Callable,
		activation_number: int, limited: bool = false) -> Array:
	var used: Array = []
	var cap: int = np.limited_space_cap(faction) if limited else 99
	while used.size() < cap:
		var pool: Array = []
		for sid in candidates.call():
			if not used.has(String(sid)):
				pool.append(String(sid))
		if pool.is_empty():
			break
		var pick: Dictionary = np.select_space(faction, column, pool)
		var sid2 := String(pick["space"])
		if sid2 == "":
			break
		if not bool(body.call(sid2)):
			break
		used.append(sid2)
		log_lines.append("NP %s: %s (%s)." % [faction, _name(sid2), pick["row"]])
		# §8.5.4: l'Activation Number decide se si continua.
		if activation_number <= 0:
			continue
		var check: Dictionary = np.activation_check(faction, activation_number, limited)
		if not bool(check["ok"]):
			break
	return used


# ---------------------------------------------------------------------------
# §8.6.6 NP RED DUST / §8.6.7 NP CHURCH OF THE RECLAIMER
# ---------------------------------------------------------------------------

## "Place Bases where 3+ Rebels and 1+ Hidden Rebel" (Rally).
func rally_place_bases(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var column := "place_or_dig_in_bases" if faction == "red_dust" else "place_or_upgrade_bases"
	var candidates := func() -> Array:
		var out: Array = []
		for sid in ops.rally_candidates(faction):
			var s := String(sid)
			if module.count_in(state, s, rebel) >= 3 \
					and module.count_in(state, s, rebel, "hidden") >= 1 \
					and ops.act.can_place_base(s) \
					and module.available(state, _base(faction)) > 0:
				out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "base"}]}).get("ok", false))
	return run_by_space(faction, column, candidates, body, activation_number, limited)


## "Select spaces using Place Rebels" (Rally).
func rally_place_rebels(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var candidates := func() -> Array:
		return Array(ops.rally_candidates(faction))
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "place"}]}).get("ok", false))
	return run_by_space(faction, "place_rebels", candidates, body, activation_number, limited)


## "Flip most Rebels where all Active": fra gli spazi con una Base propria e soli
## Ribelli Attivi, quelli con più Ribelli Attivi; lì si rimettono tutti Nascosti.
func rally_flip_hidden(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var candidates := func() -> Array:
		var out: Array = []
		for sid in ops.rally_candidates(faction):
			var s := String(sid)
			if module.count_in(state, s, _base(faction)) > 0 \
					and module.count_in(state, s, rebel, "active") > 0 \
					and module.count_in(state, s, rebel, "hidden") == 0:
				out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "hide"}]}).get("ok", false))
	var column := "place_or_dig_in_bases" if faction == "red_dust" else "place_or_upgrade_bases"
	return run_by_space(faction, column, candidates, body, activation_number, limited)


## §8.6.6 "Dig In": un solo Deserto, alla fine del Rally (nessun tiro di AN).
func rally_dig_in() -> String:
	var pool: Array = []
	for sid in module.mars_spaces(state):
		if module.is_desert(state, String(sid)) \
				and module.count_in(state, String(sid), "rd_base", "basic") > 0:
			pool.append(String(sid))
	if pool.is_empty():
		return ""
	var pick: Dictionary = np.select_space("red_dust", "place_or_dig_in_bases", pool)
	var sid2 := String(pick["space"])
	if sid2 != "":
		ops.rally({"faction": "red_dust", "spaces": [{"id": sid2, "mode": "place"}],
			"dig_in": sid2})
		log_lines.append("NP red_dust: Base Dug-In a %s." % _name(sid2))
	return sid2


## §8.6.6/§8.6.7 Attack. `mode` sceglie quale delle tre istruzioni della carta:
##   "support"      — spazi a Supporto (RD) / a Supporto o Opposizione (CR)
##   "three_rebels" — spazi con 3+ Ribelli propri (RD: e senza Opposizione)
##   "all_active"   — spazi dove tutti i propri Ribelli sono già Attivi
func attack(faction: String, mode: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s, ops.act.storm_free(faction)):
				continue
			if module.count_in(state, s, rebel) == 0:
				continue
			if ops._enemy_force_count(s, faction) == 0:
				continue
			var sup: int = state.spaces[s].support
			match mode:
				"support":
					if faction == "red_dust":
						if sup <= 0:
							continue
					elif sup == CoinEnums.Support.NEUTRAL:
						continue
				"three_rebels":
					if module.count_in(state, s, rebel) < 3:
						continue
					if faction == "red_dust" and sup < 0:
						continue
				"all_active":
					if module.count_in(state, s, rebel, "hidden") > 0:
						continue
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.attack({"faction": faction, "spaces": [sid]}).get("ok", false))
	return run_by_space(faction, "attack", candidates, body, activation_number, limited)


## §8.6.6 Campaign — Red Dust. Se lo spazio ha una Base RD e Ribelli Nascosti,
## lo si sceglie solo se almeno un Ribelle resterebbe Nascosto.
func campaign(activation_number: int, limited: bool = false) -> Array:
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s):
				continue
			if module.population(state, s) <= 0 or module.count_in(state, s, "rd_rebel") == 0:
				continue
			if module.count_in(state, s, "rd_base") > 0 \
					and module.count_in(state, s, "rd_rebel", "hidden") > 0 \
					and module.count_in(state, s, "rd_rebel", "hidden") < 2:
				continue  # resterebbe scoperta la Base
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.campaign({"spaces": [sid]}).get("ok", false))
	return run_by_space("red_dust", "shift_active_opposition", candidates, body,
		activation_number, limited)


## §8.6.7 Preach — Reclaimer. Stessa cautela sulla Base scoperta.
func preach(activation_number: int, limited: bool = false) -> Array:
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s, ops.act.storm_free("reclaimer")):
				continue
			if module.population(state, s) <= 0 or module.count_in(state, s, "cr_rebel") == 0:
				continue
			if module.count_in(state, s, "cr_base") > 0 \
					and module.count_in(state, s, "cr_rebel", "hidden") > 0 \
					and module.count_in(state, s, "cr_rebel", "hidden") < 2:
				continue
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.preach({"spaces": [sid]}).get("ok", false))
	return run_by_space("reclaimer", "place_damage", candidates, body,
		activation_number, limited)


# ---------------------------------------------------------------------------

func _rebel(faction: String) -> String:
	return "cr_rebel" if faction == "reclaimer" else "rd_rebel"


func _base(faction: String) -> String:
	return "cr_base" if faction == "reclaimer" else "rd_base"


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid
