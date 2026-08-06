class_name RDRModule
extends RulesModule

## Modulo di gioco "Red Dust Rebellion" (Serie COIN Vol. XII, GMT 2024).
##
## Differenze strutturali rispetto agli altri COIN già implementati (Cuba Libre,
## All Bridges Burning), tutte gestite qui e non nel motore generico:
##  * il Controllo COIN è di COALIZIONE (MarsGov + Corporations + EarthGov contro
##    tutti i Ribelli), mentre Red Dust e Reclaimer controllano individualmente (§1.9);
##  * la Popolazione degli spazi è variabile in partita (marker Popolazione/Danno
##    sulla traccia Infrastruttura, §1.7): `pop` in spaces.json è il valore stampato,
##    lo stato di gioco tiene `population` per spazio;
##  * EarthGov è una Fazione non-giocante controllata a turno da MarsGov o CORP a
##    seconda della casella della traccia EG Confidence (§1.2);
##  * la soglia di vittoria dei Reclaimer è dinamica (Basi nemiche sulla mappa, §2.0).

const DATA_DIR := "res://games/red_dust_rebellion/data/"

const COIN_FACTIONS := ["marsgov", "corporations", "earthgov"]
## Le Fazioni che qualcuno gioca davvero. L'EarthGov esiste sulla plancia ma non
## ha né turno né giocatore: lo muove chi ne è Controller (§1.1).
const PLAYABLE_FACTIONS := ["marsgov", "corporations", "red_dust", "reclaimer"]
const REBEL_FACTIONS := ["red_dust", "reclaimer"]

## Fazione proprietaria di ciascun tipo di pezzo (le chiavi del setup_*.json sono
## i tipi di pezzo: il proprietario è implicito).
const PIECE_OWNER := {
	"mg_troop": "marsgov", "mg_base": "marsgov",
	"security": "corporations", "specops": "corporations", "corp_base": "corporations",
	"eg_troop": "earthgov", "satellite": "earthgov",
	"rd_rebel": "red_dust", "rd_base": "red_dust",
	"cr_rebel": "reclaimer", "cr_base": "reclaimer",
}

const SUPPORT_KEY_MAP := {
	"active_support": CoinEnums.Support.ACTIVE_SUPPORT,
	"passive_support": CoinEnums.Support.PASSIVE_SUPPORT,
	"neutral": CoinEnums.Support.NEUTRAL,
	"passive_opposition": CoinEnums.Support.PASSIVE_OPPOSITION,
	"active_opposition": CoinEnums.Support.ACTIVE_OPPOSITION,
}

## Caselle della traccia EarthGov Confidence (§1.2), dal basso verso l'alto.
var eg_boxes: Array = []
## Collegamenti Maglev fra Labirinti (§1.2): [{a, b, under_construction}].
var maglev: Array = []
## Popolazione stampata per spazio (base della traccia Infrastruttura).
var printed_pop: Dictionary = {}
## Numero di caselle Infrastruttura per spazio (2 nei Deserti, 4 nei Labirinti).
var infra_boxes: Dictionary = {}
## Valore Flashpoint stampato su ciascuna carta Evento: numero carta -> 0..4.
var card_flashpoint: Dictionary = {}
## Tabella dei tiri Dust Storm: space_id -> [[d6 bianco, d6 nero], …].
## Hellas Chaos occupa due risultati del dado nero (3 e 4).
var storm_table: Dictionary = {}


# ---------------------------------------------------------------------------
# Costruzione GameDef
# ---------------------------------------------------------------------------

