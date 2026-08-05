class_name RDREvents
extends RefCounted

## Esecuzione degli Eventi (§7.0).
##
## Gli Eventi di Red Dust Rebellion sono quasi tutti pieni di scelte ("rimuovi
## fino a 6 Ribelli da spazi a scelta", "una Fazione può eseguire un'Operazione
## gratuita"): tradurli in codice significherebbe scrivere 93 effetti a mano.
## Qui la scelta è diversa e dichiarata: `data/event_effects.json` contiene solo
## gli effetti riconosciuti con certezza dal testo, e ogni opzione che non sia
## interamente riconosciuta è marcata `manual`.
##
## Giocare un Evento quindi: applica gli effetti automatici (fra cui il simbolo
## EG+/EG−, che è sempre automatico) e restituisce il testo residuo perché i
## giocatori lo risolvano al tavolo — come fa il modulo Vassal, che di proposito
## automatizza pochissimo.

var state: GameState
var module: RDRModule
var act: RDRActions
var effects: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule) -> void:
	state = p_state
	module = p_module
	act = RDRActions.new(p_state, p_module)
	var path := RDRModule.DATA_DIR + "event_effects.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			effects = parsed.get("events", {})


## Descrizione di un'opzione: {text, manual, effects}.
func option(number: int, shaded: bool) -> Dictionary:
	var e: Dictionary = effects.get(str(number), {})
	return e.get("shaded" if shaded else "unshaded", {})


func is_manual(number: int, shaded: bool) -> bool:
	return bool(option(number, shaded).get("manual", false))


## Spazi che il giocatore deve indicare per l'opzione (0 se non servono).
func targets_needed(number: int, shaded: bool) -> int:
	var n := 0
	for e in option(number, shaded).get("effects", []):
		if String(e.get("op", "")) == "shift_spaces":
			n += int(e.get("count", 0))
	return n


## Esegue l'opzione. `targets` sono gli spazi scelti per le clausole che li
## richiedono. Restituisce {ok, manual, residual, applied}.
func play(number: int, shaded: bool, targets: Array = []) -> Dictionary:
	var opt := option(number, shaded)
	if opt.is_empty():
		return {"ok": false, "manual": false, "residual": "", "applied": 0,
			"error": "Evento #%d senza testo per questa opzione." % number}
	var applied := 0
	var target_idx := 0
	for e in opt.get("effects", []):
		match String(e.get("op", "")):
			"eg_side":
				act.set_eg(String(e.get("side", "EG+")))
				applied += 1
			"profits":
				state.tracks["profits"] = clampi(
					int(state.tracks.get("profits", 0)) + int(e["delta"]), 0, 50)
				applied += 1
			"resources":
				state.add_resources(String(e["faction"]), int(e["delta"]), 50)
				applied += 1
			"supply_earth":
				module.add_marker(state, "earth", "supply", int(e["delta"]))
				applied += 1
			"population_earth":
				module.add_marker(state, "earth", "population", int(e["delta"]))
				applied += 1
			"shift_space":
				for i in range(int(e.get("levels", 1))):
					act.shift(String(e["space"]), int(e.get("direction", 1)))
				applied += 1
			"set_neutral":
				state.spaces[String(e["space"])].support = CoinEnums.Support.NEUTRAL
				applied += 1
			"clear_supply":
				module.set_marker(state, String(e["space"]), "supply", 0)
				applied += 1
			"activate_all":
				var who := String(e.get("faction", "both"))
				for sid in module.mars_spaces(state):
					if who in ["red_dust", "both"]:
						act.activate(sid, "rd_rebel", 99)
					if who in ["reclaimer", "both"]:
						act.activate(sid, "cr_rebel", 99)
				applied += 1
			"shift_spaces":
				# Richiede gli spazi indicati dal giocatore.
				for i in range(int(e.get("count", 0))):
					if target_idx >= targets.size():
						break
					act.shift(String(targets[target_idx]), int(e.get("direction", 1)))
					target_idx += 1
				applied += 1
	log_lines.append_array(act.log_lines)
	act.log_lines.clear()
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)

	var residual := String(opt.get("residual", ""))
	if residual != "":
		log_lines.append("Da risolvere al tavolo: %s" % residual)
	return {
		"ok": true,
		"manual": bool(opt.get("manual", false)),
		"residual": residual,
		"applied": applied,
		"error": "",
	}


## Quante opzioni sono automatiche e quante restano manuali (per la UI e i test).
func coverage() -> Dictionary:
	var auto := 0
	var manual := 0
	for number in effects.keys():
		for opt in effects[number].keys():
			if bool(effects[number][opt].get("manual", false)):
				manual += 1
			else:
				auto += 1
	return {"automatic": auto, "manual": manual, "total": auto + manual}
