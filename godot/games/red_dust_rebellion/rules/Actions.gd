class_name RDRActions
extends RefCounted

## Azioni condivise da Operazioni, Attività Speciali, Eventi e round periodici:
## House e Repair (§1.7), spostamento di Supporto/Opposizione (§1.8), piazzamento
## del Danno, regole di movimento (adiacenza, Maglev, Spaceport, tempeste, §1.2 e
## §1.10) e le priorità di rimozione "Basi per ultime" (§5.5, §5.9).

const SUPPORT_MIN := CoinEnums.Support.ACTIVE_OPPOSITION
const SUPPORT_MAX := CoinEnums.Support.ACTIVE_SUPPORT

var state: GameState
var module: RDRModule
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule) -> void:
	state = p_state
	module = p_module


func log_line(text: String) -> void:
	log_lines.append(text)


# ---------------------------------------------------------------------------
# EarthGov Confidence (§1.2 / §7.5)
# ---------------------------------------------------------------------------

## "Set the EG Confidence marker to EG+/EG-": gira il marcatore, non muove la
## traccia (il movimento avviene nel Flashpoint Round).
func set_eg(side: String) -> void:
	state.tracks["eg_side"] = 1 if side == "EG+" else -1


# ---------------------------------------------------------------------------
# Supporto / Opposizione (§1.8)
# ---------------------------------------------------------------------------

## Sposta lo spazio di `steps` livelli (positivi verso il Supporto Attivo).
## Gli spazi Spopolati sono sempre Neutrali.
func shift(sid: String, steps: int) -> int:
	var st: SpaceState = state.spaces[sid]
	if module.population(state, sid) <= 0:
		st.support = CoinEnums.Support.NEUTRAL
		return 0
	var before: int = st.support
	st.support = clampi(before + steps, SUPPORT_MIN, SUPPORT_MAX)
	return st.support - before


## Rimuove il marker Supporto/Opposizione se lo spazio è diventato Spopolato.
func normalize_support(sid: String) -> void:
	if module.population(state, sid) <= 0:
		state.spaces[sid].support = CoinEnums.Support.NEUTRAL


# ---------------------------------------------------------------------------
# Popolazione e Danno (§1.7)
# ---------------------------------------------------------------------------

## §6.1: le Truppe MarsGov Fortificate assorbono un Danno ciascuna.
func fortified(sid: String) -> int:
	return module.marker(state, sid, "fortified")


## Piazza un Danno. Restituisce false se non è possibile (nessun quadrato verde
## scoperto). Una Truppa Fortificata, se c'è, assorbe il Danno.
func place_damage(sid: String) -> bool:
	if fortified(sid) > 0:
		module.add_marker(state, sid, "fortified", -1)
		module.remove_pieces(state, sid, "mg_troop", 1, "available")
		log_line("%s: una Truppa Fortificata assorbe il Danno." % _name(sid))
		return false
	if module.marker(state, sid, "damage") >= int(module.printed_pop.get(sid, 0)):
		return false
	# Prima spariscono i marker Popolazione gialli (tornano al pool generale),
	# poi il Danno copre il quadrato verde più a destra.
	module.set_marker(state, sid, "pop_markers", 0)
	module.add_marker(state, sid, "damage", 1)
	state.tracks["displaced_population"] = int(state.tracks.get("displaced_population", 0)) + 1
	normalize_support(sid)
	return true


func can_house(sid: String) -> bool:
	return int(state.tracks.get("displaced_population", 0)) > 0 \
		and module.marker(state, sid, "damage") == 0 \
		and module.free_infra_slots(state, sid) > 0


## §1.7: sposta un marker Popolazione da Displaced Population nello spazio.
## L'effetto sull'EG Confidence dipende da chi esegue l'azione.
func house(sid: String, actor: String, eg_choice: String = "EG+") -> bool:
	if not can_house(sid):
		return false
	state.tracks["displaced_population"] = int(state.tracks["displaced_population"]) - 1
	module.add_marker(state, sid, "pop_markers", 1)
	match actor:
		"marsgov": set_eg("EG+")
		"red_dust": set_eg("EG-")
		"corporations": set_eg(eg_choice)
	log_line("%s: House (%s)." % [_name(sid), actor])
	return true


func can_repair(sid: String, actor: String) -> bool:
	if module.marker(state, sid, "damage") <= 0:
		return false
	if int(state.tracks.get("displaced_population", 0)) <= 0:
		return false
	match actor:
		"marsgov":
			return state.get_resources("marsgov") >= 3
		"red_dust":
			return state.get_resources("red_dust") >= 2
		"corporations":
			return module.count_in(state, sid, "security") > 0
	return true