func build_game_def() -> GameDef:
	var gd := GameDef.new()
	gd.title = "Red Dust Rebellion"

	var factions_data: Dictionary = _load_json(DATA_DIR + "factions.json")
	for pt in factions_data.get("piece_types", []):
		var p := PieceTypeDef.from_dict(pt)
		if pt.has("counts_for_control"):
			p.counts_for_control = bool(pt["counts_for_control"])
		gd.add_piece_type(p)
	for f in factions_data.get("factions", []):
		gd.add_faction(FactionDef.from_dict(f))
	eg_boxes = factions_data.get("eg_confidence_boxes", [])

	var spaces_data: Dictionary = _load_json(DATA_DIR + "spaces.json")
	for s in spaces_data.get("spaces", []):
		var sd := SpaceDef.from_dict(s)
		# Il tipo RDR (labyrinth/desert) resta in `terrain`: il motore generico
		# usa CITY/PROVINCE solo per sapere se lo spazio ha Popolazione.
		sd.terrain = String(s.get("type", ""))
		gd.add_space(sd)
		printed_pop[sd.id] = int(s.get("pop", 0))
		infra_boxes[sd.id] = int(s.get("infra", 0))
		if s.has("storm_die"):
			var rolls: Array = [s["storm_die"]]
			if s.has("storm_die_alt"):
				rolls.append(s["storm_die_alt"])
			storm_table[sd.id] = rolls
	maglev = spaces_data.get("maglev", [])

	var cards_data: Dictionary = _load_json(DATA_DIR + "cards.json")
	for c in cards_data.get("cards", []):
		gd.add_card(CardDef.from_dict(c))
		card_flashpoint[int(c.get("number", 0))] = int(c.get("flashpoint", 0))

	gd.tracks = {
		"eg_confidence": {"min": 0, "max": 8},
		"flashpoint": {"min": 0, "max": 5},
		"profits": {"min": 0, "max": 50},
		"dust_storm_rounds": {"min": 0, "max": 3},
		"displaced_population": {"min": 0, "max": 12},
	}
	return gd


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func apply_setup(state: GameState, scenario_id: String = "standard") -> void:
	var setup: Dictionary = _load_json(DATA_DIR + "setup_%s.json" % scenario_id)
	if setup.is_empty():
		push_warning("RDR apply_setup: scenario '%s' non trovato" % scenario_id)
		return

	for fid in setup.get("resources", {}).keys():
		state.resources[fid] = int(setup["resources"][fid])

	var tracks: Dictionary = setup.get("tracks", {})
	for tk in tracks.keys():
		if typeof(tracks[tk]) == TYPE_STRING:
			continue  # eg_confidence_side, gestito sotto
		state.tracks[tk] = int(tracks[tk])
	state.tracks["eg_side"] = 1 if String(tracks.get("eg_confidence_side", "EG-")) == "EG+" else -1
	state.tracks["displaced_population"] = int(setup.get("displaced_population", 0))

	for sid in setup.get("spaces", {}).keys():
		if not state.spaces.has(sid):
			push_warning("RDR setup: spazio sconosciuto '%s'" % sid)
			continue
		var entry: Dictionary = setup["spaces"][sid]
		var st: SpaceState = state.spaces[sid]
		_place_forces(state, sid, entry.get("forces", {}))
		st.support = SUPPORT_KEY_MAP.get(String(entry.get("support", "neutral")), CoinEnums.Support.NEUTRAL)
		var dmg := int(entry.get("damage", 0))
		if dmg > 0:
			st.markers["damage"] = dmg

	# Spazi fuori mappa (Aldrin Cycler, Orbita) e Forze Disponibili.
	for sid in setup.get("off_map", {}).keys():
		if state.spaces.has(sid):
			_place_forces(state, sid, setup["off_map"][sid])

	state.tracks["available"] = setup.get("available", {})
	recompute_all_control(state)
	refresh_victory_tracks(state)


func _place_forces(state: GameState, sid: String, forces: Dictionary) -> void:
	var st: SpaceState = state.spaces[sid]
	for key in forces.keys():
		var k := String(key)
		var n := int(forces[key])
		if not PIECE_OWNER.has(k):
			# marker non-forza (supply, population): tracciati come marker di spazio
			st.markers[k] = int(st.markers.get(k, 0)) + n
			continue
		var pt: PieceTypeDef = state.game_def.piece_type(k)
		var default_state := pt.default_state if pt != null else ""
		st.add_piece(PIECE_OWNER[k], k, n, default_state)


# ---------------------------------------------------------------------------
# Controllo (§1.9) — COIN è una coalizione, i Ribelli controllano da soli
# ---------------------------------------------------------------------------

