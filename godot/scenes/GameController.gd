extends Node

## Autoload: possiede il modulo di regole e lo stato della partita, e notifica la UI.
## Restia volutamente sottile: la logica di gioco vive in `games/<gioco>/`.

signal state_changed()
signal log_line(text: String)

var module: RulesModule
var state: GameState
var game_def: GameDef

## Flusso delle carte e round periodici (§4.0-§4.3).
var rounds: RDRRounds
## Sequenza della carta corrente (§4.1); null se la partita è finita.
var sequence: RDRSequence
## Operazioni e Attività Speciali della partita in corso.
var ops: RDROperations
var specials: RDRSpecials
## Mazzi Asset (Reclaimer) e Campaign (Red Dust).
var cards: RDRCards
## Esecuzione degli Eventi (§7.0).
var events: RDREvents
## §8.0: sistema Non-Player *Curiosity*, se ci sono Fazioni gestite dal bot.
var np: RDRNonPlayer
var np_ops: RDRNonPlayerOps
var np_move: RDRNonPlayerMove

## §Annulla: istantanee dello stato prima di ogni azione. Bastano lo stato di
## gioco (GameState sa serializzarsi) e la sequenza della carta; i round e i
## mazzi leggono tutto da lì. NB: il generatore casuale non torna indietro,
## quindi rifare un'azione con dadi può dare un risultato diverso.
const UNDO_LIMIT := 25
var _undo: Array = []

## Formato dei salvataggi (user://): stato + sequenza della carta in corso.
const SAVE_VERSION := 1
const SAVE_PATH := "user://partita.json"
## Salvataggio automatico a ogni cambio carta: una partita COIN dura ore, e
## chiudere per sbaglio non deve costare la serata.
const AUTOSAVE_PATH := "user://autosave.json"

## Geometrie della tavola (regions.json / board_layout.json), normalizzate [0..1].
var regions: Dictionary = {}
var off_map: Dictionary = {}
var layout: Dictionary = {}


func _ready() -> void:
	new_game()


## `seed_value` diverso da 0 rende la partita riproducibile (mazzi e dadi):
## serve ai test e, in prospettiva, al salvataggio/ripresa.
## `np_factions` elenca le Fazioni gestite dal sistema Non-Player: vuoto = partita
## fra soli giocatori, com'è stato finora.
func new_game(scenario: String = "standard", seed_value: int = 0,
		np_factions: Array = []) -> void:
	module = GameRegistry.create_module()
	game_def = module.build_game_def()
	state = GameState.new(game_def)
	state.roles = GameRegistry.default_roles(game_def)
	module.apply_setup(state, scenario)

	var reg: Dictionary = _load_json(GameRegistry.data_path("regions.json"))
	regions = reg.get("regions", {})
	off_map = reg.get("off_map", {})
	layout = _load_json(GameRegistry.data_path("board_layout.json"))

	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	state.tracks["seed"] = seed_value

	cards = RDRCards.new(state, rdr(), rng)
	rounds = RDRRounds.new(state, rdr(), rng)
	rounds.cards = cards
	ops = RDROperations.new(state, rdr(), rng)
	ops.rounds = rounds
	ops.cards = cards
	specials = RDRSpecials.new(state, rdr())
	specials.cards = cards
	events = RDREvents.new(state, rdr())
	events.cards = cards
	events.rounds = rounds

	np = RDRNonPlayer.new(state, rdr(), rng)
	np.setup(np_factions)
	np_ops = RDRNonPlayerOps.new(np, ops)
	np_move = RDRNonPlayerMove.new(np, ops)
	# §8.5.9: i Round periodici delle Fazioni NP hanno una scheda tutta loro.
	if not np_factions.is_empty():
		rounds.np_round = RDRNonPlayerRound.new(np, rounds)
	np_ops.move = np_move
	for fid in np_factions:
		np.setup_deck(String(fid), RDRNonPlayerOps.DECKS.get(String(fid), []))
	_undo.clear()
	rounds.begin_game()
	_drain_log()
	_start_card()

	emit_signal("log_line", "Partita avviata — scenario '%s'." % scenario)
	emit_signal("state_changed")


# ---------------------------------------------------------------------------
# Sequenza di gioco (§4.1)
# ---------------------------------------------------------------------------

func _start_card() -> void:
	sequence = null
	if rounds == null or rounds.is_game_over():
		return
	var card: CardDef = game_def.card(state.current_card)
	if card == null:
		return
	sequence = RDRSequence.new(state, module, card)


## La Fazione di turno Passa (§4.1). Restituisce false se non è una mossa legale.
func do_pass() -> bool:
	if sequence == null or sequence.pending_faction() == "":
		return false
	var fid := sequence.pending_faction()
	var before := sequence.pass_effects.size()
	snapshot("Passo di %s" % game_def.faction(fid).short_name)
	if not sequence.act_pass():
		_undo.pop_back()
		return false
	emit_signal("log_line", "%s Passa." % game_def.faction(fid).short_name)
	# Il Passo delle Corporations attiva l'Aldrin Cycler; quello dei Reclaimer
	# darebbe una pescata di Asset (mazzo non ancora implementato).
	for i in range(before, sequence.pass_effects.size()):
		match sequence.pass_effects[i]:
			"aldrin_cycler":
				# Campaign #11 "Comms Cutoff": il Passo delle Corporations non
				# attiva l'Aldrin Cycler.
				if rdr().campaign_active(state, 11):
					emit_signal("log_line", "Campaign «Comms Cutoff»: l'Aldrin Cycler non si attiva.")
				else:
					rounds.aldrin_cycler()
			"draw_asset":
				cards.draw_asset(1)
				for line in cards.log_lines:
					emit_signal("log_line", line)
				cards.log_lines.clear()
				emit_signal("log_line", "I Reclaimer pescano 1 Asset card (%d in mano)." % cards.hand().size())
	_after_action()
	return true


## Operazioni eseguibili dalla UI con la sola scelta degli spazi. Le altre
## (Logistics, Secure, Recon, March, Travel) hanno bisogno del pianificatore di
## movimento, non ancora in interfaccia.
const UI_OPERATIONS := {
	"marsgov": ["train", "secure", "recon", "assault"],
	"corporations": ["logistics", "secure", "recon", "assault"],
	"red_dust": ["rally", "march", "attack", "campaign"],
	"reclaimer": ["rally", "travel", "attack", "preach"],
}

## Operazioni che oltre agli spazi richiedono di dichiarare gli spostamenti.
const MOVEMENT_OPERATIONS := ["secure", "recon", "march", "travel"]

