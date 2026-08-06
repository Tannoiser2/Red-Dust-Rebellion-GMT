class_name RDREvents
extends RefCounted

## Esecuzione degli Eventi (§7.0).
##
## Gli Eventi di Red Dust Rebellion sono quasi tutti pieni di scelte ("rimuovi
## fino a 6 Ribelli da spazi a scelta", "una Fazione può eseguire un'Operazione
## gratuita"). `data/event_effects.json` non è più il risultato di un'estrazione
## automatica dai testi: è una **libreria scritta a mano**, dove ogni opzione
## dichiara
##
##  * `choices` — le decisioni che spettano ai giocatori (quali spazi, quale
##    Fazione, quale ramo di un "either/or"); e
##  * `effects` — la sequenza di effetti atomici da applicare una volta note le
##    scelte.
##
## Chi chiama passa le scelte a `play()`. Quelle che mancano vengono riempite
## automaticamente scorrendo i candidati legali, così che i test headless (e la
## UI finché non offre tutti i selettori) possano comunque risolvere l'Evento
## per intero; `play()` restituisce in `choices` ciò che ha effettivamente usato.
##
## Le Operazioni gratuite concesse dagli Eventi non vengono eseguite qui: sono
## registrate in `state.tracks["pending_free_ops"]` e le esegue il chiamante con
## il normale motore delle Operazioni (§5.0), a costo zero.

## Gruppi di tipi di pezzo usati dai filtri e dalle rimozioni.
const TYPE_GROUPS := {
	"rebels": ["rd_rebel", "cr_rebel"],
	"rebel_bases": ["rd_base", "cr_base"],
	"rebel_forces": ["rd_rebel", "cr_rebel", "rd_base", "cr_base"],
	"cubes": ["mg_troop", "security", "eg_troop"],
	"troops": ["mg_troop", "eg_troop"],
	"coin_units": ["mg_troop", "security", "specops", "eg_troop", "satellite"],
	"coin_forces": ["mg_troop", "security", "specops", "eg_troop", "satellite",
		"mg_base", "corp_base"],
	"coin_bases": ["mg_base", "corp_base"],
	"corp_forces": ["security", "specops", "corp_base"],
	"corp_units": ["security", "specops"],
	"mg_forces": ["mg_troop", "mg_base"],
	"bases": ["mg_base", "corp_base", "rd_base", "cr_base"],
}

## §1.10: non si possono mettere in gioco più di 6 marcatori Tempesta.
const MAX_STORMS := 6

var state: GameState
var module: RDRModule
var act: RDRActions
## Serve alle clausole "perform an Aldrin Cycler phase" (§4.2).
var rounds: RDRRounds = null
## Serve alle clausole su Asset card e Campaign card (§1.5).
var cards: RDRCards = null
## Fazione che sta giocando l'Evento: risolve "@rebel", "executing" e simili.
var executing_faction: String = ""

var effects: Dictionary = {}
## §1.5: gli Eventi delle 10 Asset card dei Reclaimer, scritti con la stessa
## grammatica delle carte Evento e risolti dalla stessa macchina.
var asset_effects: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule) -> void:
	state = p_state
	module = p_module
	act = RDRActions.new(p_state, p_module)
	effects = _load_library("event_effects.json", "events")
	asset_effects = _load_library("asset_effects.json", "cards")


func _load_library(file_name: String, key: String) -> Dictionary:
	var path := RDRModule.DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get(key, {}) if typeof(parsed) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------------------
# Interrogazione
# ---------------------------------------------------------------------------

## Descrizione di un'opzione: {text, choices, effects, manual, residual}.
func option(number: int, shaded: bool) -> Dictionary:
	var e: Dictionary = effects.get(str(number), {})
	return e.get("shaded" if shaded else "unshaded", {})


func is_manual(number: int, shaded: bool) -> bool:
	return bool(option(number, shaded).get("manual", false))


## Scelte che l'opzione richiede, ciascuna con i candidati legali nello stato
## attuale. `known` permette di risolvere le scelte che dipendono dalle
## precedenti (per esempio "in uno spazio adiacente a quello scelto prima").
func requirements(number: int, shaded: bool, known: Dictionary = {}) -> Array:
	return _requirements_of(option(number, shaded), known)


func _requirements_of(opt: Dictionary, known: Dictionary) -> Array:
	var ctx := _new_ctx(known)
	var out: Array = []
	for c in opt.get("choices", []):
		var desc: Dictionary = (c as Dictionary).duplicate(true)
		var cid := String(desc.get("id", ""))
		match String(desc.get("kind", "space")):
			"space":
				desc["candidates"] = _matching(desc.get("filter", {}), ctx)
			"faction":
				desc["candidates"] = desc.get("options", [])
			"branch":
				desc["candidates"] = desc.get("options", [])
		out.append(desc)
		# Le scelte successive vedono quelle già risolte (fornite o automatiche).
		ctx["choices"][cid] = known[cid] if known.has(cid) else _auto_choice(desc, ctx)
	return out


## Spazi che il giocatore DEVE indicare (le clausole "up to" hanno minimo 0).
func targets_needed(number: int, shaded: bool) -> int:
	var n := 0
	for c in option(number, shaded).get("choices", []):
		if String((c as Dictionary).get("kind", "space")) == "space":
			n += int((c as Dictionary).get("min", 0))
	return n


## Massimo di spazi selezionabili in tutto (per la barra della UI).
func targets_allowed(number: int, shaded: bool) -> int:
	var n := 0
	for c in option(number, shaded).get("choices", []):
		if String((c as Dictionary).get("kind", "space")) == "space":
			n += int((c as Dictionary).get("count", 0))
	return n


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


