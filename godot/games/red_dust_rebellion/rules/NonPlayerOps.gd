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

		# --- pescate dalle Disponibili ---------------------------------
		"1d6_le_available_bases":
			return rng.randi_range(1, 6) <= module.available(state, _base(faction))
		"1d6_le_available_troops":
			return rng.randi_range(1, 6) <= module.available(state, "mg_troop")
		"2d6_le_available_troops":
			return rng.randi_range(1, 6) + rng.randi_range(1, 6) \
				<= module.available(state, "mg_troop")
		"2d6_le_available_security":
			return rng.randi_range(1, 6) + rng.randi_range(1, 6) \
				<= module.available(state, "security")

		# --- tracciati e marcatori --------------------------------------
		"displaced_population_any":
			return int(state.tracks.get("displaced_population", 0)) > 0
		"eg_confidence_above_4":
			return module.eg_confidence_value(state) > 4
		"eg_minus":
			return int(state.tracks.get("eg_side", -1)) < 0

		# --- conteggi sulla mappa ----------------------------------------
		"fifteen_rebels_on_map":
			var n15 := 0
			for sid in module.mars_spaces(state):
				n15 += module.count_in(state, String(sid), rebel)
			return n15 >= 15
		"three_rebels_at_enemy_base":
			for sid in module.mars_spaces(state):
				var s4 := String(sid)
				if module.count_in(state, s4, rebel) >= 3 and _enemy_base_in(s4, faction):
					return true
			return false
		"three_rebels_with_enemy_forces":
			for sid in module.mars_spaces(state):
				var s5 := String(sid)
				if module.count_in(state, s5, rebel) >= 3 \
						and ops._enemy_force_count(s5, faction) > 0:
					return true
			return false
		"three_rebels_populated_base_room_no_support":
			for sid in module.mars_spaces(state):
				var s6 := String(sid)
				if module.count_in(state, s6, rebel) < 3:
					continue
				if module.population(state, s6) > 0 and state.spaces[s6].support <= 0 \
						and ops.act.can_place_base(s6) \
						and module.available(state, _base(faction)) > 0:
					return true
			return false
		"hidden_rebel_at_vulnerable_base":
			for sid in module.mars_spaces(state):
				var s7 := String(sid)
				if module.count_in(state, s7, rebel, "hidden") > 0 \
						and np._vulnerable_enemy_base(s7, faction):
					return true
			return false
		"rebel_in_pop2_not_active_opposition":
			for sid in module.mars_spaces(state):
				var s8 := String(sid)
				if module.count_in(state, s8, rebel) > 0 \
						and module.population(state, s8) >= 2 \
						and state.spaces[s8].support != CoinEnums.Support.ACTIVE_OPPOSITION:
					return true
			return false
		"rebels_in_two_populated_not_active_opposition":
			var found := 0
			for sid in module.mars_spaces(state):
				var s9 := String(sid)
				if module.count_in(state, s9, rebel) > 0 \
						and module.population(state, s9) > 0 \
						and state.spaces[s9].support != CoinEnums.Support.ACTIVE_OPPOSITION:
					found += 1
			return found >= 2

		# --- situazioni COIN ---------------------------------------------
		"space_without_coin_control":
			for sid in module.mars_spaces(state):
				if state.spaces[String(sid)].control != "coin":
					return true
			return false
		"coin_control_not_active_support":
			for sid in module.mars_spaces(state):
				var sa := String(sid)
				if state.spaces[sa].control == "coin" \
						and state.spaces[sa].support != CoinEnums.Support.ACTIVE_SUPPORT:
					return true
			return false
		"labyrinth_support_with_rebel":
			return _any_space(true, func(sid: String) -> bool:
				return state.spaces[sid].support > 0 \
					and (module.count_in(state, sid, "rd_rebel")
						+ module.count_in(state, sid, "cr_rebel")) > 0)
		"desert_support_with_rebel":
			return _any_space(false, func(sid: String) -> bool:
				return state.spaces[sid].support > 0 \
					and (module.count_in(state, sid, "rd_rebel")
						+ module.count_in(state, sid, "cr_rebel")) > 0)
		"labyrinth_support_hidden_rebels":
			return _any_space(true, func(sid: String) -> bool:
				return state.spaces[sid].support > 0 \
					and (module.count_in(state, sid, "rd_rebel", "hidden")
						+ module.count_in(state, sid, "cr_rebel", "hidden")) > 0)
		"non_terraforming_corp_base_in_desert":
			return _any_space(false, func(sid: String) -> bool:
				return module.count_in(state, sid, "corp_base", "basic") > 0)
		"two_populated_corp_bases_corp_gt_mg_no_damage":
			var ok2 := 0
			for sid in module.mars_spaces(state):
				var sb := String(sid)
				if module.population(state, sb) <= 0:
					continue
				if module.count_in(state, sb, "corp_base") == 0:
					continue
				if module.marker(state, sb, "damage") > 0:
					continue
				var corp := module.count_in(state, sb, "security") \
					+ module.count_in(state, sb, "specops")
				if corp > module.count_in(state, sb, "mg_troop"):
					ok2 += 1
			return ok2 >= 2
		"space_coin_control_security_damage":
			for sid in module.mars_spaces(state):
				var sc := String(sid)
				if state.spaces[sc].control == "coin" \
						and module.count_in(state, sc, "security") > 0 \
						and module.marker(state, sc, "damage") > 0:
					return true
			return false
		"labyrinth_without_coin_control_reachable_by_mg":
			return _reachable(faction, "secure", ["mg_troop"], func(sid: String) -> bool:
				return module.is_labyrinth(state, sid) and state.spaces[sid].control != "coin")
		"desert_without_corp_base_reachable_by_corp":
			return _reachable(faction, "recon", ["security", "specops"],
				func(sid: String) -> bool:
					return module.is_desert(state, sid) \
						and module.count_in(state, sid, "corp_base") == 0)

		# --- valutazioni dell'Assault -------------------------------------
		"assault_could_remove_base":
			return _assault_any(faction, "base")
		"assault_could_remove_base_or_two_rebels":
			return _assault_any(faction, "base_or_two")
		"assault_could_remove_base_three_rebels_or_at_support":
			return _assault_any(faction, "base_three_or_support")
		"assault_could_remove_base_or_rebel_at_support":
			return _assault_any(faction, "base_or_support")
	push_warning("NP: condizione di carta non riconosciuta «%s»" % cond)
	return false