## Forze di una Fazione in uno spazio, escludendo i pezzi che non contano per il
## Controllo (i Satelliti, §1.3).
func control_forces(state: GameState, st: SpaceState, faction: String) -> int:
	return state.control_count(faction, st)


func coin_forces(state: GameState, st: SpaceState) -> int:
	var t := 0
	for f in COIN_FACTIONS:
		t += control_forces(state, st, f)
	return t


func rebel_forces(state: GameState, st: SpaceState) -> int:
	var t := 0
	for f in REBEL_FACTIONS:
		t += control_forces(state, st, f)
	return t


## "coin", "red_dust", "reclaimer" oppure "" (Uncontrolled).
func control_of(state: GameState, sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	if sd == null:
		return ""
	if sid == "phobos":
		return "coin"  # §1.2: Phobos è permanentemente sotto Controllo COIN
	var st: SpaceState = state.spaces[sid]
	var coin := coin_forces(state, st)
	# Campaign #7 "Torture Video Leaks": le unità CORP non contribuiscono al
	# Controllo nei Labirinti.
	if campaign_active(state, 7) and is_labyrinth(state, sid):
		coin -= count_in(state, sid, "security") + count_in(state, sid, "specops")
	var rd := control_forces(state, st, "red_dust")
	var cr := control_forces(state, st, "reclaimer")
	if coin > rd + cr:
		return "coin"
	if rd > coin + cr:
		return "red_dust"
	if cr > coin + rd:
		return "reclaimer"
	return ""


func recompute_all_control(state: GameState) -> void:
	for sid in state.spaces.keys():
		state.spaces[sid].control = control_of(state, sid)


# ---------------------------------------------------------------------------
# Popolazione, Supporto/Opposizione (§1.7, §1.8)
# ---------------------------------------------------------------------------

## §1.7: la Popolazione corrente di uno spazio è quella stampata (quadrati verdi)
## meno i Danni che li coprono, più i marker Popolazione gialli sui quadrati grigi.
## Earth/Transit e gli altri box fuori mappa non hanno traccia Infrastruttura: lì
## "population" è il numero di marker nel box.
func population(state: GameState, sid: String) -> int:
	var sd: SpaceDef = state.game_def.space(sid)
	if sd == null:
		return 0
	if sd.type == CoinEnums.SpaceType.COUNTRY:
		return marker(state, sid, "population")
	return maxi(0, int(printed_pop.get(sid, 0))
		- marker(state, sid, "damage") + marker(state, sid, "pop_markers"))


## Quadrati grigi liberi dove si può piazzare un marker Popolazione (House, §1.7).
func free_infra_slots(state: GameState, sid: String) -> int:
	var boxes := int(infra_boxes.get(sid, 0))
	var printed := int(printed_pop.get(sid, 0))
	return maxi(0, boxes - printed - marker(state, sid, "pop_markers"))


## §1.8: Passivo conta 1 punto per Popolazione, Attivo 2. Gli spazi senza
## Popolazione sono sempre Neutrali.
func total_support(state: GameState) -> int:
	var sum := 0
	for sid in state.spaces.keys():
		var lvl: int = state.spaces[sid].support
		if lvl > 0:
			sum += lvl * population(state, sid)
	return sum


func total_opposition(state: GameState) -> int:
	var sum := 0
	for sid in state.spaces.keys():
		var lvl: int = state.spaces[sid].support
		if lvl < 0:
			sum += -lvl * population(state, sid)
	return sum


# ---------------------------------------------------------------------------
# Traccia EarthGov Confidence (§1.2)
# ---------------------------------------------------------------------------

func eg_box(state: GameState) -> Dictionary:
	var idx: int = clampi(int(state.tracks.get("eg_confidence", 0)), 0, eg_boxes.size() - 1)
	return eg_boxes[idx]


## Valore numerico stampato (0/1/2/4/6/8/10), sommato al totale di vittoria MarsGov.
func eg_confidence_value(state: GameState) -> int:
	return int(eg_box(state).get("value", 0))


## "marsgov", "corporations" oppure "" (nessun Controller).
func eg_controller(state: GameState) -> String:
	return String(eg_box(state).get("controller", ""))


# ---------------------------------------------------------------------------
# Conteggi per la vittoria (§2.0)
# ---------------------------------------------------------------------------

func bases_on_map(state: GameState, faction: String) -> int:
	var total := 0
	for sid in state.spaces.keys():
		var sd: SpaceDef = state.game_def.space(sid)
		if sd == null or sd.type == CoinEnums.SpaceType.COUNTRY:
			continue
		var st: SpaceState = state.spaces[sid]
		for type_id in st.pieces.get(faction, {}).keys():
			var pt: PieceTypeDef = state.game_def.piece_type(type_id)
			if pt != null and pt.is_base:
				total += st.count(faction, type_id)
	return total


func cr_controlled_spaces(state: GameState) -> int:
	var n := 0
	for sid in state.spaces.keys():
		if state.spaces[sid].control == "reclaimer":
			n += 1
	return n


func enemy_bases(state: GameState) -> int:
	var n := 0
	for f in ["marsgov", "corporations", "red_dust"]:
		n += bases_on_map(state, f)
	return n


func victory_status(state: GameState) -> Dictionary:
	var mg := total_support(state) + eg_confidence_value(state)
	var corp := int(state.tracks.get("profits", 0))
	var rd := total_opposition(state) + bases_on_map(state, "red_dust")
	var cr_value := cr_controlled_spaces(state) + bases_on_map(state, "reclaimer")
	var cr_threshold := enemy_bases(state)
	return {
		"marsgov": _vstat(mg, 34),
		"corporations": _vstat(corp, 36),
		"red_dust": _vstat(rd, 32),
		"reclaimer": _vstat(cr_value, cr_threshold),
	}


func _vstat(value: int, threshold: int) -> Dictionary:
	return {
		"value": value,
		"threshold": threshold,
		"margin": value - threshold,
		"won": value > threshold,
	}


## Aggiorna i marcatori dell'Edge Track (valori mostrati in UI).
func refresh_victory_tracks(state: GameState) -> void:
	var v := victory_status(state)
	state.tracks["support_plus_eg"] = v["marsgov"]["value"]
	state.tracks["oppose_plus_bases"] = v["red_dust"]["value"]
	state.tracks["cr_control_plus_bases"] = v["reclaimer"]["value"]
	state.tracks["enemy_bases"] = v["reclaimer"]["threshold"]


## §2.0: le parità vanno ai Reclaimer, poi MarsGov, poi Red Dust (poi CORP).
func tiebreak_order() -> PackedStringArray:
	return PackedStringArray(["reclaimer", "marsgov", "red_dust", "corporations"])


## §4.1: bonus del Passo. CORP non guadagna Risorse (attiva l'Aldrin Cycler) e i
## Reclaimer pescano una carta Asset: gestiti dal chiamante.
func pass_resources(faction: String) -> int:
	match faction:
		"marsgov": return 3
		"red_dust": return 1
		_: return 0


# ---------------------------------------------------------------------------
# Maglev / Spaceport (§1.2)
# ---------------------------------------------------------------------------

## Labirinti raggiungibili via Maglev da `sid` (esclusa la linea in costruzione
## finché l'Evento #14 non l'ha aperta).
func maglev_links(state: GameState, sid: String) -> PackedStringArray:
	var out := PackedStringArray()
	var rodgers_open: bool = state.active_capabilities.has("rodgers_line")
	for link in maglev:
		if bool(link.get("under_construction", false)) and not rodgers_open:
			continue
		if String(link["a"]) == sid:
			out.append(String(link["b"]))
		elif String(link["b"]) == sid:
			out.append(String(link["a"]))
	return out


# ---------------------------------------------------------------------------
# Forze Disponibili e movimento dei pezzi (§1.3)
# ---------------------------------------------------------------------------

## Forze Disponibili di una Fazione per tipo di pezzo.
func available(state: GameState, type_id: String) -> int:
	var pool: Dictionary = state.tracks.get("available", {})
	var fid: String = PIECE_OWNER.get(type_id, "")
	return int(pool.get(fid, {}).get(type_id, 0))


## Preleva fino a `n` pezzi dalle Disponibili; restituisce quanti ne ha presi.
## §1.3: "Forces may only be placed from Available".
func take_available(state: GameState, type_id: String, n: int) -> int:
	var pool: Dictionary = state.tracks.get("available", {})
	var fid: String = PIECE_OWNER.get(type_id, "")
	if not pool.has(fid):
		return 0
	var have := int(pool[fid].get(type_id, 0))
	var took: int = mini(have, n)
	pool[fid][type_id] = have - took
	return took


func to_available(state: GameState, type_id: String, n: int) -> void:
	if n <= 0:
		return
	var pool: Dictionary = state.tracks.get("available", {})
	var fid: String = PIECE_OWNER.get(type_id, "")
	if not pool.has(fid):
		pool[fid] = {}
	pool[fid][type_id] = int(pool[fid].get(type_id, 0)) + n


## Piazza pezzi in uno spazio prelevandoli dalle Disponibili. Restituisce quanti
## ne ha effettivamente piazzati (0 se le Disponibili sono vuote).
func place_from_available(state: GameState, sid: String, type_id: String, n: int,
		piece_state: String = "") -> int:
	var took := take_available(state, type_id, n)
	if took > 0:
		var st: SpaceState = state.spaces[sid]
		st.add_piece(PIECE_OWNER[type_id], type_id, took, _state_or_default(state, type_id, piece_state))
		# Campaign #2 "Prison Labor Revolt": −1 Profit per ogni Base CORP piazzata.
		if type_id == "corp_base" and campaign_active(state, 2):
			state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) - took, 0, 50)
	return took