# ---------------------------------------------------------------------------
# Esecuzione
# ---------------------------------------------------------------------------

## Esegue l'opzione. `choices` è {id_scelta: valore}; per compatibilità accetta
## anche un Array, interpretato come gli spazi della prima scelta.
## Restituisce {ok, manual, residual, applied, choices, free_ops, error}.
func play(number: int, shaded: bool, choices = {}, faction: String = "") -> Dictionary:
	var opt := option(number, shaded)
	if opt.is_empty():
		return {"ok": false, "manual": false, "residual": "", "applied": 0,
			"choices": {}, "free_ops": [],
			"error": "Evento #%d senza testo per questa opzione." % number}
	return _play_option(opt, choices, faction)


## §1.5: Evento di una Asset card dei Reclaimer. Stessa grammatica e stessa
## macchina delle carte Evento, solo una libreria diversa.
func asset_option(number: int) -> Dictionary:
	return asset_effects.get(str(number), {})


func asset_requirements(number: int, known: Dictionary = {}) -> Array:
	return _requirements_of(asset_option(number), known)


func play_asset(number: int, choices = {}, faction: String = "reclaimer") -> Dictionary:
	var opt := asset_option(number)
	if opt.is_empty():
		return {"ok": false, "manual": false, "residual": "", "applied": 0,
			"choices": {}, "free_ops": [],
			"error": "Asset card #%d senza Evento." % number}
	return _play_option(opt, choices, faction)


func _play_option(opt: Dictionary, choices, faction: String) -> Dictionary:
	if faction != "":
		executing_faction = faction

	var known := _normalize_choices(opt, choices)
	var ctx := _new_ctx(known)
	# Le scelte non fornite si risolvono da sole sui candidati legali.
	for c in opt.get("choices", []):
		var desc: Dictionary = c
		var cid := String(desc.get("id", ""))
		if not ctx["choices"].has(cid) or _empty_choice(ctx["choices"][cid]):
			ctx["choices"][cid] = _auto_choice(desc, ctx)

	var free_before: int = _free_ops().size()
	var applied := 0
	for e in opt.get("effects", []):
		applied += _apply(e, ctx)
		# Le righe di RDRActions (House, Repair, Danno) vanno nel Log in ordine.
		log_lines.append_array(act.log_lines)
		act.log_lines.clear()

	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)

	var free_ops: Array = []
	for i in range(free_before, _free_ops().size()):
		free_ops.append(_free_ops()[i])

	var residual := String(opt.get("residual", ""))
	if residual != "":
		log_lines.append("Da risolvere al tavolo: %s" % residual)
	return {
		"ok": true,
		"manual": bool(opt.get("manual", false)),
		"residual": residual,
		"applied": applied,
		"choices": ctx["choices"],
		"free_ops": free_ops,
		"error": "",
	}


func _new_ctx(known: Dictionary) -> Dictionary:
	return {"choices": known.duplicate(true), "last": 0, "vars": {}}


## Effetti "a seguire" di un'Operazione gratuita (§7.0): li applica il chiamante
## dopo aver eseguito l'Operazione registrata in `pending_free_ops`.
func apply_after(entry: Dictionary) -> int:
	var ctx := {
		"choices": (entry.get("choices", {}) as Dictionary).duplicate(true),
		"vars": (entry.get("vars", {}) as Dictionary).duplicate(true),
		"last": 0,
	}
	var applied := 0
	for e in entry.get("after", []):
		applied += _apply(e, ctx)
	log_lines.append_array(act.log_lines)
	act.log_lines.clear()
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)
	return applied


## Accetta l'Array storico (`play(10, false, ["a", "b"])`) mappandolo sulla
## prima scelta di spazi dichiarata dall'opzione.
func _normalize_choices(opt: Dictionary, choices) -> Dictionary:
	if typeof(choices) == TYPE_DICTIONARY:
		return (choices as Dictionary).duplicate(true)
	var out := {}
	if typeof(choices) == TYPE_ARRAY and not (choices as Array).is_empty():
		for c in opt.get("choices", []):
			if String((c as Dictionary).get("kind", "space")) == "space":
				out[String((c as Dictionary).get("id", ""))] = Array(choices)
				break
	return out


func _empty_choice(value) -> bool:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).is_empty()
	return typeof(value) == TYPE_STRING and String(value) == ""


## Scelta automatica: i primi candidati legali, in ordine di mappa.
func _auto_choice(desc: Dictionary, ctx: Dictionary) -> Variant:
	match String(desc.get("kind", "space")):
		"faction":
			var options: Array = desc.get("options", [])
			if options.has(executing_faction):
				return executing_faction
			var pref := String(desc.get("default", ""))
			if pref != "" and options.has(pref):
				return pref
			return String(options[0]) if not options.is_empty() else ""
		"branch":
			var branches: Array = desc.get("options", [])
			var pref2 := String(desc.get("default", ""))
			if pref2 != "" and branches.has(pref2):
				return pref2
			return String(branches[0]) if not branches.is_empty() else ""
		_:
			var pool: Array = _matching(desc.get("filter", {}), ctx)
			var want := int(desc.get("count", 0))
			var out: Array = []
			for sid in pool:
				if out.size() >= want:
					break
				out.append(sid)
			# `repeat` (più pezzi nello stesso spazio): si riempie il primo spazio.
			if bool(desc.get("repeat", false)) and not pool.is_empty():
				while out.size() < want:
					out.append(String(pool[0]))
			return out