## Elenco delle condizioni implementate: il test verifica che le carte non ne
## usino nessuna fuori da qui.
const CARD_CONDITIONS := [
	"available_bases", "1d6_le_available_rebels", "2d6_le_available_rebels",
	"base_without_hidden_rebel", "rebel_in_non_neutral_space", "ten_rebels_on_map",
	"three_rebels_in_a_space", "three_rebels_at_enemy_base_or_uncontrolled",
	"hidden_rebel_at_vulnerable_or_uncontrolled",
	"rebel_with_support_opposition_or_population",
	"1d6_le_available_bases", "1d6_le_available_troops", "2d6_le_available_troops",
	"2d6_le_available_security", "displaced_population_any", "eg_confidence_above_4",
	"eg_minus", "fifteen_rebels_on_map", "three_rebels_at_enemy_base",
	"three_rebels_with_enemy_forces", "three_rebels_populated_base_room_no_support",
	"hidden_rebel_at_vulnerable_base", "rebel_in_pop2_not_active_opposition",
	"rebels_in_two_populated_not_active_opposition", "space_without_coin_control",
	"coin_control_not_active_support", "labyrinth_support_with_rebel",
	"desert_support_with_rebel", "labyrinth_support_hidden_rebels",
	"non_terraforming_corp_base_in_desert", "two_populated_corp_bases_corp_gt_mg_no_damage",
	"space_coin_control_security_damage", "labyrinth_without_coin_control_reachable_by_mg",
	"desert_without_corp_base_reachable_by_corp", "assault_could_remove_base",
	"assault_could_remove_base_or_two_rebels",
	"assault_could_remove_base_three_rebels_or_at_support",
	"assault_could_remove_base_or_rebel_at_support",
]