## Attività Speciali collegate alla UI, per Fazione, con il numero massimo di
## spazi selezionabili (§6.0).
const UI_SPECIALS := {
	# Il Transport non sceglie spazi: dichiara spostamenti sulla propria rete,
	# più al massimo 2 spazi attivati in più (1 se non è EarthGov Controller).
	"marsgov": {"entrench": 2, "petition": 0, "transport": 2},
	"corporations": {"public_relations": 2, "exploit": 2, "raid": 2},
	"red_dust": {"redistribute": 4, "coordinate": 2},
	"reclaimer": {"purify": 2, "ransack": 2},
}

const SPECIAL_NAMES := {
	"entrench": "Entrench", "petition": "Petition", "transport": "Transport",
	"public_relations": "Public Relations", "exploit": "Exploit", "raid": "Raid",
	"redistribute": "Redistribute", "coordinate": "Coordinate", "ambush": "Ambush",
	"purify": "Purify", "ransack": "Ransack",
}

const OPERATION_NAMES := {
	"train": "Train", "logistics": "Logistics", "secure": "Secure", "recon": "Recon",
	"assault": "Assault", "rally": "Rally", "march": "March", "travel": "Travel",
	"attack": "Attack", "campaign": "Campaign", "preach": "Preach",
}


## Esegue un'Operazione per la Fazione di turno e registra l'azione nella
## sequenza. Restituisce il risultato dell'Operazione ({ok, error, spent}).
## `plan_extra` porta le scelte in più delle Operazioni di movimento
## ({moves: [...]}) e di Logistics ({earth: {...}, transit: bool}).
func execute_operation(op_id: String, spaces: Array, with_special: bool = false,
		plan_extra: Dictionary = {}) -> Dictionary:
	if sequence == null:
		return {"ok": false, "error": "Nessuna carta in corso."}
	var fid := sequence.pending_faction()
	if fid == "":
		return {"ok": false, "error": "Non è il turno di nessuno."}
	# §5.0: ogni Fazione ha le sue Operazioni. Senza questo controllo un Train
	# chiesto durante il turno del Red Dust veniva eseguito lo stesso, e a
	# piazzare le Truppe era MarsGov: la barra offre solo le Operazioni giuste,
	# ma qui ci passano anche l'anteprima, i test e ogni futuro chiamante.
	if not Array(UI_OPERATIONS.get(fid, [])).has(op_id):
		return {"ok": false, "error": "%s non è un'Operazione di %s." % [
			OPERATION_NAMES.get(op_id, op_id), game_def.faction(fid).short_name]}
	var action := CoinEnums.ActionType.OPERATION_WITH_SPECIAL if with_special \
		else CoinEnums.ActionType.OPERATION
	if not sequence.is_legal(action):
		action = CoinEnums.ActionType.LIMITED_OPERATION
		if not sequence.is_legal(action) or spaces.size() > 1:
			return {"ok": false, "error": "Azione non consentita adesso."}

	snapshot(OPERATION_NAMES.get(op_id, op_id))
	var res: Dictionary = _run_operation(op_id, fid, spaces, plan_extra)
	if not res.get("ok", false):
		_undo.pop_back()
		return res
	for line in ops.log_lines:
		emit_signal("log_line", line)
	ops.log_lines.clear()
	emit_signal("log_line", "%s esegue %s in %d spazi." % [
		game_def.faction(fid).short_name, OPERATION_NAMES.get(op_id, op_id), spaces.size()])
	sequence.act(action)
	_after_action()
	return res


func _run_operation(op_id: String, fid: String, spaces: Array,
		extra: Dictionary = {}) -> Dictionary:
	return _run_operation_on(ops, op_id, fid, spaces, extra)


## Stessa Operazione ma su un motore indicato: serve all'anteprima, che la
## esegue su una COPIA dello stato senza toccare la partita.
func _run_operation_on(o: RDROperations, op_id: String, fid: String, spaces: Array,
		extra: Dictionary = {}) -> Dictionary:
	var moves: Array = extra.get("moves", [])
	match op_id:
		"secure":
			return o.secure({"faction": fid, "dest": spaces, "moves": moves})
		"recon":
			return o.recon({"faction": fid, "dest": spaces, "moves": moves})
		"march":
			return o.march({"dest": spaces, "moves": moves})
		"travel":
			return o.travel({"origins": spaces, "moves": moves})
		"logistics":
			var plan := {"deserts": spaces, "earth": extra.get("earth", {}),
				"transit": bool(extra.get("transit", false))}
			return o.logistics(plan)
		"train":
			var entries: Array = []
			for sid in spaces:
				entries.append({"id": sid, "troops": 4})
			return o.train({"spaces": entries})
		"assault":
			# §5.5: chi è EarthGov Controller può Bombardare gli spazi
			# dell'Assault (un Satellite dall'Orbita per due forze nemiche in
			# più) e Sopprimere in UNO spazio non scelto.
			var ap := {"faction": fid, "spaces": spaces}
			if not (extra.get("bombard", []) as Array).is_empty():
				ap["bombard"] = extra["bombard"]
			if not (extra.get("suppress", {}) as Dictionary).is_empty():
				ap["suppress"] = extra["suppress"]
			return o.assault(ap)
		"rally":
			# §5.6: ogni spazio scelto ha la sua modalità. Senza, il Rally
			# sarebbe sempre «piazza un Ribelle» e non si potrebbero mai
			# costruire Basi né riportare i Ribelli Nascosti.
			var modes: Dictionary = extra.get("modes", {})
			var entries: Array = []
			for sid in spaces:
				entries.append({"id": sid, "mode": String(modes.get(sid, "place"))})
			var plan := {"faction": fid, "spaces": entries}
			if String(extra.get("dig_in", "")) != "":
				plan["dig_in"] = String(extra["dig_in"])
			return o.rally(plan)
		"attack":
			# §6.9/§6.12 Ambush: non è un'azione a parte, sceglie i dadi
			# dell'Attack in un massimo di due degli spazi selezionati.
			var atk := {"faction": fid, "spaces": spaces}
			var dice: Dictionary = extra.get("ambush_dice", {})
			if not dice.is_empty():
				atk["ambush_dice"] = dice
			return o.attack(atk)
		"campaign":
			return o.campaign({"spaces": spaces})
		"preach":
			return o.preach({"spaces": spaces})
	return {"ok": false, "error": "Operazione '%s' non ancora disponibile in UI." % op_id}


## §6.3: la rete su cui il Transport sposta le Truppe — Phobos e ogni spazio con
## una Base MarsGov, più quelli attivati apposta.
func transport_network(extra: Array = []) -> PackedStringArray:
	return ops.transport_pool(extra) if ops != null else PackedStringArray()