# ---------------------------------------------------------------------------
# Selezione degli spazi
# ---------------------------------------------------------------------------

## Sorgente di spazi di un effetto: {choice} · {list} · {space} · {filter}.
func _spaces(where, ctx: Dictionary) -> Array:
	if typeof(where) == TYPE_STRING:
		return [String(where)]
	if typeof(where) != TYPE_DICTIONARY:
		return []
	var w: Dictionary = where
	var out: Array = []
	if w.has("space"):
		out = [String(w["space"])]
	elif w.has("list"):
		for sid in w["list"]:
			out.append(String(sid))
	elif w.has("choice"):
		var v = ctx["choices"].get(String(w["choice"]), [])
		if typeof(v) == TYPE_ARRAY:
			for sid in v:
				out.append(String(sid))
		elif typeof(v) == TYPE_STRING and String(v) != "":
			out = [String(v)]
	elif w.has("filter"):
		out = _matching(w["filter"], ctx)
	if bool(w.get("unique", false)):
		var seen: Array = []
		for sid in out:
			if not seen.has(sid):
				seen.append(sid)
		out = seen
	if bool(w.get("adjacent", false)):
		out = _adjacent_of(out)
	if w.has("limit"):
		out = out.slice(0, _count(w["limit"], ctx))
	return out


func _adjacent_of(spaces: Array) -> Array:
	var out: Array = []
	for sid in spaces:
		var sd: SpaceDef = state.game_def.space(String(sid))
		if sd == null:
			continue
		for a in sd.adjacent:
			if not out.has(String(a)) and not spaces.has(String(a)):
				out.append(String(a))
	return out