func _any_space(labyrinth: bool, test: Callable) -> bool:
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if module.is_labyrinth(state, s) != labyrinth:
			continue
		if bool(test.call(s)):
			return true
	return false


## Esiste uno spazio che soddisfa `test` e raggiungibile con quell'Operazione?
func _reachable(faction: String, op_id: String, types: Array, test: Callable) -> bool:
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if not bool(test.call(s)):
			continue
		if ops.legal_origins_for(op_id, faction, s, types).size() > 0:
			return true
	return false


## §5.5: l'Assault rimuove un Ribelle Attivo per unità COIN presente, e la Base
## solo quando non restano Ribelli di quella Fazione a difenderla.
func _assault_any(faction: String, kind: String) -> bool:
	for sid in module.mars_spaces(state):
		var s := String(sid)
		var hits := 0
		for t in ops._coin_unit_types(faction):
			hits += module.count_in(state, s, String(t),
				"active" if String(t) == "specops" else null)
		if hits <= 0:
			continue
		var active := module.count_in(state, s, "rd_rebel", "active") \
			+ module.count_in(state, s, "cr_rebel", "active")
		var at_support: bool = state.spaces[s].support > 0
		var base := _assault_clears_base(s, hits)
		match kind:
			"base":
				if base:
					return true
			"base_or_two":
				if base or (active >= 2 and hits >= 2):
					return true
			"base_three_or_support":
				if base or (active >= 3 and hits >= 3) or (at_support and active > 0):
					return true
			"base_or_support":
				if base or (at_support and active > 0):
					return true
	return false


## Una Base Ribelle cade solo se non restano Ribelli suoi: i Nascosti non si
## possono colpire, quindi bastano i colpi per gli Attivi più uno.
func _assault_clears_base(sid: String, hits: int) -> bool:
	for pair in [["rd_base", "rd_rebel"], ["cr_base", "cr_rebel"]]:
		var base_id := String(pair[0])
		var rebel_id := String(pair[1])
		if module.count_in(state, sid, base_id) == 0:
			continue
		if module.count_in(state, sid, rebel_id, "hidden") > 0:
			continue
		if hits >= module.count_in(state, sid, rebel_id, "active") + 1:
			return true
	return false


func _enemy_base_in(sid: String, faction: String) -> bool:
	for base_id in ["mg_base", "corp_base", "rd_base", "cr_base"]:
		if String(RDRModule.PIECE_OWNER[base_id]) == faction:
			continue
		if module.count_in(state, sid, base_id) > 0:
			return true
	return false


## Carte Curiosity di ciascuna Fazione (i fronti; i retri si raggiungono girando).
const DECKS := {
	"marsgov": ["A", "B", "C", "D", "E", "F"],
	"corporations": ["G", "H", "J", "K", "L", "M"],
	"red_dust": ["N", "P", "Q", "R", "S", "T"],
	"reclaimer": ["U", "V", "W", "X", "Y", "Z"],
}

## Motore di movimento, se collegato: serve alle Operazioni che spostano pezzi.
var move: RDRNonPlayerMove = null