## §6.9/§6.12: in quali degli spazi scelti per l'Attack si può fare Ambush —
## serve un Ribelle Nascosto, e non più di due spazi in tutto.
func ambush_candidates(fid: String, chosen: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if fid != "red_dust" and fid != "reclaimer":
		return out
	var rebel := "rd_rebel" if fid == "red_dust" else "cr_rebel"
	for sid in chosen:
		if rdr().count_in(state, String(sid), rebel, "hidden") > 0:
			out.append(String(sid))
	return out


## §5.5 Bombard: si può solo se si è EarthGov Controller e c'è un Satellite in
## Orbita da far scendere.
func can_bombard(fid: String) -> bool:
	return rdr().eg_controller(state) == fid \
		and rdr().count_in(state, "orbit", "satellite") > 0


## §5.5 Suppress: uno spazio NON scelto per l'Assault, con Truppe EG e Ribelli.
func suppress_candidates(fid: String, chosen: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if rdr().eg_controller(state) != fid:
		return out
	var m: RDRModule = rdr()
	for sid in m.mars_spaces(state):
		var s := String(sid)
		if chosen.has(s):
			continue
		if m.count_in(state, s, "eg_troop") == 0:
			continue
		if m.count_in(state, s, "rd_rebel") + m.count_in(state, s, "cr_rebel") == 0:
			continue
		out.append(s)
	return out


## Deserti adiacenti in cui i Ribelli soppressi possono essere spinti.
func suppress_destinations(sid: String) -> PackedStringArray:
	var out := PackedStringArray()
	var sd: SpaceDef = game_def.space(sid)
	if sd == null:
		return out
	for other in sd.adjacent:
		if rdr().is_desert(state, String(other)):
			out.append(String(other))
	return out


## §5.6: le modalità di Rally che hanno davvero effetto in questo spazio, con
## l'etichetta da mostrare. Offrire quelle impossibili significa far scoprire il
## rifiuto per tentativi, e alcune (Base, Conversion Center) dipendono da quanti
## Ribelli ci sono in quel momento.
func rally_modes(fid: String, sid: String) -> Array:
	var m: RDRModule = rdr()
	var rebel := "rd_rebel" if fid == "red_dust" else "cr_rebel"
	var base := "rd_base" if fid == "red_dust" else "cr_base"
	var out: Array = [{"id": "place", "label": "Piazza 1 Ribelle"}]
	if m.count_in(state, sid, rebel) >= 2 and ops.act.can_place_base(sid) \
			and m.available(state, base) > 0:
		out.append({"id": "base", "label": "Base (2 Ribelli)"})
	var has_base := (m.cr_bases_in(state, sid) > 0) if fid == "reclaimer" \
		else m.count_in(state, sid, base) > 0
	if fid == "reclaimer" and m.capability_active(state, 5):
		has_base = true
	if has_base:
		var n := m.population(state, sid) + (m.cr_bases_in(state, sid) if fid == "reclaimer" \
			else m.count_in(state, sid, base))
		if n > 0:
			out.append({"id": "fill", "label": "Riempi (%d Ribelli)" % n})
		if m.count_in(state, sid, rebel, "active") > 0:
			out.append({"id": "hide", "label": "Torna Nascosto"})
	if fid == "reclaimer" and m.count_in(state, sid, base, "basic") > 0:
		out.append({"id": "upgrade", "label": "Conversion Center"})
	return out


## §5.6: le Basi RD in un Deserto che si possono portare a Dug-In. Il Red Dust
## può farlo su UNA Base, anche fuori dagli spazi scelti e in un'Operazione
## Limitata.
func dig_in_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	var m: RDRModule = rdr()
	for sid in m.mars_spaces(state):
		var s := String(sid)
		if m.is_desert(state, s) and m.count_in(state, s, "rd_base", "basic") > 0:
			out.append(s)
	return out


## Spazi legalmente selezionabili per l'Operazione, usati per l'evidenziazione.
func operation_candidates(op_id: String, fid: String) -> PackedStringArray:
	var m: RDRModule = rdr()
	match op_id:
		"train":
			return ops.train_candidates()
		"rally":
			return ops.rally_candidates(fid)
		"assault":
			var out := PackedStringArray()
			for sid in m.mars_spaces(state):
				if not ops.act.selectable(sid):
					continue
				var own := 0
				for t in ops._coin_unit_types(fid):
					own += m.count_in(state, sid, t)
				var targets := m.count_in(state, sid, "rd_rebel", "active") \
					+ m.count_in(state, sid, "cr_rebel", "active")
				if own > 0 and targets > 0:
					out.append(sid)
			return out
		"attack":
			var rebel := "rd_rebel" if fid == "red_dust" else "cr_rebel"
			var out2 := PackedStringArray()
			for sid in m.mars_spaces(state):
				if ops.act.selectable(sid) and m.count_in(state, sid, rebel) > 0 \
						and ops._enemy_force_count(sid, fid) > 0:
					out2.append(sid)
			return out2
		"secure":
			var out_s := PackedStringArray()
			for sid in m.mars_spaces(state):
				if m.is_labyrinth(state, sid) and ops.act.selectable(sid):
					out_s.append(sid)
			return out_s
		"recon":
			var out_r := PackedStringArray()
			for sid in m.mars_spaces(state):
				if m.is_desert(state, sid) and ops.act.selectable(sid):
					out_r.append(sid)
			return out_r
		"march":
			var out_m := PackedStringArray()
			for sid in m.mars_spaces(state):
				if ops.act.selectable(sid):
					out_m.append(sid)
			return out_m
		"travel":
			# Travel sceglie le ORIGINI e ignora le tempeste (§5.8).
			var out_t := PackedStringArray()
			for sid in m.mars_spaces(state):
				if m.count_in(state, sid, "cr_rebel") + m.count_in(state, sid, "cr_base") > 0:
					out_t.append(sid)
			return out_t
		"logistics":
			var out_l := PackedStringArray()
			for sid in m.mars_spaces(state):
				if m.is_desert(state, sid) and m.count_in(state, sid, "corp_base") > 0:
					out_l.append(sid)
			return out_l
		"campaign", "preach":
			var rebel2 := "rd_rebel" if op_id == "campaign" else "cr_rebel"
			var out3 := PackedStringArray()
			for sid in m.mars_spaces(state):
				if ops.act.selectable(sid) and m.population(state, sid) > 0 \
						and m.count_in(state, sid, rebel2) > 0:
					out3.append(sid)
			return out3
	return PackedStringArray()


## Spazi legalmente selezionabili per un'Attività Speciale (§6.0).
func special_candidates(sa_id: String, fid: String) -> PackedStringArray:
	var m: RDRModule = rdr()
	var out := PackedStringArray()
	for sid in m.mars_spaces(state):
		var st: SpaceState = state.spaces[sid]
		var okk := false
		match sa_id:
			"entrench":
				okk = st.control == "coin" and m.count_in(state, sid, "mg_troop") > 0
			"public_relations":
				okk = st.control == "coin" and m.count_in(state, sid, "security") > 0
			"exploit":
				okk = m.count_in(state, sid, "corp_base") > 0 and m.marker(state, sid, "damage") == 0
			"raid":
				okk = m.count_in(state, sid, "specops") > 0 or _adjacent_specops(sid)
			"redistribute":
				okk = m.population(state, sid) > 0 and st.control == "red_dust" \
					and m.count_in(state, sid, "rd_rebel", "hidden") > 0
			"coordinate":
				okk = st.support <= 0 and m.count_in(state, sid, "rd_rebel", "hidden") > 0
			"purify":
				okk = st.control == "reclaimer" and m.count_in(state, sid, "cr_rebel", "hidden") > 0
			"ransack":
				okk = m.marker(state, sid, "damage") > 0 \
					and m.count_in(state, sid, "cr_rebel", "hidden") > 0
		if okk:
			out.append(sid)
	return out


func _adjacent_specops(sid: String) -> bool:
	for a in state.game_def.space(sid).adjacent:
		if rdr().count_in(state, String(a), "specops", "hidden") > 0:
			return true
	return false


## Unità che la Fazione di turno può muovere con l'Operazione in corso.
func movable_types(op_id: String, fid: String) -> Array[String]:
	match op_id:
		"secure", "recon":
			return ops._coin_unit_types(fid)
		"march":
			return ["rd_rebel"] as Array[String]
		"travel":
			return ["cr_rebel", "cr_base"] as Array[String]
	return [] as Array[String]


## Origini legali per portare `type_id` in `dest` con l'Operazione in corso.
## La regola vive in RDROperations: la usa anche il sistema Non-Player.
func legal_origins(op_id: String, fid: String, dest: String, type_id: String) -> PackedStringArray:
	return ops.legal_origins(op_id, fid, dest, type_id)


## §6.0: esegue un'Attività Speciale della Fazione di turno. Non consuma il turno
## da sola: accompagna l'Operazione (qui è eseguita subito, prima o dopo).
func execute_special(sa_id: String, spaces: Array,
		extra_moves: Dictionary = {}) -> Dictionary:
	if sequence == null or sequence.pending_faction() == "":
		return {"ok": false, "error": "Non è il turno di nessuno."}
	snapshot(SPECIAL_NAMES.get(sa_id, sa_id))
	var res: Dictionary = _run_special(sa_id, spaces, extra_moves)
	if not res.get("ok", false):
		_undo.pop_back()
		return res
	for line in specials.log_lines:
		emit_signal("log_line", line)
	specials.log_lines.clear()
	emit_signal("log_line", "%s: %s in %d spazi." % [
		game_def.faction(sequence.pending_faction()).short_name,
		SPECIAL_NAMES.get(sa_id, sa_id), spaces.size()])
	refresh()
	return res


func _run_special(sa_id: String, spaces: Array, extra_moves: Dictionary = {}) -> Dictionary:
	return _run_special_on(specials, sa_id, spaces, extra_moves)


## Come sopra: l'anteprima esegue su una copia, non sulla partita.
func _run_special_on(sp: RDRSpecials, sa_id: String, spaces: Array,
		extra_moves: Dictionary = {}) -> Dictionary:
	var entries: Array = []
	match sa_id:
		"entrench":
			for sid in spaces:
				entries.append({"id": sid, "fortify": 9})
			return sp.entrench({"spaces": entries})
		"petition":
			return sp.petition({})
		"public_relations":
			for sid in spaces:
				entries.append({"id": sid, "repairs": 1, "house": true})
			return sp.public_relations({"spaces": entries})
		"exploit":
			return sp.exploit({"spaces": spaces})
		"raid":
			for sid in spaces:
				entries.append({"id": sid, "targets": ["rd_rebel", "cr_rebel"]})
			return sp.raid({"spaces": entries})
		"redistribute":
			return sp.redistribute({"spaces": spaces})
		"coordinate":
			for sid in spaces:
				entries.append({"id": sid, "action": "", "at_max": "remove"})
			return sp.coordinate({"spaces": entries})
		"purify":
			for sid in spaces:
				entries.append({"id": sid, "mode": "convert"})
			return sp.purify({"spaces": entries})
		"ransack":
			return sp.ransack({"spaces": spaces})
		"transport":
			# §6.3: non sceglie spazi come le altre Speciali — dichiara
			# spostamenti sulla rete Phobos + Basi MG, più gli spazi attivati
			# in più (fino a 2 se MarsGov è EarthGov Controller, 1 altrimenti).
			return sp.transport({"extra": extra_moves.get("extra", []),
				"moves": extra_moves.get("moves", [])})
	return {"ok": false, "error": "Attività Speciale '%s' non disponibile in UI." % sa_id}


## §7.0: la Fazione di turno gioca l'Evento della carta corrente. Applica gli
## effetti riconosciuti e restituisce il testo che resta da risolvere al tavolo.
## `choices` è il dizionario delle scelte dell'Evento ({id: valore}); accetta
## anche il vecchio Array di spazi, che finisce sulla prima scelta dichiarata.
func execute_event(shaded: bool, choices = {}) -> Dictionary:
	if sequence == null or sequence.pending_faction() == "":
		return {"ok": false, "error": "Non è il turno di nessuno."}
	if not sequence.is_legal(CoinEnums.ActionType.EVENT):
		return {"ok": false, "error": "L'Evento non è consentito adesso."}
	var fid := sequence.pending_faction()
	snapshot("Evento #%d" % state.current_card)
	var res: Dictionary = events.play(state.current_card, shaded, choices, fid)
	if not res.get("ok", false):
		_undo.pop_back()
		return res
	for line in events.log_lines:
		emit_signal("log_line", line)
	events.log_lines.clear()
	emit_signal("log_line", "%s gioca l'Evento #%d (%s)." % [
		game_def.faction(fid).short_name, state.current_card,
		"ombreggiato" if shaded else "non ombreggiato"])
	sequence.act(CoinEnums.ActionType.EVENT)
	# L'Evento di un giocatore può concedere un'Operazione gratuita a una
	# Fazione gestita dal bot: la esegue lui, non chi ha giocato la carta.
	_run_np_free_ops()
	_after_action()
	return res


# ---------------------------------------------------------------------------
# Anteprima delle azioni
# ---------------------------------------------------------------------------

## Simula un'Operazione (o un'Attività Speciale) su una COPIA dello stato e
## racconta cosa costerebbe e cosa cambierebbe. Non tocca la partita: serve a
## non far premere «Esegui» alla cieca.
## Restituisce {ok, error, cost, resources, affordable, log, effects}.
func preview_action(kind: String, action_id: String, fid: String, spaces: Array,
		extra: Dictionary = {}) -> Dictionary:
	if state == null or spaces.is_empty():
		return {"ok": false, "error": "Nessuno spazio scelto.", "effects": []}
	var copy := GameState.from_dict(game_def, state.to_dict())
	copy.roles = state.roles
	# Seme fisso: l'anteprima non deve cambiare a ogni ridisegno. Le azioni coi
	# dadi (Attack) restano comunque indicative.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805
	var c := RDRCards.new(copy, rdr(), rng)
	var r := RDRRounds.new(copy, rdr(), rng)
	r.cards = c
	var res: Dictionary
	if kind == "special":
		var sp := RDRSpecials.new(copy, rdr())
		sp.cards = c
		res = _run_special_on(sp, action_id, spaces)
		res["log"] = sp.log_lines.duplicate()
	else:
		var o := RDROperations.new(copy, rdr(), rng)
		o.rounds = r
		o.cards = c
		res = _run_operation_on(o, action_id, fid, spaces, extra)
		res["log"] = o.log_lines.duplicate()
	var cost := int(res.get("spent", 0))
	res["cost"] = cost
	res["resources"] = state.get_resources(fid)
	res["affordable"] = bool(res.get("ok", false))
	res["effects"] = _effect_summary(state, copy) if bool(res.get("ok", false)) else []
	return res


## Differenze leggibili fra lo stato attuale e quello simulato. Sono le grandezze
## su cui si decide: Supporto, Opposizione, Controllo, Profits, Risorse, pezzi.
func _effect_summary(before: GameState, after: GameState) -> Array:
	var m: RDRModule = rdr()
	var out: Array = []
	var pairs := [
		["Supporto", m.total_support(before), m.total_support(after)],
		["Opposizione", m.total_opposition(before), m.total_opposition(after)],
		["Profits", int(before.tracks.get("profits", 0)), int(after.tracks.get("profits", 0))],
	]
	for f in game_def.factions:
		if f.id in ["marsgov", "red_dust"]:
			pairs.append(["Ris. %s" % f.short_name,
				before.get_resources(f.id), after.get_resources(f.id)])
	for p in pairs:
		if int(p[1]) != int(p[2]):
			out.append("%s %+d" % [p[0], int(p[2]) - int(p[1])])
	# Spazi che cambiano padrone: è l'effetto che si vede meno nei numeri.
	var flips := 0
	for sid in before.spaces.keys():
		if before.spaces[sid].control != after.spaces[sid].control:
			flips += 1
	if flips > 0:
		out.append("Controllo cambia in %d spazi" % flips)
	# Pezzi tolti dalla mappa, per tipo.
	for type_id in RDRModule.PIECE_OWNER.keys():
		var b := 0
		var a := 0
		for sid in m.mars_spaces(before):
			b += m.count_in(before, String(sid), String(type_id))
			a += m.count_in(after, String(sid), String(type_id))
		if a != b:
			out.append("%s %+d" % [type_id, a - b])
	return out


# ---------------------------------------------------------------------------
# Annulla e salvataggio
# ---------------------------------------------------------------------------

## Fotografa lo stato prima di un'azione, così la si può disfare.
func snapshot(label: String) -> void:
	if state == null:
		return
	_undo.append({
		"label": label,
		"state": state.to_dict(),
		"has_sequence": sequence != null,
		"sequence": sequence.snapshot() if sequence != null else {},
	})
	while _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func can_undo() -> bool:
	return not _undo.is_empty()


## Cosa si sta per disfare ("" se non c'è nulla): serve al tasto Annulla.
func undo_label() -> String:
	return String((_undo[-1] as Dictionary)["label"]) if can_undo() else ""


func undo() -> bool:
	if not can_undo():
		return false
	var snap: Dictionary = _undo.pop_back()
	state.load_dict(snap["state"])
	_start_card()
	if sequence != null and bool(snap["has_sequence"]):
		sequence.restore_snapshot(snap["sequence"])
	emit_signal("log_line", "Annullato: %s." % snap["label"])
	refresh()
	return true


func clear_undo() -> void:
	_undo.clear()


## Salva la partita (stato + sequenza della carta in corso).
func save_game(path: String) -> bool:
	if state == null:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		emit_signal("log_line", "Salvataggio fallito: %s non scrivibile." % path)
		return false
	f.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"state": state.to_dict(),
		"has_sequence": sequence != null,
		"sequence": sequence.snapshot() if sequence != null else {},
	}, "\t"))
	f.close()
	emit_signal("log_line", "Partita salvata in %s." % path)
	return true