## Tutti gli spazi che soddisfano il filtro, nell'ordine della mappa.
func _matching(filter: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for sid in _scope(filter):
		if _matches(String(sid), filter, ctx):
			out.append(String(sid))
	return out


func _scope(filter: Dictionary) -> Array:
	match String(filter.get("scope", "mars")):
		"all":
			var every: Array = []
			for s in state.game_def.spaces:
				every.append(s.id)
			return every
		"mars_and_phobos":
			var wp: Array = Array(module.mars_spaces(state))
			wp.append("phobos")
			return wp
		_:
			return Array(module.mars_spaces(state))


func _matches(sid: String, filter: Dictionary, ctx: Dictionary) -> bool:
	if filter.is_empty():
		return true
	if filter.has("in") and not (filter["in"] as Array).has(sid):
		return false
	if filter.has("not_in") and (filter["not_in"] as Array).has(sid):
		return false
	if filter.has("terrain"):
		var want := String(filter["terrain"])
		var is_lab := module.is_labyrinth(state, sid)
		if want == "labyrinth" and not is_lab:
			return false
		if want == "desert" and not module.is_desert(state, sid):
			return false
	if filter.has("populated") and (module.population(state, sid) > 0) != bool(filter["populated"]):
		return false
	if filter.has("support") and not _support_matches(sid, String(filter["support"])):
		return false
	if filter.has("control") and not _control_matches(sid, String(filter["control"])):
		return false
	if filter.has("has_any") and _count_types(sid, filter["has_any"]) <= 0:
		return false
	if filter.has("has_none") and _count_types(sid, filter["has_none"]) > 0:
		return false
	for cond in filter.get("has", []):
		var c: Dictionary = cond
		var n := _count_types(sid, c.get("types", [c.get("type", "")]),
			String(c.get("state", "")))
		if n < int(c.get("min", 1)) or n > int(c.get("max", 9999)):
			return false
	if filter.has("damage"):
		var d := module.marker(state, sid, "damage")
		var dr: Dictionary = filter["damage"]
		if d < int(dr.get("min", 0)) or d > int(dr.get("max", 9999)):
			return false
	if filter.has("marker"):
		var mk: Dictionary = filter["marker"]
		var mv := module.marker(state, sid, String(mk.get("name", "")))
		if mv < int(mk.get("min", 0)) or mv > int(mk.get("max", 9999)):
			return false
	if filter.has("storm"):
		var sr: Dictionary = filter["storm"]
		var sv := module.storm(state, sid)
		if sv < int(sr.get("min", 0)) or sv > int(sr.get("max", 9999)):
			return false
	if filter.has("adjacent_to"):
		var anchors := _spaces(filter["adjacent_to"], ctx)
		if anchors.is_empty():
			return false
		var sd: SpaceDef = state.game_def.space(sid)
		# `include_anchor`: "in or adjacent to" — vale anche lo spazio stesso.
		var touching: bool = bool(filter.get("include_anchor", false)) and anchors.has(sid)
		for a in anchors:
			if touching:
				break
			if sd != null and Array(sd.adjacent).has(String(a)):
				touching = true
		if not touching:
			return false
	if bool(filter.get("maglev_adjacent", false)) and not _near_maglev(sid):
		return false
	if bool(filter.get("base_room", false)) and not act.can_place_base(sid):
		return false
	if bool(filter.get("selectable", false)) and not act.selectable(sid):
		return false
	return true


func _support_matches(sid: String, want: String) -> bool:
	var lvl: int = state.spaces[sid].support
	match want:
		"active_support": return lvl == CoinEnums.Support.ACTIVE_SUPPORT
		"passive_support": return lvl == CoinEnums.Support.PASSIVE_SUPPORT
		"neutral": return lvl == CoinEnums.Support.NEUTRAL
		"passive_opposition": return lvl == CoinEnums.Support.PASSIVE_OPPOSITION
		"active_opposition": return lvl == CoinEnums.Support.ACTIVE_OPPOSITION
		"any_support": return lvl > 0
		"any_opposition": return lvl < 0
		"no_support": return lvl <= 0
		"not_active_support": return lvl != CoinEnums.Support.ACTIVE_SUPPORT
	return true


func _control_matches(sid: String, want: String) -> bool:
	var ctrl: String = state.spaces[sid].control
	match want:
		"none": return ctrl == ""
		"any": return ctrl != ""
		"rebel": return ctrl == "red_dust" or ctrl == "reclaimer"
	return ctrl == want


## §1.2: uno spazio "adiacente a una linea Maglev" è un Labirinto collegato, o un
## Deserto confinante con due Labirinti collegati fra loro.
func _near_maglev(sid: String) -> bool:
	if module.maglev_links(state, sid).size() > 0:
		return true
	var sd: SpaceDef = state.game_def.space(sid)
	if sd == null:
		return false
	for a in sd.adjacent:
		for b in sd.adjacent:
			if String(a) == String(b):
				continue
			if Array(module.maglev_links(state, String(a))).has(String(b)):
				return true
	return false


# ---------------------------------------------------------------------------
# Tipi di pezzo e conteggi
# ---------------------------------------------------------------------------

## Espande i gruppi ("rebels") e i segnaposto dinamici ("@rebel", "@base").
func _expand_types(types, ctx: Dictionary = {}) -> Array:
	var raw: Array = []
	if typeof(types) == TYPE_STRING:
		raw = [String(types)]
	elif typeof(types) == TYPE_ARRAY:
		raw = types
	var out: Array = []
	for t in raw:
		var key := String(t)
		if key == "@own":
			# Le unità della Fazione a cui l'effetto si riferisce.
			for own in _own_types(String(ctx.get("faction", executing_faction))):
				if not out.has(String(own)):
					out.append(String(own))
			continue
		if key.begins_with("@"):
			key = _dynamic_type(key, ctx)
			if key == "":
				continue
		if TYPE_GROUPS.has(key):
			for sub in TYPE_GROUPS[key]:
				if not out.has(String(sub)):
					out.append(String(sub))
		elif key != "" and not out.has(key):
			out.append(key)
	return out


## "@rebel"/"@base"/"@cube" dipendono dalla Fazione in gioco per quell'effetto.
func _dynamic_type(token: String, ctx: Dictionary) -> String:
	var fid := String(ctx.get("faction", executing_faction))
	match token:
		"@rebel":
			return "cr_rebel" if fid == "reclaimer" else "rd_rebel"
		"@base":
			match fid:
				"reclaimer": return "cr_base"
				"red_dust": return "rd_base"
				"corporations": return "corp_base"
				_: return "mg_base"
		"@cube":
			match fid:
				"corporations": return "security"
				"earthgov": return "eg_troop"
				_: return "mg_troop"
	return ""


## Unità mobili di una Fazione (§5.0): quelle che può muovere di suo.
func _own_types(fid: String) -> Array:
	match fid:
		"marsgov": return ["mg_troop"]
		"corporations": return ["security", "specops"]
		"earthgov": return ["eg_troop"]
		"red_dust": return ["rd_rebel"]
		"reclaimer": return ["cr_rebel"]
	return []


func _count_types(sid: String, types, piece_state: String = "", ctx: Dictionary = {}) -> int:
	var n := 0
	for t in _expand_types(types, ctx):
		n += module.count_in(state, sid, String(t), null if piece_state == "" else piece_state)
	return n


## Quantità calcolata: {kind: spaces|pieces|marker|population|last|fixed}.
func _count(desc, ctx: Dictionary) -> int:
	if typeof(desc) == TYPE_INT or typeof(desc) == TYPE_FLOAT:
		return int(desc)
	if typeof(desc) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = desc
	var spaces: Array = _spaces(d.get("where", {"filter": d.get("filter", {})}), ctx)
	if d.has("where") and d.has("filter"):
		var kept: Array = []
		for sid in spaces:
			if _matches(String(sid), d["filter"], ctx):
				kept.append(sid)
		spaces = kept
	var total := 0
	match String(d.get("kind", "fixed")):
		"fixed":
			total = int(d.get("value", 0))
		"last":
			total = int(ctx.get("last", 0))
		"spaces":
			total = spaces.size()
		"pieces":
			for sid in spaces:
				total += _count_types(String(sid), d.get("types", []),
					String(d.get("state", "")), ctx)
		"marker":
			for sid in spaces:
				total += module.marker(state, String(sid), String(d.get("name", "")))
		"population":
			for sid in spaces:
				total += module.population(state, String(sid))
		"resources":
			total = state.get_resources(String(d.get("faction", "marsgov")))
		"var":
			total = int((ctx.get("vars", {}) as Dictionary).get(String(d.get("name", "")), 0))
	if d.has("per"):
		var q := float(total) / float(maxi(1, int(d["per"])))
		total = int(ceil(q)) if String(d.get("round", "down")) == "up" else int(floor(q))
	if d.has("mult"):
		total *= int(d["mult"])
	if d.has("max"):
		total = mini(total, int(d["max"]))
	return total


## `when` su un effetto: una condizione o una lista di condizioni, tutte da
## soddisfare. Ogni condizione è {count, min?, max?}.
func _condition_ok(cond, ctx: Dictionary) -> bool:
	if typeof(cond) == TYPE_ARRAY:
		for c in cond:
			if not _condition_ok(c, ctx):
				return false
		return true
	if typeof(cond) != TYPE_DICTIONARY:
		return true
	var d: Dictionary = cond
	var value := _count(d.get("count", 0), ctx)
	return value >= int(d.get("min", -99999)) and value <= int(d.get("max", 99999))


func _amount(e: Dictionary, ctx: Dictionary) -> int:
	if e.has("delta"):
		return int(e["delta"])
	if e.has("count"):
		return _count(e["count"], ctx)
	if e.has("delta_per"):
		return int(e["delta_per"]) * _count(e.get("times", {}), ctx)
	return 0


func _faction_of(value, ctx: Dictionary) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		if d.has("choice"):
			return String(ctx["choices"].get(String(d["choice"]), ""))
		if d.has("most_rebels_in"):
			return _most_rebels(_spaces(d["most_rebels_in"], ctx))
	var fid := String(value)
	if fid == "" or fid == "executing":
		return executing_faction
	return fid


## §7.0 (#11): la Fazione Ribelle con più forze negli spazi indicati; a parità
## decide chi esegue l'Evento (se è un Ribelle), altrimenti il Red Dust.
func _most_rebels(spaces: Array) -> String:
	var rd := 0
	var cr := 0
	for sid in spaces:
		rd += _count_types(String(sid), ["rd_rebel", "rd_base"])
		cr += _count_types(String(sid), ["cr_rebel", "cr_base"])
	if rd > cr:
		return "red_dust"
	if cr > rd:
		return "reclaimer"
	return executing_faction if executing_faction in RDRModule.REBEL_FACTIONS else "red_dust"


func _free_ops() -> Array:
	if not state.tracks.has("pending_free_ops"):
		state.tracks["pending_free_ops"] = []
	return state.tracks["pending_free_ops"]


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid


# ---------------------------------------------------------------------------
# Effetti atomici
# ---------------------------------------------------------------------------

## Applica un effetto. Restituisce 1 se ha fatto qualcosa (per il conteggio
## `applied` restituito da play()).
func _apply(e: Dictionary, ctx: Dictionary) -> int:
	# Alcuni effetti valgono solo per la Fazione indicata: la si mette nel
	# contesto perché "@rebel" e simili si risolvano correttamente.
	if e.has("faction"):
		ctx["faction"] = _faction_of(e["faction"], ctx)
	if e.has("when") and not _condition_ok(e["when"], ctx):
		return 0
	match String(e.get("op", "")):
		"capture":
			# Memorizza una quantità per riusarla dopo (kind "var").
			(ctx["vars"] as Dictionary)[String(e.get("id", ""))] = _count(e.get("count", 0), ctx)
			return 0
		"branch":
			var picked := String(ctx["choices"].get(String(e.get("choice", "")), ""))
			var done := 0
			for sub in e.get("cases", {}).get(picked, []):
				done += _apply(sub, ctx)
			return done
		"note":
			log_lines.append(String(e.get("text", "")))
			return 1

		# --- tracciati -----------------------------------------------------
		"profits":
			var d := _amount(e, ctx)
			state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) + d, 0, 50)
			ctx["last"] = absi(d)
			return 1
		"resources":
			var fid := _faction_of(e.get("faction", "marsgov"), ctx)
			module.resources_delta(state, fid, _amount(e, ctx))
			return 1
		"resource_transfer":
			var from_f := _faction_of(e.get("from", "marsgov"), ctx)
			var to_f := _faction_of(e.get("to", "red_dust"), ctx)
			# §8.2: se le Risorse verrebbero tolte a una Fazione NP, che non le
			# traccia, chi le riceve le guadagna comunque per intero.
			var moved: int = _amount(e, ctx)
			if not module.is_np(state, from_f):
				moved = mini(moved, state.get_resources(from_f))
			module.resources_delta(state, from_f, -moved)
			module.resources_delta(state, to_f, moved)
			log_lines.append("%d Risorse da %s a %s." % [moved, from_f, to_f])
			ctx["last"] = moved
			return 1
		"eg_side":
			act.set_eg(String(e.get("side", "EG+")))
			return 1
		"eg_confidence":
			var steps := _amount(e, ctx)
			var boxes: int = maxi(1, module.eg_boxes.size())
			state.tracks["eg_confidence"] = clampi(
				int(state.tracks.get("eg_confidence", 0)) + steps, 0, boxes - 1)
			if steps != 0:
				log_lines.append("EG Confidence: %+d casella/e." % steps)
			return 1
		"supply_earth":
			module.add_marker(state, "earth", "supply", _amount(e, ctx))
			return 1
		"population_earth":
			module.add_marker(state, "earth", "population", _amount(e, ctx))
			return 1
		"displaced":
			var delta := _amount(e, ctx)
			var cur := int(state.tracks.get("displaced_population", 0))
			state.tracks["displaced_population"] = maxi(0, cur + delta)
			ctx["last"] = absi(state.tracks["displaced_population"] - cur)
			return 1
		"displaced_clear":
			var had := int(state.tracks.get("displaced_population", 0))
			state.tracks["displaced_population"] = 0
			ctx["last"] = had
			log_lines.append("Displaced Population svuotata (%d marker)." % had)
			return 1

		# --- Supporto / Opposizione / Infrastruttura ------------------------
		"shift":
			return _op_shift(e, ctx)
		"set_support":
			var lvl: int = RDRModule.SUPPORT_KEY_MAP.get(
				String(e.get("level", "neutral")), CoinEnums.Support.NEUTRAL)
			for sid in _spaces(e.get("where", {}), ctx):
				state.spaces[String(sid)].support = lvl
				act.normalize_support(String(sid))
			return 1
		"damage":
			var placed := 0
			for sid in _spaces(e.get("where", {}), ctx):
				for i in range(int(e.get("count", 1))):
					if act.place_damage(String(sid)):
						placed += 1
			ctx["last"] = placed
			return 1
		"remove_damage":
			return _op_remove_damage(e, ctx)
		"clear_supply":
			var cleared := 0
			for sid in _spaces(e.get("where", {}), ctx):
				cleared += module.marker(state, String(sid), "supply")
				module.set_marker(state, String(sid), "supply", 0)
			ctx["last"] = cleared
			return 1
		"storm":
			return _op_storm(e, ctx)

		# --- pezzi ----------------------------------------------------------
		"place":
			return _op_place(e, ctx)
		"remove":
			return _op_remove(e, ctx)
		"move":
			return _op_move(e, ctx)
		"replace":
			return _op_replace(e, ctx)
		"activate":
			var n := 0
			for sid in _spaces(e.get("where", {}), ctx):
				for t in _expand_types(e.get("types", "rebels"), ctx):
					n += act.activate(String(sid), String(t), 99)
			ctx["last"] = n
			return 1
		"hide":
			var h := 0
			for sid in _spaces(e.get("where", {}), ctx):
				for t in _expand_types(e.get("types", "rebels"), ctx):
					h += act.hide(String(sid), String(t), 99)
			ctx["last"] = h
			return 1
		"flip":
			return _op_flip(e, ctx)
		"remove_from_game":
			return _op_remove_from_game(e, ctx)

		# --- azioni condivise ------------------------------------------------
		"house":
			var actor := _faction_of(e.get("faction", "marsgov"), ctx)
			var did := 0
			for sid in _spaces(e.get("where", {}), ctx):
				if act.house(String(sid), actor):
					did += 1
			ctx["last"] = did
			return 1
		"repair":
			var ractor := _faction_of(e.get("faction", "marsgov"), ctx)
			var rdid := 0
			for sid in _spaces(e.get("where", {}), ctx):
				if act.repair(String(sid), ractor):
					rdid += 1
			ctx["last"] = rdid
			return 1
		"aldrin_cycler":
			if rounds == null:
				log_lines.append("Aldrin Cycler: fase non eseguita (round non collegati).")
				return 0
			rounds.aldrin_cycler()
			log_lines.append_array(rounds.log_lines)
			rounds.log_lines.clear()
			return 1

		# --- carte, Eligibility, Operazioni gratuite --------------------------
		"free_op":
			return _op_free(e, ctx)
		"ineligible":
			var who := _faction_of(e.get("faction", "executing"), ctx)
			var forced: Array = state.tracks.get("forced_ineligible", [])
			if not forced.has(who):
				forced.append(who)
			state.tracks["forced_ineligible"] = forced
			log_lines.append("%s è Non Disponibile per tutto il prossimo Event Round." % who)
			return 1
		"stay_eligible":
			var keep := _faction_of(e.get("faction", "executing"), ctx)
			var stay: Array = state.tracks.get("stay_eligible", [])
			if not stay.has(keep):
				stay.append(keep)
			state.tracks["stay_eligible"] = stay
			log_lines.append("%s resta Disponibile." % keep)
			return 1
		"draw_asset":
			if cards == null:
				return 0
			var drawn := cards.draw_asset(_count(e.get("count", 1), ctx))
			log_lines.append_array(cards.log_lines)
			cards.log_lines.clear()
			log_lines.append("I Reclaimer pescano %d Asset card." % drawn)
			return 1
		"discard_asset":
			return _op_discard_asset(e, ctx)
		"campaign":
			return _op_campaign(e, ctx)
		"rodgers_line":
			if not state.active_capabilities.has("rodgers_line"):
				state.active_capabilities.append("rodgers_line")
			log_lines.append("La Rodgers Line è aperta: Europa ↔ Tereshkova via Maglev.")
			return 1
	return 0


