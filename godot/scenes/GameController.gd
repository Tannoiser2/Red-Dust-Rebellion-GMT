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

## Geometrie della tavola (regions.json / board_layout.json), normalizzate [0..1].
var regions: Dictionary = {}
var off_map: Dictionary = {}
var layout: Dictionary = {}


func _ready() -> void:
	new_game()


func new_game(scenario: String = "standard") -> void:
	module = GameRegistry.create_module()
	game_def = module.build_game_def()
	state = GameState.new(game_def)
	state.roles = GameRegistry.default_roles(game_def)
	module.apply_setup(state, scenario)

	var reg: Dictionary = _load_json(GameRegistry.data_path("regions.json"))
	regions = reg.get("regions", {})
	off_map = reg.get("off_map", {})
	layout = _load_json(GameRegistry.data_path("board_layout.json"))

	rounds = RDRRounds.new(state, rdr())
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
				emit_signal("log_line", "I Reclaimer pescherebbero 1 Asset card (mazzo non implementato).")
	_after_action()
	return true


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