func load_game(path: String) -> bool:
	if not FileAccess.file_exists(path):
		emit_signal("log_line", "Nessun salvataggio in %s." % path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("state"):
		emit_signal("log_line", "Salvataggio illeggibile: %s." % path)
		return false
	var d: Dictionary = parsed
	# Si riparte da una partita pulita e le si sovrascrive lo stato: così mazzi,
	# round e Operazioni restano agganciati agli stessi oggetti.
	new_game("standard", int(state.tracks.get("seed", 0)) if state != null else 0)
	state.load_dict(d["state"])
	_start_card()
	if sequence != null and bool(d.get("has_sequence", false)):
		sequence.restore_snapshot(d.get("sequence", {}))
	clear_undo()
	emit_signal("log_line", "Partita ripresa da %s." % path)
	refresh()
	return true


## §1.5: i Reclaimer giocano una Asset card dalla mano. Una Capability resta in
## gioco come modificatore permanente (e la applicano direttamente le regole);
## un Evento viene risolto qui, con la stessa macchina delle carte Evento.
##
## §1.5: l'Evento di una Asset card si gioca «when they are eligible to execute
## an Event», quindi è a tutti gli effetti l'azione Evento del loro turno — e la
## FAQ ufficiale lo conferma dal lato opposto: dopo un Asset Event dei Reclaimer
## la 2ª Disponibile ha le stesse opzioni che avrebbe dopo un Evento normale
## (Operazione in uno o più spazi, con Attività Speciale se vuole). Registrarlo
## nella sequenza è quel che glielo garantisce.
func play_asset_card(number: int, choices = {}) -> Dictionary:
	if cards == null:
		return {"ok": false, "error": "Mazzi non collegati."}
	# Una Capability entra in gioco senza consumare il turno; un Evento sì.
	var is_capability := String(cards.assets.get(number, {}).get("kind", "")) == "capability"
	var as_turn := false
	if not is_capability and sequence != null \
			and sequence.pending_faction() == "reclaimer":
		if not sequence.is_legal(CoinEnums.ActionType.EVENT):
			return {"ok": false,
				"error": "I Reclaimer non possono giocare un Asset Event adesso."}
		as_turn = true
	snapshot("Asset card #%d" % number)
	var res: Dictionary = cards.play_asset_event(number)
	if not res.get("ok", false):
		_undo.pop_back()
		return res
	for line in cards.log_lines:
		emit_signal("log_line", line)
	cards.log_lines.clear()
	if not bool(res.get("capability", false)):
		var ev: Dictionary = events.play_asset(number, choices, "reclaimer")
		for line in events.log_lines:
			emit_signal("log_line", line)
		events.log_lines.clear()
		res["event"] = ev
		res["free_ops"] = ev.get("free_ops", [])
	if as_turn:
		emit_signal("log_line", "I Reclaimer giocano l'Evento della Asset card #%d." % number)
		sequence.act(CoinEnums.ActionType.EVENT)
		_after_action()
	else:
		refresh()
	return res


## §8.0: la Fazione Non-Player di turno gioca da sé. Restituisce il resoconto,
## già registrato nella sequenza della carta.
func np_take_turn() -> Dictionary:
	if sequence == null or sequence.pending_faction() == "":
		return {"ok": false, "error": "Non è il turno di nessuno."}
	var fid := sequence.pending_faction()
	if not np.is_np(fid):
		return {"ok": false, "error": "%s non è una Fazione Non-Player." % fid}
	snapshot("Turno di %s (bot)" % game_def.faction(fid).short_name)
	var slot := "first" if sequence.is_first_slot() else "second"
	var res: Dictionary = np_ops.take_turn(fid, slot, _np_context(), _np_rng())
	for line in np.log_lines + np_ops.log_lines + np_move.log_lines + ops.log_lines:
		emit_signal("log_line", line)
	np.log_lines.clear()
	np_ops.log_lines.clear()
	np_move.log_lines.clear()
	ops.log_lines.clear()
	for line in res.get("trace", []):
		emit_signal("log_line", "  · %s" % line)
	if not res.get("ok", false):
		# §8.6.1: se nessuna carta Curiosity porta a un'Operazione — capita
		# quando la plancia non offre più niente a quella Fazione: nessuna forza
		# fra le Disponibili, nessuna Base, nessuna condizione soddisfatta — non
		# c'è altro da fare che Passare. Restituire l'errore e basta lasciava la
		# sequenza ferma sulla stessa Fazione, che veniva richiamata all'infinito
		# riempiendo il Log senza toccare la plancia.
		emit_signal("log_line", "%s (bot): %s Passa." % [
			game_def.faction(fid).short_name, res.get("error", "nessuna azione possibile.")])
		for line in res.get("trace", []):
			emit_signal("log_line", "  · %s" % line)
		_undo.pop_back()
		# `do_pass()` e non `sequence.act_pass()`: il Passo delle Corporations
		# attiva l'Aldrin Cycler e quello dei Reclaimer dà una Asset card.
		if not do_pass():
			# Nemmeno il Passo è legale (ultima carta Evento): si registra la
			# casella legale che resta, altrimenti la carta non si chiude più.
			var fallback := -1
			for a in sequence.legal_actions():
				if int(a) != CoinEnums.ActionType.PASS:
					fallback = int(a)
					break
			if fallback >= 0:
				sequence.act(fallback)
				_after_action()
		res["ok"] = true
		res["action"] = "pass"
		res["passed"] = true
		return res

	# §8.5.5: se la tabella ha scelto l'Evento, lo si gioca davvero.
	if String(res.get("action", "")) == "event":
		var which := _np_event_option(fid, state.current_card)
		if which >= 0:
			var ev_res: Dictionary = events.play(state.current_card, which == 1, {}, fid)
			for line in events.log_lines:
				emit_signal("log_line", line)
			events.log_lines.clear()
			res["event_option"] = "ombreggiato" if which == 1 else "non ombreggiato"
			res["event_ok"] = ev_res.get("ok", false)
			# Le istruzioni della carta, se ci sono, vanno lette al tavolo.
			var note: Dictionary = np.event_instruction(fid, state.current_card)
			if not note.is_empty():
				emit_signal("log_line", "  · Istruzione di carta: %s" % note.get("text", ""))
		# §7.0: le Operazioni gratuite concesse dall'Evento, se toccano a una
		# Fazione gestita dal bot, si eseguono subito.
		_run_np_free_ops()

	# Si registra l'azione nella sequenza, come farebbe un giocatore. Se la
	# tabella ha scelto una casella che in questo slot non è legale — capita
	# quando la 1ª Disponibile ha fatto qualcosa che restringe le opzioni della
	# 2ª — si ripiega sulla prima legale invece di lasciar cadere la richiesta:
	# senza registrare niente la Fazione di turno non cambierebbe mai, e il bot
	# rigiocherebbe all'infinito la stessa carta.
	var token := String(res.get("action", ""))
	if token == "pass":
		# `do_pass()` e non `sequence.act_pass()`: il Passo NON è solo saltare il
		# turno. §4.1 dà +3 Risorse a MarsGov, +1 a Red Dust, l'Aldrin Cycler alle
		# Corporations e una Asset card ai Reclaimer. Registrando solo la casella,
		# un bot che passava restava a mani vuote.
		_undo.pop_back()
		do_pass()
		res["action"] = "pass"
		return res
	else:
		var want: int = int(NP_TOKEN_ACTION.get(token, CoinEnums.ActionType.OPERATION_WITH_SPECIAL))
		if not sequence.act(want):
			var fallback := -1
			for a in sequence.legal_actions():
				fallback = int(a)
				break
			if fallback < 0 or not sequence.act(fallback):
				emit_signal("log_line",
					"%s (bot): nessuna casella legale, Passa." %
					game_def.faction(fid).short_name)
				sequence.act_pass()
			else:
				emit_signal("log_line",
					"%s (bot): la casella «%s» non è legale in questo slot, ripiega su «%s»." % [
					game_def.faction(fid).short_name, token,
					String(NP_ACTION_TOKEN.get(fallback, "?"))])
				res["action"] = String(NP_ACTION_TOKEN.get(fallback, token))
	emit_signal("log_line", "%s (bot): %s." % [
		game_def.faction(fid).short_name, res.get("operation", res.get("action", ""))])
	_after_action()
	return res


## §7.0: esegue le Operazioni gratuite in coda che toccano a una Fazione gestita
## dal bot. NON si guarda chi ha giocato l'Evento: un Evento del Red Dust può
## benissimo concedere un Assault gratuito a MarsGov, e prima quella voce restava
## in coda per sempre in attesa di un giocatore che non c'era.
## Quelle che lasciano la scelta dell'Operazione all'Evento restano in coda e si
## dichiarano nel Log: il bot non ha una tabella per deciderle.
func _run_np_free_ops() -> void:
	for guard in range(6):
		var queue: Array = pending_free_ops()
		var idx := -1
		for i in range(queue.size()):
			var entry: Dictionary = queue[i]
			var owner := String(entry.get("faction", ""))
			if owner == "" or not np.is_np(owner):
				continue
			if String(entry.get("operation", "")) == "" and String(entry.get("special", "")) == "":
				continue
			idx = i
			break
		if idx < 0:
			break
		var res: Dictionary = execute_free_op(idx)
		if not res.get("ok", false):
			emit_signal("log_line",
				"Operazione gratuita non eseguibile dal bot: %s" % res.get("error", ""))
			pending_free_ops().remove_at(idx)
	for entry in pending_free_ops():
		var e: Dictionary = entry
		if np.is_np(String(e.get("faction", ""))):
			emit_signal("log_line",
				"[Operazione gratuita di %s lasciata al tavolo: %s]" % [
				e.get("faction", "?"), e.get("note", "l'Evento lascia la scelta")])


## Ciò che il bot sa della carta in corso. Critical/Performed/effective
## dipendono da tabelle non ancora trascritte: restano fuori, e la Eligibility
## lo dichiara con `degraded`.
func _np_context() -> Dictionary:
	var ctx := {}
	if sequence != null and not sequence.is_first_slot():
		ctx["first_chose"] = String(NP_ACTION_TOKEN.get(sequence.first_action(), ""))
	if rounds != null:
		ctx["next_is_dust_storm"] = int(rdr().card_flashpoint.get(rounds.next_card(), -1)) < 0
	# §8.5.5: l'efficacia dell'Evento si calcola dagli effetti già scomposti in
	# event_effects.json. Il «Critical» invece è un simbolo stampato sulle carte
	# (★/⊘ sotto l'icona della Fazione), che non abbiamo ancora estratto.
	var fid := sequence.pending_faction() if sequence != null else ""
	if fid != "" and np != null and np.is_np(fid):
		ctx["current_effective"] = _np_event_option(fid, state.current_card) >= 0
		# §8.5.5: ★ Critico e ⊘ Non eseguito sono stampati sulle carte.
		ctx["current_critical"] = np.event_critical(fid, state.current_card) \
			and not np.event_not_performed(fid, state.current_card)
		if rounds != null:
			ctx["next_critical"] = np.event_critical(fid, rounds.next_card())
			ctx["first_on_next_if_pass"] = _first_on_next_if_pass(fid)
		var second := sequence.next_eligible()
		if second != "":
			ctx["current_critical_for_second"] = np.event_critical(second, state.current_card)
	return ctx


## §8.5.2: passando, questa Fazione sarebbe la 1ª Disponibile sulla prossima
## carta? Chi passa resta Disponibile, chi agisce no; l'ordine è quello stampato
## sulla carta successiva, che è già scoperta. Delle Fazioni che devono ancora
## muoversi su questa carta non si può sapere se agiranno o passeranno: si
## assume che agiscano, che è il caso normale — quindi la risposta è "sì" appena
## nessuna Fazione che ha già passato la precede nell'ordine della prossima carta.
func _first_on_next_if_pass(fid: String) -> bool:
	if rounds == null or sequence == null:
		return false
	var next_card: CardDef = game_def.card(rounds.next_card())
	if next_card == null:
		return false
	for other in next_card.faction_order:
		var o := String(other)
		if o == fid:
			return true
		# Chi ha già agito su questa carta sarà Non Disponibile sulla prossima;
		# chi ha passato resta Disponibile e ci precede.
		var box := String(sequence.action_box.get(o, ""))
		if box == "pass":
			return false
		if box == "":
			return false   # deve ancora muoversi: se passasse, ci precederebbe
	return false


## Quale opzione dell'Evento gioverebbe alla Fazione: 0 non ombreggiata,
## 1 ombreggiata, -1 nessuna. Chi ha il ⊘ non lo esegue affatto.
func _np_event_option(fid: String, card: int) -> int:
	if np.event_not_performed(fid, card):
		return -1
	# La tabella Event Instructions può imporre quale delle due opzioni giocare.
	var forced := np.event_forced_option(fid, card)
	if forced != "":
		return 1 if forced == "shaded" else 0
	for shaded in [false, true]:
		var opt: Dictionary = events.option(card, shaded)
		if opt.is_empty():
			continue
		if bool(np.event_effective(fid, opt.get("effects", []))["effective"]):
			return 1 if shaded else 0
	return -1


## §8.5.2: cosa ha fatto la 1ª Disponibile, nel vocabolario della tabella di
## Eligibility. Si legge dalla sequenza, così vale anche quando la prima a
## muoversi è stata una Fazione di un giocatore.
const NP_ACTION_TOKEN := {
	CoinEnums.ActionType.EVENT: "event",
	CoinEnums.ActionType.OPERATION_WITH_SPECIAL: "op_sa",
	CoinEnums.ActionType.OPERATION: "op_only",
	CoinEnums.ActionType.LIMITED_OPERATION: "lim_op",
}

## Azione della tabella NP → casella della Sequenza di Gioco.
const NP_TOKEN_ACTION := {
	"event": CoinEnums.ActionType.EVENT,
	"asset_event": CoinEnums.ActionType.EVENT,
	"op_sa": CoinEnums.ActionType.OPERATION_WITH_SPECIAL,
	"op_only": CoinEnums.ActionType.OPERATION,
	"lim_op": CoinEnums.ActionType.LIMITED_OPERATION,
}

var _np_rng_instance: RandomNumberGenerator = null


func _np_rng() -> RandomNumberGenerator:
	if _np_rng_instance == null:
		_np_rng_instance = RandomNumberGenerator.new()
		var seed_value := int(state.tracks.get("seed", 0))
		if seed_value != 0:
			_np_rng_instance.seed = seed_value + 977
		else:
			_np_rng_instance.randomize()
	return _np_rng_instance


## §7.0: Operazioni gratuite concesse dagli Eventi e non ancora eseguite.
func pending_free_ops() -> Array:
	if not state.tracks.has("pending_free_ops"):
		state.tracks["pending_free_ops"] = []
	return state.tracks["pending_free_ops"]


## Esegue una delle Operazioni gratuite in sospeso: stesso motore delle
## Operazioni normali, ma senza pagarne il costo (né Risorse né Asset card).
## Al termine applica gli effetti "a seguire" dichiarati dall'Evento.
func execute_free_op(index: int, plan_extra: Dictionary = {}) -> Dictionary:
	var queue: Array = pending_free_ops()
	if index < 0 or index >= queue.size():
		return {"ok": false, "error": "Nessuna Operazione gratuita a quell'indice."}
	var entry: Dictionary = queue[index]
	var fid := String(entry.get("faction", ""))
	var spaces: Array = entry.get("spaces", [])
	var op_id := String(entry.get("operation", ""))
	var sa_id := String(entry.get("special", ""))
	if op_id == "" and sa_id == "":
		return {"ok": false, "error": "L'Evento lascia la scelta dell'Operazione: %s" % entry.get("note", "")}
	snapshot("Operazione gratuita")
	ops.free = true
	var res: Dictionary = _run_operation(op_id, fid, spaces, plan_extra) if op_id != "" \
		else _run_special(sa_id, spaces)
	ops.free = false
	if not res.get("ok", false):
		_undo.pop_back()
		return res
	for line in ops.log_lines:
		emit_signal("log_line", line)
	ops.log_lines.clear()
	for line in specials.log_lines:
		emit_signal("log_line", line)
	specials.log_lines.clear()
	events.apply_after(entry)
	for line in events.log_lines:
		emit_signal("log_line", line)
	events.log_lines.clear()
	queue.remove_at(index)
	emit_signal("log_line", "Operazione gratuita eseguita: %s (%s)." % [
		OPERATION_NAMES.get(op_id, SPECIAL_NAMES.get(sa_id, op_id)), fid])
	refresh()
	return res


# ---------------------------------------------------------------------------
# §4.3 fase 3 — Support Phase dei giocatori
# ---------------------------------------------------------------------------

## Fazioni che devono ancora risolvere Pacify o Agitate. Vuoto = niente in sospeso.
func support_pending() -> Array:
	return rounds.pending_support() if rounds != null else []


## Spazi in cui questa Fazione può agire adesso.
func support_candidates(fid: String, action: String = "") -> PackedStringArray:
	return ops.act.support_candidates(fid, action) if ops != null else PackedStringArray()


func can_lobby() -> bool:
	return ops != null and int(state.tracks.get("lobby_done", 0)) == 0 and ops.act.can_lobby()


## §4.3: fino a due azioni fra House, Repair e lo spostamento del Supporto, in
## uno spazio sotto il proprio Controllo. `actions` è ["house"/"repair"/"shift"].
func support_act(fid: String, sid: String, actions: Array) -> Dictionary:
	if not support_pending().has(fid):
		return {"ok": false, "error": "%s non ha una Support Phase in sospeso." % fid}
	snapshot("Support Phase — %s" % game_def.space(sid).name)
	var done := ops.act.pacify(sid, actions) if fid == "marsgov" else ops.act.agitate(sid, actions)
	for line in ops.act.log_lines:
		emit_signal("log_line", line)
	ops.act.log_lines.clear()
	if done == 0:
		_undo.pop_back()
		return {"ok": false, "error": "Nessuna di quelle azioni è possibile in %s." %
			game_def.space(sid).name}
	emit_signal("log_line", "%s: %d azioni in %s." % [
		game_def.faction(fid).short_name, done, game_def.space(sid).name])
	refresh()
	return {"ok": true, "done": done}


## §4.3 Lobby: 5 Risorse per un livello di EarthGov Confidence, una volta sola.
func support_lobby() -> Dictionary:
	if not can_lobby():
		return {"ok": false, "error": "Lobby non disponibile (5 Risorse, una sola volta)."}
	snapshot("Lobby")
	if not ops.act.lobby():
		_undo.pop_back()
		return {"ok": false, "error": "Lobby rifiutata."}
	state.tracks["lobby_done"] = 1
	for line in ops.act.log_lines:
		emit_signal("log_line", line)
	ops.act.log_lines.clear()
	refresh()
	return {"ok": true}


## La Fazione dichiara di aver finito. Quando non ne resta nessuna, il Dust
## Storm Round riprende da dove si era fermato.
func support_done(fid: String) -> void:
	var left: Array = []
	for f in support_pending():
		if String(f) != fid:
			left.append(String(f))
	state.tracks["support_pending"] = left
	emit_signal("log_line", "%s chiude la propria Support Phase." %
		game_def.faction(fid).short_name)
	if left.is_empty():
		rounds.finish_dust_storm_round()
		_drain_log()
		_start_card()
		_autosave()
	refresh()


## Chiude la carta corrente e passa alla successiva (§4.2 «Next Card»).
func end_card() -> void:
	if sequence == null:
		return
	snapshot("Chiusura della carta #%d" % state.current_card)
	sequence.finish()
	rounds.advance_card()
	_drain_log()
	_start_card()
	_autosave()
	refresh()


## Salvataggio automatico silenzioso: non sporca il Log a ogni carta.
func _autosave() -> void:
	if state == null:
		return
	var f := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"state": state.to_dict(),
		"has_sequence": sequence != null,
		"sequence": sequence.snapshot() if sequence != null else {},
	}, "\t"))
	f.close()


static func has_save(path: String) -> bool:
	return FileAccess.file_exists(path)


func _after_action() -> void:
	if sequence != null and sequence.is_done():
		end_card()
	else:
		_drain_log()
		refresh()


func _drain_log() -> void:
	if rounds == null:
		return
	for line in rounds.log_lines:
		emit_signal("log_line", line)
	rounds.log_lines.clear()


## Comodo per la UI: il modulo RDR espone conteggi non presenti nel motore generico.
func rdr() -> RDRModule:
	return module as RDRModule


func refresh() -> void:
	var m := rdr()
	if m != null:
		m.recompute_all_control(state)
		m.refresh_victory_tracks(state)
	emit_signal("state_changed")


func region(space_id: String) -> Dictionary:
	return regions.get(space_id, off_map.get(space_id, {}))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("GameController: file non trovato %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