## §8.5: il turno completo di una Fazione NP.
## Decide l'azione con la tabella di Eligibility, pesca una carta Curiosity, la
## legge (pescandone un'altra o girandola quando la carta lo impone) ed esegue
## l'Operazione che ne risulta.
## Restituisce {ok, action, card, operation, pairs/spaces, trace}.
func take_turn(faction: String, slot: String, ctx: Dictionary = {},
		rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng if rng != null else RandomNumberGenerator.new()
	var trace: Array[String] = []
	var decision := np.choose_action(faction, slot, ctx)
	trace.append("Eligibility: %s → %s" % [decision["label"], decision["action"]])
	var action := String(decision["action"])
	if action in ["pass", "event", "asset_event"]:
		# L'Evento richiede Effective Events ed Event Instructions, non ancora
		# trascritte: per ora si passa e lo si dichiara.
		return {"ok": true, "action": action, "trace": trace,
			"degraded": bool(decision.get("degraded", false))}

	var limited := action == "lim_op"
	# §8.5.3: si pesca finché una carta non porta a un'Operazione (al massimo
	# tutto il mazzo, per non girare a vuoto).
	var card_id := ""
	var read: Dictionary = {}
	for attempt in range(DECKS.get(faction, []).size() * 2):
		card_id = np.draw_card(faction)
		if card_id == "":
			break
		read = read_card(card_id, faction, r)
		trace.append_array(read.get("trace", []))
		if String(read.get("outcome", "")) == "flip":
			card_id = String(read.get("next", ""))
			if card_id == "":
				continue
			read = read_card(card_id, faction, r)
			trace.append_array(read.get("trace", []))
		if String(read.get("outcome", "")) == "operation":
			break
	if String(read.get("outcome", "")) != "operation":
		return {"ok": false, "action": action, "trace": trace,
			"error": "Nessuna carta Curiosity porta a un'Operazione."}

	var op_id := String(read["operation"])
	var an := int(read.get("activation_number", 0))
	trace.append("Carta %s → %s (AN %d)" % [card_id, op_id, an])
	var out := {"ok": true, "action": action, "card": card_id, "operation": op_id,
		"trace": trace, "degraded": bool(decision.get("degraded", false))}

	if NEEDS_MOVE_PRIORITIES.has(op_id):
		if move == null:
			out["ok"] = false
			out["error"] = "Motore di movimento non collegato."
			return out
		var moved := move.run_operation(faction, op_id, an, limited)
		out["pairs"] = moved.get("pairs", [])
		trace.append_array(moved.get("trace", []))
		return out

	out["spaces"] = _run_instructions(faction, op_id, read.get("instructions", []), an, limited)
	_maybe_special(faction, action, read, out, trace)
	return out


## §4.1: l'Attività Speciale accompagna l'Operazione, quindi solo con Op+SA.
func _maybe_special(faction: String, action: String, read: Dictionary,
		out: Dictionary, trace: Array) -> void:
	if action != "op_sa":
		return
	var list: Array = read.get("special_activities", [])
	if list.is_empty():
		return
	var done := run_special_activity(faction, list)
	if bool(done.get("ok", false)):
		out["special"] = String(done["special"])
		out["special_spaces"] = done["spaces"]
		trace.append("Attività Speciale: %s" % done["special"])
	elif not (done.get("skipped", []) as Array).is_empty():
		trace.append("Attività Speciale saltata (%s: non ancora eseguibile)"
			% ", ".join(PackedStringArray(done["skipped"])))


## Esegue le istruzioni della carta che sappiamo già eseguire (§8.6).
func _run_instructions(faction: String, op_id: String, instructions: Array,
		an: int, limited: bool) -> Array:
	var used: Array = []
	for entry in instructions:
		var i: Dictionary = entry
		if i.has("only_if_player") and not np.is_player(String(i["only_if_player"])):
			continue
		# Le istruzioni col numerale bianco non fanno tirare l'Activation Number.
		var roll := 0 if bool(i.get("no_an_roll", false)) else an
		match String(i["id"]):
			"rally_place_bases":
				used.append_array(rally_place_bases(faction, roll, limited))
			"rally_place_rebels", "rally_alternate_place_upgrade":
				used.append_array(rally_place_rebels(faction, roll, limited))
			"rally_flip_hidden":
				used.append_array(rally_flip_hidden(faction, roll, limited))
			"rally_dig_in":
				var dug := rally_dig_in()
				if dug != "":
					used.append(dug)
			"attack_support":
				used.append_array(attack(faction, "support", roll, limited))
			"attack_three_rebels":
				used.append_array(attack(faction, "three_rebels", roll, limited))
			"attack_all_active":
				used.append_array(attack(faction, "all_active", roll, limited))
			"campaign":
				used.append_array(campaign(roll, limited))
			"preach":
				used.append_array(preach(roll, limited))
			"assault_remove_bases":
				used.append_array(assault(faction, "bases", roll, limited))
			"assault_remove":
				used.append_array(assault(faction, "any", roll, limited))
			"assault_suppress":
				pass  # Suppress e Bombard viaggiano nel piano dell'Assault
			"train_place_troops":
				used.append_array(train(roll, limited))
			"train_pacify":
				pass  # il Pacify è già dentro train(), come sulla carta
			"logistics_upgrade_base":
				used.append_array(logistics())
			"logistics_upgrade_more", "logistics_buy_earth", "logistics_aldrin", \
			"logistics_place_security":
				pass  # tutte risolte da logistics() in una volta sola
			_:
				log_lines.append("NP %s: istruzione «%s» non ancora eseguibile." % [
					faction, i["id"]])
	return used


## Attività Speciali che il bot sa eseguire. Ambush e Transport restano fuori:
## la prima modifica l'Attack mentre lo si risolve, il secondo è un'Operazione di
## movimento a sé — vanno intrecciate, non aggiunte.
const RUNNABLE_SPECIALS := ["purify", "ransack", "coordinate", "redistribute",
	"entrench", "petition", "public_relations", "exploit", "raid"]

## Colonna delle Space Selection Priorities con cui scegliere gli spazi.
const SPECIAL_COLUMN := {
	"purify": "remove_or_replace", "ransack": "ransack",
	"coordinate": "place_population", "redistribute": "redistribute",
	"entrench": "place_bases", "public_relations": "place_population",
	"exploit": "exploit", "raid": "remove_or_replace",
}


## «Select 1 Special Activity»: si prende la prima dell'elenco che abbia effetto.
## Restituisce {ok, special, spaces, skipped}.
func run_special_activity(faction: String, list: Array) -> Dictionary:
	var skipped: Array[String] = []
	for entry in list:
		var sa: Dictionary = entry
		var sa_id := String(sa.get("id", ""))
		if not RUNNABLE_SPECIALS.has(sa_id):
			skipped.append(sa_id)
			continue
		# Le voci con una condizione (per esempio «solo con EG−») la rispettano.
		if sa.has("when") and not _special_condition(String(sa["when"]), faction):
			continue
		var done := _run_special(faction, sa_id)
		if not (done["spaces"] as Array).is_empty() or bool(done.get("ok", false)):
			log_lines.append("NP %s: %s in %d spazi." % [
				faction, sa_id, (done["spaces"] as Array).size()])
			return {"ok": true, "special": sa_id, "spaces": done["spaces"],
				"skipped": skipped}
	return {"ok": false, "special": "", "spaces": [], "skipped": skipped}


func _special_condition(cond: String, faction: String) -> bool:
	match cond:
		"eg_minus":
			return int(state.tracks.get("eg_side", -1)) < 0
		"three_rebels_activated":
			# Approssimazione dichiarata: si guarda se ci sono Ribelli Attivi.
			for sid in module.mars_spaces(state):
				var s := String(sid)
				if module.count_in(state, s, "rd_rebel", "active") \
						+ module.count_in(state, s, "cr_rebel", "active") >= 3:
					return true
			return false
		"secure_performed", "recon_performed":
			return true   # la carta le offre solo dopo quell'Operazione
	return true


## Sceglie gli spazi con la colonna giusta ed esegue l'Attività Speciale.
func _run_special(faction: String, sa_id: String) -> Dictionary:
	var sp := RDRSpecials.new(state, module)
	sp.cards = ops.cards
	var column := String(SPECIAL_COLUMN.get(sa_id, ""))
	var pool := _special_candidates(faction, sa_id)
	var picks: Array = []
	if column != "" and not pool.is_empty():
		picks = np.select_spaces(faction, column, pool, 2)
	var res: Dictionary = {"ok": false}
	match sa_id:
		"petition":
			res = sp.petition({})
		"exploit":
			res = sp.exploit({"spaces": picks})
		"ransack":
			res = sp.ransack({"spaces": picks})
		"redistribute":
			res = sp.redistribute({"spaces": picks})
		"purify":
			var e1: Array = []
			for sid in picks:
				e1.append({"id": sid, "mode": "convert"})
			res = sp.purify({"spaces": e1})
		"coordinate":
			var e2: Array = []
			for sid in picks:
				e2.append({"id": sid, "action": "", "at_max": "remove"})
			res = sp.coordinate({"spaces": e2})
		"entrench":
			var e3: Array = []
			for sid in picks:
				e3.append({"id": sid, "fortify": 9})
			res = sp.entrench({"spaces": e3})
		"public_relations":
			var e4: Array = []
			for sid in picks:
				e4.append({"id": sid, "repairs": 1, "house": true})
			res = sp.public_relations({"spaces": e4})
		"raid":
			var e5: Array = []
			for sid in picks:
				e5.append({"id": sid, "targets": ["rd_rebel", "cr_rebel"]})
			res = sp.raid({"spaces": e5})
	log_lines.append_array(sp.log_lines)
	return {"ok": bool(res.get("ok", false)),
		"spaces": picks if bool(res.get("ok", false)) else []}


## Spazi dove quell'Attività Speciale avrebbe davvero effetto.
func _special_candidates(faction: String, sa_id: String) -> Array:
	var out: Array = []
	for sid in module.mars_spaces(state):
		var s := String(sid)
		var st: SpaceState = state.spaces[s]
		var okk := false
		match sa_id:
			"purify":
				# §6.10: il Purify SOSTITUISCE forze nemiche, quindi senza nemici
				# nello spazio non c'è niente da convertire.
				okk = st.control == "reclaimer" \
					and module.count_in(state, s, "cr_rebel", "hidden") > 0 \
					and ops._enemy_force_count(s, "reclaimer") > 0
			"ransack":
				okk = module.marker(state, s, "damage") > 0 \
					and module.count_in(state, s, "cr_rebel", "hidden") > 0
			"redistribute":
				okk = module.population(state, s) > 0 and st.control == "red_dust" \
					and module.count_in(state, s, "rd_rebel", "hidden") > 0
			"coordinate":
				okk = st.support <= 0 and module.count_in(state, s, "rd_rebel", "hidden") > 0
			"entrench":
				okk = st.control == "coin" and module.count_in(state, s, "mg_troop") > 0
			"public_relations":
				okk = st.control == "coin" and module.count_in(state, s, "security") > 0
			"exploit":
				okk = module.count_in(state, s, "corp_base") > 0 \
					and module.marker(state, s, "damage") == 0
			"raid":
				okk = module.count_in(state, s, "specops") > 0
		if okk:
			out.append(s)
	return out


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
# §8.6.4 NP MARSGOV / §8.6.5 NP CORPORATIONS
# ---------------------------------------------------------------------------

## Train: ❶ Place Troops con la colonna Place Cubes, poi ★ Pacify fino a due
## volte in uno spazio, nell'ordine della carta — House a Supporto, Repair,
## Shift verso il Supporto Attivo. Fuori dalle Limitate il Pacify può prendere
## di mira uno spazio in più, non scelto per il Train.
func train(activation_number: int, limited: bool = false) -> Array:
	var candidates := func() -> Array:
		return Array(ops.train_candidates())
	var body := func(sid: String) -> bool:
		return bool(ops.train({"spaces": [{"id": sid, "troops": 4}]}).get("ok", false))
	var used := run_by_space("marsgov", "place_cubes", candidates, body,
		activation_number, limited)

	var pool: Array = []
	for sid in used:
		if state.spaces[String(sid)].control == "coin":
			pool.append(String(sid))
	if not limited:
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if state.spaces[s].control == "coin" and not pool.has(s):
				pool.append(s)
	if pool.is_empty():
		return used
	var pick := String(np.select_space("marsgov", "place_population", pool)["space"])
	if pick == "":
		return used
	var actions := _pacify_actions(pick)
	if actions.is_empty():
		return used
	var res: Dictionary = ops.train({"spaces": [{"id": pick, "troops": 0}],
		"pacify": {"id": pick, "actions": actions}})
	if res.get("ok", false):
		log_lines.append("NP marsgov: Pacify a %s (%s)." % [_name(pick), ", ".join(actions)])
		if not used.has(pick):
			used.append(pick)
	return used


## Assault (§8.6.4 MarsGov, §8.6.5 CORP). `mode`:
##   "bases" — ❶ solo dove cadrebbe una Base Ribelle
##   "any"   — ❸ dovunque l'Assault abbia effetto
## Il Suppress (❷) e il Bombard delle Truppe EG sono passati nel piano quando la
## Fazione è EarthGov Controller, come sulla carta; gli SpecOps CORP si Attivano
## per rimuovere forze in più.
func assault(faction: String, mode: String, activation_number: int,
		limited: bool = false) -> Array:
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s):
				continue
			var own := 0
			for t in ops._coin_unit_types(faction):
				own += module.count_in(state, s, String(t))
			if own <= 0:
				continue
			var active := module.count_in(state, s, "rd_rebel", "active") \
				+ module.count_in(state, s, "cr_rebel", "active")
			if mode == "bases":
				if not _assault_clears_base(s, own):
					continue
			elif active <= 0 and not _assault_clears_base(s, own):
				continue
			out.append(s)
		return out
	var eg := module.eg_controller(state) == faction
	var body := func(sid: String) -> bool:
		var plan := {"faction": faction, "spaces": [sid]}
		if faction == "corporations" and module.count_in(state, sid, "specops", "hidden") > 0:
			plan["activate_specops"] = [sid]
		if eg and module.count_in(state, "orbit", "satellite") > 0:
			plan["bombard"] = [sid]
		return bool(ops.assault(plan).get("ok", false))
	return run_by_space(faction, "remove_or_replace", candidates, body,
		activation_number, limited)