func _op_shift(e: Dictionary, ctx: Dictionary) -> int:
	var levels := int(e.get("levels", 1))
	var toward := String(e.get("toward", ""))
	var moved := 0
	for sid in _spaces(e.get("where", {}), ctx):
		var s := String(sid)
		var steps := levels
		if toward == "neutral":
			var cur: int = state.spaces[s].support
			if cur == CoinEnums.Support.NEUTRAL:
				continue
			steps = -signi(cur) * absi(levels)
		for i in range(absi(steps)):
			if act.shift(s, signi(steps)) != 0:
				moved += 1
	ctx["last"] = moved
	return 1


func _op_remove_damage(e: Dictionary, ctx: Dictionary) -> int:
	var removed := 0
	for sid in _spaces(e.get("where", {}), ctx):
		var s := String(sid)
		var have := module.marker(state, s, "damage")
		var take: int = have if bool(e.get("all", true)) else mini(have, int(e.get("count", 1)))
		if take <= 0:
			continue
		module.add_marker(state, s, "damage", -take)
		# §1.7: il quadrato verde torna scoperto e il marker Popolazione lascia
		# la casella Displaced Population.
		state.tracks["displaced_population"] = maxi(0,
			int(state.tracks.get("displaced_population", 0)) - take)
		removed += take
		log_lines.append("%s: rimossi %d Danni." % [_name(s), take])
	ctx["last"] = removed
	return 1


