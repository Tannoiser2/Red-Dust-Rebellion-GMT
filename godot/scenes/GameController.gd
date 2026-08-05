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
	"marsgov": {"entrench": 2, "petition": 0, "transport": 0},
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
			return o.assault({"faction": fid, "spaces": spaces})
		"rally":
			var entries: Array = []
			for sid in spaces:
				entries.append({"id": sid, "mode": "place"})
			return o.rally({"faction": fid, "spaces": entries})
		"attack":
			return o.attack({"faction": fid, "spaces": spaces})
		"campaign":
			return o.campaign({"spaces": spaces})
		"preach":
			return o.preach({"spaces": spaces})
	return {"ok": false, "error": "Operazione '%s' non ancora disponibile in UI." % op_id}


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
func execute_special(sa_id: String, spaces: Array) -> Dictionary:
	if sequence == null or sequence.pending_faction() == "":
		return {"ok": false, "error": "Non è il turno di nessuno."}
	snapshot(SPECIAL_NAMES.get(sa_id, sa_id))
	var res: Dictionary = _run_special(sa_id, spaces)
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


func _run_special(sa_id: String, spaces: Array) -> Dictionary:
	return _run_special_on(specials, sa_id, spaces)


## Come sopra: l'anteprima esegue su una copia, non sulla partita.
func _run_special_on(sp: RDRSpecials, sa_id: String, spaces: Array) -> Dictionary:
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
func play_asset_card(number: int, choices = {}) -> Dictionary:
	if cards == null:
		return {"ok": false, "error": "Mazzi non collegati."}
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
		_undo.pop_back()
		return res

	# Si registra l'azione nella sequenza, come farebbe un giocatore.
	match String(res.get("action", "")):
		"pass":
			sequence.act_pass()
		"lim_op":
			sequence.act(CoinEnums.ActionType.LIMITED_OPERATION)
		"op_only":
			sequence.act(CoinEnums.ActionType.OPERATION)
		"event", "asset_event":
			sequence.act(CoinEnums.ActionType.EVENT)
		_:
			sequence.act(CoinEnums.ActionType.OPERATION_WITH_SPECIAL)
	emit_signal("log_line", "%s (bot): %s." % [
		game_def.faction(fid).short_name, res.get("operation", res.get("action", ""))])
	_after_action()
	return res


## Ciò che il bot sa della carta in corso. Critical/Performed/effective
## dipendono da tabelle non ancora trascritte: restano fuori, e la Eligibility
## lo dichiara con `degraded`.
func _np_context() -> Dictionary:
	var ctx := {}
	if sequence != null and not sequence.is_first_slot():
		ctx["first_chose"] = _np_first_choice
	if rounds != null:
		ctx["next_is_dust_storm"] = int(rdr().card_flashpoint.get(rounds.next_card(), -1)) < 0
	# §8.5.5: l'efficacia dell'Evento si calcola dagli effetti già scomposti in
	# event_effects.json. Il «Critical» invece è un simbolo stampato sulle carte
	# (★/⊘ sotto l'icona della Fazione), che non abbiamo ancora estratto.
	var fid := sequence.pending_faction() if sequence != null else ""
	if fid != "" and np != null and np.is_np(fid):
		var opt: Dictionary = events.option(state.current_card, false)
		var shaded: Dictionary = events.option(state.current_card, true)
		var eff: Dictionary = np.event_effective(fid, opt.get("effects", []))
		var eff2: Dictionary = np.event_effective(fid, shaded.get("effects", []))
		ctx["current_effective"] = bool(eff["effective"]) or bool(eff2["effective"])
	return ctx


var _np_first_choice := ""
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
