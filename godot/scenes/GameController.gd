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

## §Annulla: istantanee dello stato prima di ogni azione. Bastano lo stato di
## gioco (GameState sa serializzarsi) e la sequenza della carta; i round e i
## mazzi leggono tutto da lì. NB: il generatore casuale non torna indietro,
## quindi rifare un'azione con dadi può dare un risultato diverso.
const UNDO_LIMIT := 25
var _undo: Array = []

## Formato dei salvataggi (user://): stato + sequenza della carta in corso.
const SAVE_VERSION := 1

## Geometrie della tavola (regions.json / board_layout.json), normalizzate [0..1].
var regions: Dictionary = {}
var off_map: Dictionary = {}
var layout: Dictionary = {}


func _ready() -> void:
	new_game()


## `seed_value` diverso da 0 rende la partita riproducibile (mazzi e dadi):
## serve ai test e, in prospettiva, al salvataggio/ripresa.
func new_game(scenario: String = "standard", seed_value: int = 0) -> void:
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
	var moves: Array = extra.get("moves", [])
	match op_id:
		"secure":
			return ops.secure({"faction": fid, "dest": spaces, "moves": moves})
		"recon":
			return ops.recon({"faction": fid, "dest": spaces, "moves": moves})
		"march":
			return ops.march({"dest": spaces, "moves": moves})
		"travel":
			return ops.travel({"origins": spaces, "moves": moves})
		"logistics":
			var plan := {"deserts": spaces, "earth": extra.get("earth", {}),
				"transit": bool(extra.get("transit", false))}
			return ops.logistics(plan)
		"train":
			var entries: Array = []
			for sid in spaces:
				entries.append({"id": sid, "troops": 4})
			return ops.train({"spaces": entries})
		"assault":
			return ops.assault({"faction": fid, "spaces": spaces})
		"rally":
			var entries: Array = []
			for sid in spaces:
				entries.append({"id": sid, "mode": "place"})
			return ops.rally({"faction": fid, "spaces": entries})
		"attack":
			return ops.attack({"faction": fid, "spaces": spaces})
		"campaign":
			return ops.campaign({"spaces": spaces})
		"preach":
			return ops.preach({"spaces": spaces})
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
func legal_origins(op_id: String, fid: String, dest: String, type_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var control := "coin" if op_id in ["secure", "recon"] else \
		("red_dust" if op_id == "march" else "reclaimer")
	for s in state.game_def.spaces:
		if s.id == dest or rdr().count_in(state, s.id, type_id) == 0:
			continue
		if op_id == "travel":
			# §5.8: le forze Reclaimer si spostano di uno spazio adiacente.
			if state.game_def.space(dest).adjacent.has(s.id):
				out.append(s.id)
			continue
		var reach := ops.reachable_labyrinths(s.id, control)
		if op_id in ["recon", "march"]:
			for x in ops.reachable_deserts(s.id, control):
				reach.append(x)
		if reach.has(dest):
			out.append(s.id)
	return out


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
	var entries: Array = []
	match sa_id:
		"entrench":
			for sid in spaces:
				entries.append({"id": sid, "fortify": 9})
			return specials.entrench({"spaces": entries})
		"petition":
			return specials.petition({})
		"public_relations":
			for sid in spaces:
				entries.append({"id": sid, "repairs": 1, "house": true})
			return specials.public_relations({"spaces": entries})
		"exploit":
			return specials.exploit({"spaces": spaces})
		"raid":
			for sid in spaces:
				entries.append({"id": sid, "targets": ["rd_rebel", "cr_rebel"]})
			return specials.raid({"spaces": entries})
		"redistribute":
			return specials.redistribute({"spaces": spaces})
		"coordinate":
			for sid in spaces:
				entries.append({"id": sid, "action": "", "at_max": "remove"})
			return specials.coordinate({"spaces": entries})
		"purify":
			for sid in spaces:
				entries.append({"id": sid, "mode": "convert"})
			return specials.purify({"spaces": entries})
		"ransack":
			return specials.ransack({"spaces": spaces})
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
	refresh()


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