func _op_storm(e: Dictionary, ctx: Dictionary) -> int:
	var level := int(e.get("level", 2))
	var on_map := 0
	for sid in module.mars_spaces(state):
		if module.storm(state, String(sid)) > 0:
			on_map += 1
	var placed := 0
	for sid in _spaces(e.get("where", {}), ctx):
		if on_map + placed >= MAX_STORMS:
			break
		if module.storm(state, String(sid)) > 0:
			continue
		module.set_marker(state, String(sid), "storm", level)
		placed += 1
	log_lines.append("Tempeste piazzate: %d." % placed)
	ctx["last"] = placed
	return 1


func _op_place(e: Dictionary, ctx: Dictionary) -> int:
	var spaces := _spaces(e.get("where", {}), ctx)
	if spaces.is_empty():
		return 0
	var placed := 0
	for spec in e.get("pieces", []):
		var p: Dictionary = spec
		var kinds := _expand_types(p.get("type", ""), ctx)
		if kinds.is_empty():
			continue
		var type_id := String(kinds[0])
		var piece_state := String(p.get("state", ""))
		var per_space := int(p.get("count", 1))
		if String(e.get("mode", "each")) == "spread":
			# Un pezzo per ogni scelta: gli spazi ripetuti ne ricevono di più.
			var total := _count(p.get("total", spaces.size()), ctx)
			for i in range(total):
				var sid := String(spaces[i % spaces.size()])
				if _place_guard(sid, type_id):
					placed += module.place_from_available(state, sid, type_id, 1, piece_state)
		else:
			for sid in spaces:
				var s := String(sid)
				if not _place_guard(s, type_id):
					continue
				placed += module.place_from_available(state, s, type_id, per_space, piece_state)
	ctx["last"] = placed
	return 1