## §1.7: rimuove un Danno consumando un marker da Displaced Population.
## MarsGov paga 3 Risorse (→EG+), Red Dust 2 (→EG−), le Corporations rimuovono
## una Security nello spazio (→EG+ o EG− a scelta).
func repair(sid: String, actor: String, eg_choice: String = "EG+") -> bool:
	if not can_repair(sid, actor):
		return false
	match actor:
		"marsgov":
			state.add_resources("marsgov", -3, 50)
			set_eg("EG+")
		"red_dust":
			state.add_resources("red_dust", -2, 50)
			set_eg("EG-")
		"corporations":
			module.remove_pieces(state, sid, "security", 1, "available")
			set_eg(eg_choice)
	state.tracks["displaced_population"] = int(state.tracks["displaced_population"]) - 1
	module.add_marker(state, sid, "damage", -1)
	log_line("%s: Repair (%s)." % [_name(sid), actor])
	return true


## §5.1 Pacify / §4.3 Support Phase: fino a due azioni fra House, Repair e
## "3 Risorse per 1 livello verso il Supporto Attivo", in uno spazio con
## Controllo COIN.
func pacify(sid: String, actions: Array) -> int:
	if state.spaces[sid].control != "coin":
		return 0
	var done := 0
	for a in actions:
		if done >= 2:
			break
		match String(a):
			"house":
				if house(sid, "marsgov"):
					done += 1
			"repair":
				if repair(sid, "marsgov"):
					done += 1
			"shift":
				if state.get_resources("marsgov") >= 3 and shift(sid, 1) != 0:
					state.add_resources("marsgov", -3, 50)
					done += 1
	return done


## §4.3 Agitate: come Pacify, ma per Red Dust negli spazi sotto il proprio
## Controllo e verso l'Opposizione Attiva, a 1 Risorsa per livello.
func agitate(sid: String, actions: Array) -> int:
	if state.spaces[sid].control != "red_dust":
		return 0
	var done := 0
	for a in actions:
		if done >= 2:
			break
		match String(a):
			"house":
				if house(sid, "red_dust"):
					done += 1
			"repair":
				if repair(sid, "red_dust"):
					done += 1
			"shift":
				if state.get_resources("red_dust") >= 1 and shift(sid, -1) != 0:
					state.add_resources("red_dust", -1, 50)
					done += 1
	return done


# ---------------------------------------------------------------------------
# Movimento (§1.2, §1.10, §5.3, §5.4, §5.7, §5.8)
# ---------------------------------------------------------------------------

## §1.10: un Deserto con Raging Storm non può essere scelto per Operazioni,
## Attività Speciali o Eventi; un Labirinto sì, ma le forze non possono entrarvi
## né uscirne. I Reclaimer con Travel ignorano tutto questo.
func selectable(sid: String, ignore_storms: bool = false) -> bool:
	if ignore_storms:
		return true
	return not (module.is_desert(state, sid) and module.has_raging_storm(state, sid))


func can_enter(sid: String, ignore_storms: bool = false) -> bool:
	return ignore_storms or not module.has_raging_storm(state, sid)


func can_leave(sid: String, ignore_storms: bool = false) -> bool:
	return ignore_storms or not module.has_raging_storm(state, sid)