## Le due azioni di Pacify, nell'ordine della carta e solo se hanno effetto.
func _pacify_actions(sid: String) -> Array:
	var out: Array = []
	if ops.act.can_house(sid) and state.spaces[sid].support > 0:
		out.append("house")
	if ops.act.can_repair(sid, "marsgov"):
		out.append("repair")
	if out.size() < 2 and state.get_resources("marsgov") >= 3 \
			and state.spaces[sid].support < CoinEnums.Support.ACTIVE_SUPPORT:
		out.append("shift")
	return out.slice(0, 2)


## Logistics: potenzia una Base (e altre se restano 2+ Dust Storm Round), compra
## quattro unità su Earth, risolve l'Aldrin Cycler e piazza Security dove le Basi
## CORP hanno 0-3 cubi. Il vincolo sono i Profits: si prende solo il pagabile.
func logistics() -> Array:
	var profits := int(state.tracks.get("profits", 0))
	var rounds_left := 3 - int(state.tracks.get("dust_storm_rounds", 0))

	var upgradable: Array = []
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if module.is_desert(state, s) and module.count_in(state, s, "corp_base", "basic") > 0:
			upgradable.append(s)
	# La prima Base è gratis, ogni altra costa 3 Profits.
	var want := 1 if rounds_left < 2 else 1 + int(profits / 3.0)
	var deserts := np.select_spaces("corporations", "place_or_upgrade_bases", upgradable, want)
	var spent: int = maxi(0, deserts.size() - 1) * 3

	var thin: Array = []
	for sid in module.mars_spaces(state):
		var s2 := String(sid)
		if module.count_in(state, s2, "corp_base") == 0:
			continue
		var cubes := module.count_in(state, s2, "security") \
			+ module.count_in(state, s2, "mg_troop") + module.count_in(state, s2, "eg_troop")
		if cubes <= 3:
			thin.append(s2)
	var security_at := np.select_spaces("corporations", "place_cubes", thin,
		maxi(0, profits - spent))

	var res: Dictionary = ops.logistics({
		"deserts": deserts, "security_at": security_at,
		"earth": {"security": 3, "specops": 1}, "transit": true,
	})
	if not res.get("ok", false):
		log_lines.append("NP corporations: Logistics rifiutata (%s)." % res.get("error", ""))
		return []
	log_lines.append("NP corporations: Logistics — %d Basi potenziate, %d spazi rinforzati." % [
		deserts.size(), security_at.size()])
	var used2: Array = deserts.duplicate()
	for s3 in security_at:
		if not used2.has(String(s3)):
			used2.append(String(s3))
	return used2


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