## §1.3: non più di 2 Basi per spazio (6 nella Wilderness, 0 su Phobos).
func _place_guard(sid: String, type_id: String) -> bool:
	var pt: PieceTypeDef = state.game_def.piece_type(type_id)
	if pt != null and pt.is_base:
		return act.can_place_base(sid)
	return true


func _op_remove(e: Dictionary, ctx: Dictionary) -> int:
	var types := _expand_types(e.get("types", []), ctx)
	var dest := String(e.get("dest", ""))
	var bases_last := bool(e.get("bases_last", true))
	var all := bool(e.get("all", false))
	var per_space := -1 if all else _count(e.get("count", 1), ctx)
	var budget := 99999 if (all or not e.has("total")) else _count(e["total"], ctx)
	var removed := 0
	var piece_state = null if String(e.get("state", "")) == "" else String(e.get("state", ""))
	for sid in _spaces(e.get("where", {}), ctx):
		if budget <= 0:
			break
		var s := String(sid)
		var here := 0
		var ordered: Array = []
		var bases: Array = []
		for t in types:
			var pt: PieceTypeDef = state.game_def.piece_type(String(t))
			if bases_last and pt != null and pt.is_base:
				bases.append(String(t))
			else:
				ordered.append(String(t))
		ordered.append_array(bases)
		for t in ordered:
			var type_id := String(t)
			while budget > 0 and (per_space < 0 or here < per_space):
				var pt2: PieceTypeDef = state.game_def.piece_type(type_id)
				if pt2 != null and pt2.is_base and bool(e.get("protect_bases", true)) \
						and not act.base_removable(s, type_id):
					break
				var to := dest if dest != "" else act.removal_dest(type_id)
				if module.remove_pieces(state, s, type_id, 1, to, piece_state) == 0:
					break
				here += 1
				removed += 1
				budget -= 1
		if here > 0:
			act.normalize_support(s)
	ctx["last"] = removed
	if removed > 0:
		log_lines.append("Rimosse %d forze." % removed)
	return 1


func _op_move(e: Dictionary, ctx: Dictionary) -> int:
	var dests := _spaces(e.get("to", {}), ctx)
	if dests.is_empty():
		return 0
	var to_sid := String(dests[0])
	var types := _expand_types(e.get("types", []), ctx)
	var all := bool(e.get("all", false))
	var budget := 99999 if all else _count(e.get("count", 1), ctx)
	# `per_from` limita quanto si può prelevare da ciascuna origine ("4 cubi da
	# ciascuno di 2 Labirinti").
	var per_from := 99999 if (all or not e.has("per_from")) else _count(e["per_from"], ctx)
	var moved := 0
	for sid in _spaces(e.get("from", {}), ctx):
		var s := String(sid)
		if s == to_sid:
			continue
		var here := 0
		for t in types:
			if budget <= 0 or here >= per_from:
				break
			var k := module.move_pieces(state, s, to_sid, String(t),
				mini(budget, per_from - here))
			moved += k
			here += k
			budget -= k
	ctx["last"] = moved
	if moved > 0:
		log_lines.append("Spostate %d unità verso %s." % [moved, _name(to_sid)])
	return 1


