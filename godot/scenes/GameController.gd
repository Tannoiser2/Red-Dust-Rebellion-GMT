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
	if not sequence.act_pass():
		return false
	emit_signal("log_line", "%s Passa." % game_def.faction(fid).short_name)
	# Il Passo delle Corporations attiva l'Aldrin Cycler; quello dei Reclaimer
	# darebbe una pescata di Asset (mazzo non ancora implementato).
	for i in range(before, sequence.pass_effects.size()):
		match sequence.pass_effects[i]:
			"aldrin_cycler":
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
	"marsgov": ["train", "assault"],
	"corporations": ["assault"],
	"red_dust": ["rally", "attack", "campaign"],
	"reclaimer": ["rally", "attack", "preach"],
}

const OPERATION_NAMES := {
	"train": "Train", "logistics": "Logistics", "secure": "Secure", "recon": "Recon",
	"assault": "Assault", "rally": "Rally", "march": "March", "travel": "Travel",
	"attack": "Attack", "campaign": "Campaign", "preach": "Preach",
}


## Esegue un'Operazione per la Fazione di turno e registra l'azione nella
## sequenza. Restituisce il risultato dell'Operazione ({ok, error, spent}).
func execute_operation(op_id: String, spaces: Array, with_special: bool = false) -> Dictionary:
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

	var res: Dictionary = _run_operation(op_id, fid, spaces)
	if not res.get("ok", false):
		return res
	for line in ops.log_lines:
		emit_signal("log_line", line)
	ops.log_lines.clear()
	emit_signal("log_line", "%s esegue %s in %d spazi." % [
		game_def.faction(fid).short_name, OPERATION_NAMES.get(op_id, op_id), spaces.size()])
	sequence.act(action)
	_after_action()
	return res


func _run_operation(op_id: String, fid: String, spaces: Array) -> Dictionary:
	match op_id:
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
		"campaign", "preach":
			var rebel2 := "rd_rebel" if op_id == "campaign" else "cr_rebel"
			var out3 := PackedStringArray()
			for sid in m.mars_spaces(state):
				if ops.act.selectable(sid) and m.population(state, sid) > 0 \
						and m.count_in(state, sid, rebel2) > 0:
					out3.append(sid)
			return out3
	return PackedStringArray()


## Chiude la carta corrente e passa alla successiva (§4.2 «Next Card»).
func end_card() -> void:
	if sequence == null:
		return
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
