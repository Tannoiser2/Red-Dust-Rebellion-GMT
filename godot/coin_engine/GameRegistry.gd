extends Node

## Singleton (autoload) che incapsula il gioco attivo (game_id) e funge da factory
## per il modulo regole, i sottosistemi (operazioni, eventi, bot…) e fornisce i
## path di dati e asset gioco-specifici.
##
## Il game_id può essere passato da CLI (--game=all_bridges_burning), da
## ProjectSettings ("application/config/game_id") oppure usa il default qui sotto.

const DEFAULT_GAME_ID := "cuba_libre"

var game_id: String = DEFAULT_GAME_ID
var manifest: GameManifest


func _ready() -> void:
	_ensure()


## Carica il manifest se non è ancora stato caricato. Serve perché l'ordine di
## `_ready()` fra autoload non è garantito: un altro autoload (GameController)
## può chiedere il modulo prima che questo abbia eseguito il proprio `_ready()`.
func _ensure() -> void:
	if manifest != null:
		return
	game_id = _resolve_game_id()
	manifest = _load_manifest(game_id)


func _resolve_game_id() -> String:
	# 1) CLI: --game=<id>
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--game="):
			return arg.substr("--game=".length()).strip_edges()
	# 2) ProjectSettings
	var ps := str(ProjectSettings.get_setting("application/config/game_id", ""))
	if ps != "":
		return ps
	# 3) default
	return DEFAULT_GAME_ID


func _load_manifest(gid: String) -> GameManifest:
	var path := "res://games/%s/Manifest.gd" % gid
	if not ResourceLoader.exists(path):
		push_error("GameRegistry: manifest non trovato per game_id='%s' (%s)" % [gid, path])
		return null
	var script: Script = load(path)
	return script.new()


# ---------------------------------------------------------------------------
# Path helpers (gioco-specifici)
# ---------------------------------------------------------------------------

func game_root() -> String:
	_ensure()
	return "res://games/%s/" % game_id

func data_dir() -> String:
	return game_root() + "data/"

func data_path(file_name: String) -> String:
	return data_dir() + file_name

func assets_dir() -> String:
	return game_root() + "assets/"

func asset_path(file_name: String) -> String:
	return assets_dir() + file_name


# ---------------------------------------------------------------------------
# Factory (delegano al manifest)
# ---------------------------------------------------------------------------

func create_module() -> RulesModule:
	_ensure()
	return manifest.create_module() if manifest else null

func create_operations(state, module):
	return manifest.create_operations(state, module) if manifest else null

func create_specials(state, module):
	return manifest.create_specials(state, module) if manifest else null

func create_propaganda(state, module):
	return manifest.create_propaganda(state, module) if manifest else null

func create_events(state, module):
	return manifest.create_events(state, module) if manifest else null

func create_bot(state, module):
	return manifest.create_bot(state, module) if manifest else null

func default_roles(game_def: GameDef) -> Dictionary:
	_ensure()
	return manifest.default_roles(game_def) if manifest else {}