## Rimuove pezzi da uno spazio e li manda in `dest`: "available", "casualties"
## oppure l'id di un altro spazio. §1.2: le forze CORP ed EarthGov rimosse vanno
## nelle Casualties, non direttamente fra le Disponibili.
func remove_pieces(state: GameState, sid: String, type_id: String, n: int,
		dest: String = "available", piece_state = null) -> int:
	var st: SpaceState = state.spaces[sid]
	var fid: String = PIECE_OWNER.get(type_id, "")
	var removed := 0
	var states: Array = st.pieces.get(fid, {}).get(type_id, {}).keys()
	if piece_state != null:
		states = [String(piece_state)]
	for s in states:
		if removed >= n:
			break
		removed += st.remove_piece(fid, type_id, n - removed, String(s))
	if removed > 0:
		if dest == "available":
			to_available(state, type_id, removed)
		else:
			state.spaces[dest].add_piece(fid, type_id, removed,
				_state_or_default(state, type_id, ""))
	return removed


## Sposta pezzi fra due spazi conservandone lo stato Nascosto/Attivo.
func move_pieces(state: GameState, from_sid: String, to_sid: String, type_id: String,
		n: int, piece_state = null) -> int:
	var fid: String = PIECE_OWNER.get(type_id, "")
	var src: SpaceState = state.spaces[from_sid]
	var dst: SpaceState = state.spaces[to_sid]
	var moved := 0
	var states: Array = src.pieces.get(fid, {}).get(type_id, {}).keys()
	if piece_state != null:
		states = [String(piece_state)]
	for s in states:
		if moved >= n:
			break
		var k := src.remove_piece(fid, type_id, n - moved, String(s))
		if k > 0:
			dst.add_piece(fid, type_id, k, String(s))
			moved += k
	return moved


