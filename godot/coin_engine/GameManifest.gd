class_name GameManifest
extends RefCounted

## Contratto che ogni modulo di gioco (cuba_libre, all_bridges_burning, …) deve
## implementare. Il GameRegistry istanzia il manifest del game_id attivo e lo usa
## come factory: il GameController e la UI restano agnostici dal gioco specifico.

## Identificatore del gioco (snake_case), deve coincidere con la cartella in res://games/.
func game_id() -> String:
	push_error("GameManifest.game_id() non implementato")
	return ""

## Titolo umano del gioco (mostrato nella UI).
func game_title() -> String:
	return game_id()

## Crea il RulesModule del gioco.
func create_module() -> RulesModule:
	push_error("GameManifest.create_module() non implementato")
	return null

## Crea il sistema Operazioni (può restituire Variant se non c'è ancora una base class).
func create_operations(_state, _module):
	return null

func create_specials(_state, _module):
	return null

func create_propaganda(_state, _module):
	return null

func create_events(_state, _module):
	return null

## Crea il sistema Non-giocatore (Bot) del gioco.
func create_bot(_state, _module):
	return null

## Ruoli default (player/bot) per fazione. Override per scenari iniziali differenti.
## Default: la prima fazione di game_def è il giocatore umano, le altre sono bot.
func default_roles(game_def: GameDef) -> Dictionary:
	var roles := {}
	var factions = game_def.factions if game_def != null else []
	for i in range(factions.size()):
		var fid: String = factions[i].id
		roles[fid] = "player" if i == 0 else "bot"
	return roles