func _op_replace(e: Dictionary, ctx: Dictionary) -> int:
	var from_types := _expand_types(e.get("from", []), ctx)
	var to_types := _expand_types(e.get("to", []), ctx)
	if to_types.is_empty():
		return 0
	var budget := _count(e.get("count", 1), ctx)
	# Con una scelta ripetuta ("fino a 6 cubi") ogni occorrenza vale 1
	# sostituzione: `per_space` dice quante se ne fanno per ciascuna.
	var per_space := _count(e.get("per_space", 1), ctx)
	var done := 0
	for sid in _spaces(e.get("where", {}), ctx):
		var s := String(sid)
		var here := 0
		for t in from_types:
			while budget > 0 and here < per_space:
				var type_id := String(t)
				var new_type := _replacement_for(type_id, to_types)
				if new_type == "":
					break
				if module.remove_pieces(state, s, type_id, 1, act.removal_dest(type_id)) == 0:
					break
				if not _place_guard(s, new_type):
					break
				module.place_from_available(state, s, new_type, 1)
				budget -= 1
				here += 1
				done += 1
	ctx["last"] = done
	if done > 0:
		log_lines.append("Sostituite %d unità." % done)
	return 1


## Una Base si sostituisce con una Base, un'unità con un'unità (§7.0).
func _replacement_for(type_id: String, candidates: Array) -> String:
	var src: PieceTypeDef = state.game_def.piece_type(type_id)
	var want_base: bool = src != null and src.is_base
	for c in candidates:
		var pt: PieceTypeDef = state.game_def.piece_type(String(c))
		if pt != null and pt.is_base == want_base:
			return String(c)
	return ""


func _op_flip(e: Dictionary, ctx: Dictionary) -> int:
	var types := _expand_types(e.get("types", e.get("type", "")), ctx)
	if types.is_empty():
		return 0
	var type_id := String(types[0])
	var from_state := String(e.get("from_state", "basic"))
	var to_state := String(e.get("to_state", "terraforming"))
	var per_space := int(e.get("count", 1))
	var budget := int(e.get("total", 99999))
	var fid: String = RDRModule.PIECE_OWNER.get(type_id, "")
	var flipped := 0
	for sid in _spaces(e.get("where", {}), ctx):
		if budget <= 0:
			break
		var s := String(sid)
		var n: int = mini(per_space, budget)
		var k := state.flip_pieces(fid, type_id, s, from_state, to_state, n)
		flipped += k
		budget -= k
	ctx["last"] = flipped
	if flipped > 0:
		log_lines.append("Girate %d Basi (%s)." % [flipped, to_state])
	return 1


## §7.0 (#18 ombreggiato): pezzi tolti DAL GIOCO, non fra le Disponibili.
func _op_remove_from_game(e: Dictionary, ctx: Dictionary) -> int:
	var types := _expand_types(e.get("types", e.get("type", "")), ctx)
	if types.is_empty():
		return 0
	var type_id := String(types[0])
	var n := module.take_available(state, type_id, int(e.get("count", 1)))
	if n > 0:
		var fid: String = RDRModule.PIECE_OWNER.get(type_id, "")
		var key := "%s:%s" % [fid, type_id]
		state.out_of_play[key] = int(state.out_of_play.get(key, 0)) + n
		log_lines.append("%d %s rimossi dal gioco." % [n, type_id])
	ctx["last"] = n
	return 1


func _op_discard_asset(e: Dictionary, ctx: Dictionary) -> int:
	if cards == null:
		return 0
	var n := int(e.get("count", 1))
	var hand: Array = cards.hand()
	var done := 0
	while done < n and not hand.is_empty():
		# "at random": senza generatore si scarta dal fondo della mano.
		var idx := hand.size() - 1
		cards.discard_pile().append(hand[idx])
		hand.remove_at(idx)
		done += 1
	log_lines.append("I Reclaimer scartano %d Asset card." % done)
	ctx["last"] = done
	return 1


func _op_campaign(e: Dictionary, ctx: Dictionary) -> int:
	if cards == null:
		return 0
	if bool(e.get("remove", false)):
		var was := cards.campaign_in_play()
		cards.remove_campaign()
		log_lines.append("Campaign card «%s» rimossa dal gioco." % cards.campaign_title(was))
		return 1
	cards.draw_campaign_into_play(int(e.get("draw", 1)))
	log_lines.append_array(cards.log_lines)
	cards.log_lines.clear()
	return 1


## Registra un'Operazione (o Attività Speciale) gratuita: la esegue il chiamante
## con il motore delle Operazioni, senza pagarne il costo.
func _op_free(e: Dictionary, ctx: Dictionary) -> int:
	var who := _faction_of(e.get("faction", "executing"), ctx)
	var entry := {
		"faction": who,
		"operation": _operation_token(String(e.get("operation", "")), who),
		"special": String(e.get("special", "")),
		"spaces": _spaces(e.get("where", {}), ctx),
		"note": String(e.get("note", "")),
		# Contesto per gli effetti "a seguire", applicati da apply_after().
		"after": e.get("after", []),
		"choices": (ctx["choices"] as Dictionary).duplicate(true),
		"vars": (ctx.get("vars", {}) as Dictionary).duplicate(true),
	}
	_free_ops().append(entry)
	var label := String(entry["operation"])
	if label == "":
		label = String(entry["special"])
	if label == "":
		label = "Operazione a scelta"
	log_lines.append("Operazione gratuita concessa: %s a %s%s.%s" % [
		label, who,
		"" if (entry["spaces"] as Array).is_empty()
			else " (%s)" % ", ".join(PackedStringArray(entry["spaces"])),
		"" if entry["note"] == "" else " — %s" % entry["note"]])
	return 1


## "@assault_or_attack" e "@march_or_travel" dipendono da chi esegue l'Evento.
func _operation_token(op_id: String, fid: String) -> String:
	match op_id:
		"@assault_or_attack":
			return "assault" if fid in RDRModule.COIN_FACTIONS else "attack"
		"@march_or_travel":
			return "travel" if fid == "reclaimer" else "march"
	return op_id