## Conta i pezzi di un tipo in uno spazio (tutti gli stati, o uno solo).
func count_in(state: GameState, sid: String, type_id: String, piece_state = null) -> int:
	var fid: String = PIECE_OWNER.get(type_id, "")
	return state.spaces[sid].count(fid, type_id, piece_state)


func _state_or_default(state: GameState, type_id: String, piece_state: String) -> String:
	if piece_state != "":
		return piece_state
	var pt: PieceTypeDef = state.game_def.piece_type(type_id)
	return pt.default_state if pt != null else ""


## Marker generici di uno spazio (danno, popolazione, tempesta, supply…).
func marker(state: GameState, sid: String, name: String) -> int:
	return int(state.spaces[sid].markers.get(name, 0))


func set_marker(state: GameState, sid: String, name: String, value: int) -> void:
	if value <= 0:
		state.spaces[sid].markers.erase(name)
	else:
		state.spaces[sid].markers[name] = value


func add_marker(state: GameState, sid: String, name: String, delta: int) -> void:
	set_marker(state, sid, name, marker(state, sid, name) + delta)


## Spazi di Mars (23 settoriali + Wilderness): esclude Aldrin Cycler, Orbita,
## box di servizio e Phobos.
func mars_spaces(state: GameState) -> PackedStringArray:
	var out := PackedStringArray()
	for s in state.game_def.spaces:
		if s.type == CoinEnums.SpaceType.COUNTRY or s.id == "phobos":
			continue
		out.append(s.id)
	return out


func is_desert(state: GameState, sid: String) -> bool:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd != null and sd.terrain == "desert"


func is_labyrinth(state: GameState, sid: String) -> bool:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd != null and sd.terrain == "labyrinth"


## §1.5: è in gioco la Campaign card numero `n` del Red Dust?
func campaign_active(state: GameState, n: int) -> bool:
	return int(state.tracks.get("campaign_in_play", -1)) == n


# ---------------------------------------------------------------------------
# §8.4.1 Contatori surrogati delle Fazioni Non-Player
# ---------------------------------------------------------------------------
#
# Stanno qui, e non solo in RDRNonPlayer, perché a muoverli sono anche le
# Operazioni, i mazzi e i Round periodici, che il sistema NP non lo conoscono.
# §8.5.4: le Fazioni NP non tracciano Risorse — al loro posto NP MG ha il Supply
# Total (ogni Supply che arriva su Phobos vale 1), NP RD l'Agitate Total e NP CR
# l'Asset Total, che sostituisce la mano di Asset card e non passa mai 6.

## Massimo dell'Asset Total (§8.2): la mano dei Reclaimer è di 6 carte.
const ASSET_TOTAL_MAX := 6


## La Fazione è gestita dal sistema Non-Player?
func is_np(state: GameState, faction: String) -> bool:
	return not state.is_player(faction)


func supply_total(state: GameState) -> int:
	return int(state.tracks.get("supply_total", 0))


func agitate_total(state: GameState) -> int:
	return int(state.tracks.get("agitate_total", 0))


func asset_total(state: GameState) -> int:
	return int(state.tracks.get("asset_total", 0))


func add_supply(state: GameState, delta: int) -> void:
	state.tracks["supply_total"] = maxi(0, supply_total(state) + delta)


func add_agitate(state: GameState, delta: int) -> void:
	state.tracks["agitate_total"] = maxi(0, agitate_total(state) + delta)


func add_asset(state: GameState, delta: int) -> void:
	state.tracks["asset_total"] = clampi(asset_total(state) + delta, 0, ASSET_TOTAL_MAX)


## §1.5: è in gioco la Capability della Asset card numero `n` dei Reclaimer?
## Il confronto è per valore: dopo un salvataggio i numeri tornano dal JSON come
## float e un `has(n)` secco fallirebbe.
func capability_active(state: GameState, n: int) -> bool:
	for c in state.tracks.get("capabilities", []):
		if int(c) == n:
			return true
	return false


## Basi Reclaimer che contano in uno spazio ai fini delle Operazioni.
## Capability #23 "MPS Uplink Hacked": uno spazio con Satelliti conta come se
## avesse una Base Reclaimer in più.
func cr_bases_in(state: GameState, sid: String) -> int:
	var n := count_in(state, sid, "cr_base")
	if capability_active(state, 23) and count_in(state, sid, "satellite") > 0:
		n += 1
	return n


## §1.10: 0 = nessuna tempesta, 1 = Approaching, 2 = Raging.
func storm(state: GameState, sid: String) -> int:
	return marker(state, sid, "storm")


func has_raging_storm(state: GameState, sid: String) -> bool:
	return storm(state, sid) == 2


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("RDRModule: file non trovato %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