## Spazi da cui si può raggiungere `dest` in un passo di movimento "a piedi".
func adjacent_origins(dest: String, ignore_storms: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	var sd: SpaceDef = state.game_def.space(dest)
	if sd == null:
		return out
	for a in sd.adjacent:
		if can_leave(String(a), ignore_storms):
			out.append(String(a))
	return out


## §1.7: uno Spaceport è utilizzabile solo se il Labirinto non ha Danno né
## Raging Storm. Phobos non può essere Danneggiata, quindi il suo è sempre attivo.
func spaceport_open(sid: String) -> bool:
	if not module.is_labyrinth(state, sid):
		return false
	if sid == "phobos":
		return true
	return module.marker(state, sid, "damage") == 0 and not module.has_raging_storm(state, sid)


## §5.3/§5.7: Labirinti raggiungibili via Spaceport da `sid` per la Fazione
## `control` ("coin" per Secure/Recon, "red_dust" per March). Serve il Controllo
## richiesto a entrambi i capi.
func spaceport_links(sid: String, control: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not spaceport_open(sid) or state.spaces[sid].control != control:
		return out
	for s in state.game_def.spaces:
		if s.id == sid or not module.is_labyrinth(state, s.id):
			continue
		if spaceport_open(s.id) and state.spaces[s.id].control == control:
			out.append(s.id)
	return out


## §5.3/§5.7: Labirinti collegati via Maglev, escluse le tratte con Raging Storm.
func maglev_links(sid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for other in module.maglev_links(state, sid):
		if not module.has_raging_storm(state, String(other)):
			out.append(String(other))
	return out


# ---------------------------------------------------------------------------
# Attivazione e rimozione di forze
# ---------------------------------------------------------------------------

## §1.3: gira un Ribelle/SpecOps Nascosto sul lato Attivo. Restituisce quanti.
func activate(sid: String, type_id: String, n: int) -> int:
	var fid: String = RDRModule.PIECE_OWNER[type_id]
	var st: SpaceState = state.spaces[sid]
	var moved: int = mini(n, st.count(fid, type_id, "hidden"))
	if moved > 0:
		st.remove_piece(fid, type_id, moved, "hidden")
		st.add_piece(fid, type_id, moved, "active")
	return moved


func hide(sid: String, type_id: String, n: int) -> int:
	var fid: String = RDRModule.PIECE_OWNER[type_id]
	var st: SpaceState = state.spaces[sid]
	var moved: int = mini(n, st.count(fid, type_id, "active"))
	if moved > 0:
		st.remove_piece(fid, type_id, moved, "active")
		st.add_piece(fid, type_id, moved, "hidden")
	return moved


## Attiva un Ribelle di una Fazione qualsiasi (Secure/Recon attivano i Ribelli
## nemici presenti, senza distinzione fra Red Dust e Reclaimer).
func activate_any_rebel(sid: String, n: int) -> int:
	var done := 0
	for type_id in ["rd_rebel", "cr_rebel"]:
		if done >= n:
			break
		done += activate(sid, type_id, n - done)
	return done


## §1.3: le Basi si rimuovono solo quando non restano unità amiche a difenderle.
## Le Basi Ribelli sono protette dai Ribelli della PROPRIA Fazione; quelle COIN
## da tutti i cubi COIN e dagli SpecOps Attivi.
func base_removable(sid: String, base_id: String) -> bool:
	match base_id:
		"rd_base":
			return module.count_in(state, sid, "rd_rebel") == 0
		"cr_base":
			return module.count_in(state, sid, "cr_rebel") == 0
		_:
			var guards := module.count_in(state, sid, "mg_troop") \
				+ module.count_in(state, sid, "security") \
				+ module.count_in(state, sid, "eg_troop") \
				+ module.count_in(state, sid, "specops", "active")
			return guards == 0


## §1.3: destinazione di un pezzo rimosso — le forze Corporations ed EarthGov
## vanno nelle Casualties, le altre fra le Disponibili.
func removal_dest(type_id: String) -> String:
	return "casualties" if type_id in ["security", "specops", "corp_base", "eg_troop", "satellite"] \
		else "available"


## Rimuove `n` forze nemiche in `sid` seguendo `priority`, con le Basi per ultime.
## Restituisce l'elenco dei tipi rimossi.
func remove_enemy_forces(sid: String, priority: Array, n: int,
		only_active: bool = false) -> Array[String]:
	var removed: Array[String] = []
	var bases: Array[String] = []
	for type_id in priority:
		var t := String(type_id)
		var pt: PieceTypeDef = state.game_def.piece_type(t)
		if pt != null and pt.is_base:
			bases.append(t)
			continue
		while removed.size() < n:
			var piece_state = "active" if (only_active and pt != null and pt.states.size() > 0) else null
			if module.remove_pieces(state, sid, t, 1, removal_dest(t), piece_state) == 0:
				break
			removed.append(t)
	for base_id in bases:
		while removed.size() < n and module.count_in(state, sid, base_id) > 0:
			if not base_removable(sid, base_id):
				break
			if module.remove_pieces(state, sid, base_id, 1, removal_dest(base_id)) == 0:
				break
			removed.append(base_id)
	return removed


## §1.3: limite di Basi per spazio (2, 6 nella Wilderness, 0 su Phobos).
func base_limit(sid: String) -> int:
	if sid == "phobos":
		return 0
	if sid == "wilderness":
		return 6
	var sd: SpaceDef = state.game_def.space(sid)
	return 0 if (sd == null or sd.type == CoinEnums.SpaceType.COUNTRY) else 2


func bases_in(sid: String) -> int:
	var n := 0
	for base_id in ["mg_base", "corp_base", "rd_base", "cr_base"]:
		n += module.count_in(state, sid, base_id)
	return n


func can_place_base(sid: String) -> bool:
	return bases_in(sid) < base_limit(sid)


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid
