extends GameManifest

## Manifest del gioco "Red Dust Rebellion" (Serie COIN Vol. XII, GMT 2024).
## I sottosistemi (Operazioni, Attività Speciali, Eventi, Round Flashpoint/Dust
## Storm, Non-Player "Curiosity") verranno agganciati qui man mano.

func game_id() -> String:
	return "red_dust_rebellion"


func game_title() -> String:
	return "Red Dust Rebellion"


func create_module() -> RulesModule:
	return RDRModule.new()


func default_roles(_game_def: GameDef) -> Dictionary:
	# Solitario tipico: l'umano gioca il Governo Marziano contro 3 Non-Player
	# Curiosity. EarthGov non è mai un ruolo: è guidata dall'EarthGov Controller.
	return {
		"marsgov": "player",
		"corporations": "bot",
		"red_dust": "bot",
		"reclaimer": "bot",
		"earthgov": "bot",
	}
