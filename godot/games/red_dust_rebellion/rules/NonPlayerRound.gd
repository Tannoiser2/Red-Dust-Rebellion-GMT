class_name RDRNonPlayerRound
extends RefCounted

## §8.5.9: i Round periodici per le Fazioni Non-Player.
##
## Nel Flashpoint Round le scelte sono tre e stanno già in `RDRRounds`, che le
## chiede alle tabelle attraverso i ganci `np_piece_order` e `np_space_order`.
## Il Dust Storm Round invece ha una scheda tutta sua — Victory, Resources,
## Support, Redeploy, Reset — ed è quella che vive qui, letta da
## `data/np_dust_storm.json`.
##
## La Support Phase e il Redeploy sono le due fasi che al tavolo un giocatore
## risolverebbe a mano; per un bot diventano due procedure deterministiche, con
## le priorità a decidere gli spazi e il ragionamento nel Log.

var state: GameState
var module: RDRModule
var np: RDRNonPlayer
var rounds: RDRRounds
var act: RDRActions
var rng: RandomNumberGenerator
var data: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_np: RDRNonPlayer, p_rounds: RDRRounds) -> void:
	np = p_np
	rounds = p_rounds
	state = p_np.state
	module = p_np.module
	rng = p_rounds.rng
	act = RDRActions.new(state, module)
	var path := RDRModule.DATA_DIR + "np_dust_storm.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	else:
		push_error("RDRNonPlayerRound: manca %s" % path)


func _log(text: String) -> void:
	log_lines.append(text)
	rounds.log_line(text)


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid


func _flush_act() -> void:
	for line in act.log_lines:
		log_lines.append(String(line))
	act.log_lines.clear()


# ---------------------------------------------------------------------------
# Victory Phase
# ---------------------------------------------------------------------------

## §8.5.9: «A human playing solitaire against three NP Factions may only win if
## it is the Final Dust Storm Round». Vale solo per il solitario vero: un umano
## contro tre bot. Con due giocatori al tavolo la partita finisce come sempre.
func victory_blocked(round_number: int) -> bool:
	if not bool(data.get("victory", {}).get("solitaire_only_final_round", false)):
		return false
	var humans := 0
	for fid in RDRModule.PLAYABLE_FACTIONS:
		if state.is_player(String(fid)):
			humans += 1
	if humans != 1 or Array(np.np_factions).size() != 3:
		return false
	if round_number >= 3:
		return false
	_log("Solitario contro tre bot: la vittoria si può cogliere solo all'ultimo Dust Storm Round.")
	return true


## §8.5.9: NP MG paga la Displaced Population in Supply Total invece che in
## Risorse — 1 ogni due marker, dove un giocatore ne perderebbe 3 di Risorse.
## Restituisce true se se n'è occupato lui.
func displaced_population_penalty(pairs: int) -> bool:
	if pairs <= 0 or not module.is_np(state, "marsgov"):
		return false
	var per: int = int(data.get("victory", {}).get("marsgov", {}).get("supply_total_per_2_displaced", -1))
	module.add_supply(state, per * pairs)
	_log("Displaced Population: Supply Total %d (%d marker in eccesso)." % [
		module.supply_total(state), pairs * 2])
	return true


# ---------------------------------------------------------------------------
# Support Phase
# ---------------------------------------------------------------------------

## §8.5.9: NP MG e NP RD risolvono la Support Phase da soli. Prima House in
## quanti più spazi possibile, poi Repair e spostamenti del Supporto fino a
## esaurire il budget — 2d6 per NP MG, l'Agitate Total per NP RD, che lo spende.
## NP CORP e NP CR nella Support Phase non fanno niente.
func support_phase() -> void:
	for faction in ["marsgov", "red_dust"]:
		if not module.is_np(state, faction):
			continue
		var cfg: Dictionary = data.get("support", {}).get(faction, {})
		if cfg.is_empty():
			continue
		_support_for(faction, cfg)


func _support_for(faction: String, cfg: Dictionary) -> void:
	# ❶ House in quanti più spazi si può. Il limite vero è la Displaced
	# Population: ogni House ne riporta giù un marker.
	var housed: Array[String] = []
	while int(state.tracks.get("displaced_population", 0)) > 0:
		# «In as many spaces as possible»: uno per spazio, non due volte nello
		# stesso — è il numero di spazi serviti a contare.
		var pool := _spaces_where(String(cfg.get("house_where", "")),
			func(sid): return act.can_house(sid) and not housed.has(sid))
		if pool.is_empty():
			break
		var pick := _pick(faction, String(cfg["house_column"]), pool)
		if pick == "" or not act.house(pick, faction):
			break
		housed.append(pick)
		_log("Support: House in %s (%s)." % [_name(pick), faction])
	_flush_act()

	# ❷ Repair e spostamenti, fino al budget. Prima i Repair, poi gli shift.
	var budget := _budget(faction, cfg)
	if budget <= 0:
		if housed.is_empty():
			_log("Support: NP %s non ha niente da fare." % faction)
		return
	_log("Support: NP %s ha %d fra Repair e spostamenti." % [faction, budget])
	var spent := 0

	while spent < budget:
		var pool := _spaces_where(String(cfg.get("repair_where", "")),
			func(sid): return _can_repair_np(sid, faction))
		if pool.is_empty():
			break
		var pick := _pick(faction, String(cfg["repair_column"]), pool)
		if pick == "" or not _repair_np(pick, faction):
			break
		spent += 1
		_log("Support: Repair in %s." % _name(pick))
	_flush_act()

	var step := int(cfg.get("shift_step", 1))
	while spent < budget:
		var pool := _spaces_where("", func(sid): return _can_shift(sid, step))
		if pool.is_empty():
			break
		var pick := _pick(faction, String(cfg["shift_column"]), pool)
		if pick == "":
			break
		var before: int = state.spaces[pick].support
		act.shift(pick, step)
		if state.spaces[pick].support == before:
			break   # la Campaign in gioco blocca quello spostamento: si smette
		spent += 1
		_log("Support: %s si sposta di un passo (%s)." % [_name(pick), faction])
	_flush_act()

	# ❸ La coda: NP MG alza la EG Confidence, NP RD paga l'Agitate Total.
	if String(cfg.get("after", "")) == "eg_confidence_up":
		act.set_eg("EG+")
		_flush_act()
		_log("Support: EG Confidence sale di un passo.")
	if String(cfg.get("spend", "")) == "agitate_total" and spent > 0:
		module.add_agitate(state, -spent)
		_log("Support: Agitate Total −%d (ora %d)." % [spent, module.agitate_total(state)])


func _budget(faction: String, cfg: Dictionary) -> int:
	match String(cfg.get("budget", "")):
		"2d6":
			var d1 := rng.randi_range(1, 6)
			var d2 := rng.randi_range(1, 6)
			_log("Support: NP %s tira 2d6 → %d + %d." % [faction, d1, d2])
			return d1 + d2
		"agitate_total":
			return module.agitate_total(state)
	return 0


## Repair e shift di una Fazione NP non costano Risorse (§8.5.4): `RDRActions`
## le chiederebbe, quindi il controllo e l'esecuzione passano di qui.
func _can_repair_np(sid: String, faction: String) -> bool:
	if module.marker(state, sid, "damage") <= 0:
		return false
	return int(state.tracks.get("displaced_population", 0)) > 0


func _repair_np(sid: String, faction: String) -> bool:
	if not _can_repair_np(sid, faction):
		return false
	module.add_marker(state, sid, "damage", -1)
	state.tracks["displaced_population"] = int(state.tracks.get("displaced_population", 0)) - 1
	module.add_marker(state, sid, "pop_markers", 1)
	act.set_eg("EG+" if faction == "marsgov" else "EG-")
	return true


func _can_shift(sid: String, step: int) -> bool:
	if module.population(state, sid) <= 0:
		return false
	var cur: int = state.spaces[sid].support
	if step > 0:
		return cur < CoinEnums.Support.ACTIVE_SUPPORT
	return cur > CoinEnums.Support.ACTIVE_OPPOSITION


## Gli spazi di Mars che soddisfano il vincolo della scheda e il test passato.
func _spaces_where(constraint: String, test: Callable) -> Array:
	var out: Array = []
	for sid in module.mars_spaces(state):
		var s := String(sid)
		var sup: int = state.spaces[s].support
		match constraint:
			"without_opposition":
				if sup < 0:
					continue
			"with_opposition", "at_opposition":
				if sup >= 0:
					continue
		if bool(test.call(s)):
			out.append(s)
	return out


func _pick(faction: String, column: String, pool: Array) -> String:
	if pool.size() == 1:
		return String(pool[0])
	return String(np.select_space(faction, column, pool).get("space", ""))


# ---------------------------------------------------------------------------
# Redeploy Phase
# ---------------------------------------------------------------------------

## §8.5.9: ogni Fazione NP ridispiega i propri pezzi seguendo le sue istruzioni
## numerate. Restituisce l'elenco delle Fazioni di cui si è occupato, così
## `RDRRounds` sa quali lasciare alla procedura dei giocatori.
func redeploy_phase() -> Array:
	var done: Array = []
	var cfg: Dictionary = data.get("redeploy", {})

	# Le Truppe EarthGov, se il Controller è un bot.
	var controller := module.eg_controller(state)
	if controller != "" and module.is_np(state, controller):
		var eg: Dictionary = cfg.get("eg_controller", {}).get(controller, {})
		if not eg.is_empty():
			_redeploy_eg(controller, eg)

	for faction in ["marsgov", "red_dust", "reclaimer"]:
		if not module.is_np(state, faction):
			continue
		var f: Dictionary = cfg.get(faction, {})
		if f.is_empty():
			continue
		_redeploy_faction(faction, f)
		done.append(faction)
	module.recompute_all_control(state)
	return done


func _redeploy_eg(controller: String, eg: Dictionary) -> void:
	# Prima tutte giù da Mars: è la regola base, il Controller decide solo dove.
	var pool := 0
	for sid in module.mars_spaces(state):
		pool += module.count_in(state, String(sid), "eg_troop")
	match String(eg.get("rule", "")):
		"all_eg_to_phobos":
			for sid in module.mars_spaces(state):
				var n := module.count_in(state, String(sid), "eg_troop")
				if n > 0:
					module.move_pieces(state, String(sid), "phobos", "eg_troop", n)
			if pool > 0:
				_log("Redeploy: NP CORP porta tutte le %d Truppe EG su Phobos." % pool)
		"eg_to_mg_bases_then_phobos":
			var per := int(eg.get("per_base", 4))
			var bases: Array = []
			for sid in module.mars_spaces(state):
				if module.count_in(state, String(sid), "mg_base") > 0:
					bases.append(String(sid))
			# Le Truppe EG passano tutte da Phobos e da lì tornano sulle Basi:
			# così l'ordine delle Basi lo detta la tabella, non la mappa.
			for sid in module.mars_spaces(state):
				var n := module.count_in(state, String(sid), "eg_troop")
				if n > 0:
					module.move_pieces(state, String(sid), "phobos", "eg_troop", n)
			var placed := 0
			while not bases.is_empty():
				var pick := _pick("marsgov", String(eg.get("column", "place_cubes")), bases)
				if pick == "":
					pick = String(bases[0])
				bases.erase(pick)
				var want: int = per - module.count_in(state, pick, "eg_troop")
				var have := module.count_in(state, "phobos", "eg_troop")
				var take: int = mini(maxi(0, want), have)
				if take > 0:
					module.move_pieces(state, "phobos", pick, "eg_troop", take)
					placed += take
			if pool > 0:
				_log("Redeploy: NP MG porta %d Truppe EG sulle Basi MG, il resto su Phobos." % placed)


func _redeploy_faction(faction: String, f: Dictionary) -> void:
	var types: Array = f.get("moves", [])
	if types.is_empty():
		return
	var column := String(f.get("column", ""))

	# Le istruzioni numerate, in ordine. Ognuna dice quanti pezzi servono in
	# quali spazi (`get`) oppure svuota uno spazio che non si può tenere.
	for entry in f.get("get", []):
		var g: Dictionary = entry
		if g.has("only_if_player") and not np.is_player(String(g["only_if_player"])):
			continue
		if g.has("when") and not _redeploy_condition(String(g["when"]), faction):
			continue
		match String(g.get("rule", "")):
			"cr_base_to_wilderness":
				_cr_bases_to_wilderness()
			"evacuate":
				_evacuate(faction, types, String(g.get("where", "")), column, g)
			_:
				_fill(faction, types, column, f, g)


## Quanti pezzi servono in `sid` per soddisfare l'istruzione.
func _need_in(faction: String, sid: String, types: Array, g: Dictionary) -> int:
	var have := _count(sid, types)
	match String(g.get("rule", "")):
		"count":
			return maxi(0, int(g.get("count", 0)) - have)
		"coin_gt_rebels":
			var st: SpaceState = state.spaces[sid]
			return maxi(0, module.rebel_forces(state, st) + 1 - module.coin_forces(state, st))
		"mg_gt_corp":
			var corp := module.count_in(state, sid, "security") \
				+ module.count_in(state, sid, "specops") + module.count_in(state, sid, "corp_base")
			return maxi(0, corp + 1 - module.count_in(state, sid, "mg_troop"))
	return 0


## Gli spazi bersaglio di un'istruzione.
func _targets(faction: String, where: String) -> Array:
	var out: Array = []
	for sid in module.mars_spaces(state):
		var s := String(sid)
		var st: SpaceState = state.spaces[s]
		var base := _own_base(faction)
		var okk := false
		match where:
			"labyrinth_or_desert_with_mg_base":
				okk = module.is_labyrinth(state, s) \
					or (module.is_desert(state, s) and module.count_in(state, s, "mg_base") > 0)
			"desert_with_mg_base":
				okk = module.is_desert(state, s) and module.count_in(state, s, "mg_base") > 0
			"at_support_with_corp_base":
				okk = st.support > 0 and module.count_in(state, s, "corp_base") > 0
			"desert_without_coin_base":
				okk = module.is_desert(state, s) \
					and module.count_in(state, s, "mg_base") + module.count_in(state, s, "corp_base") == 0
			"desert_without_opposition_or_own_base":
				okk = module.is_desert(state, s) and st.support >= 0 \
					and module.count_in(state, s, base) == 0
			"with_own_base":
				okk = module.count_in(state, s, base) > 0
			"room_for_own_base":
				okk = act.can_place_base(s) and module.available(state, base) > 0
		if okk:
			out.append(s)
	return out


## Porta pezzi in ogni spazio bersaglio finché l'istruzione è soddisfatta o
## finché non c'è più niente da muovere.
func _fill(faction: String, types: Array, column: String, f: Dictionary, g: Dictionary) -> void:
	var pool := _targets(faction, String(g.get("where", "")))
	if pool.is_empty():
		return
	var moved := 0
	while not pool.is_empty():
		var dest := _pick(faction, column, pool)
		if dest == "":
			dest = String(pool[0])
		pool.erase(dest)
		var need := _need_in(faction, dest, types, g)
		while need > 0:
			var origin := _choose_origin(faction, types, f, dest)
			if origin == "":
				break
			var t := _first_type(origin, types)
			if t == "":
				break
			if module.move_pieces(state, origin, dest, t, 1) == 0:
				break
			moved += 1
			need -= 1
	if moved > 0:
		_log("Redeploy %s, istruzione %d: %d pezzi spostati." % [
			faction, int(g.get("n", 0)), moved])


## Svuota gli spazi che l'istruzione dice di abbandonare, mandando i pezzi dove
## le priorità li vogliono. Senza destinazione i Ribelli tornano fra i
## disponibili, come prescrive §4.3.
func _evacuate(faction: String, types: Array, where: String, column: String,
		g: Dictionary) -> void:
	var origins := _targets(faction, where)
	if origins.is_empty():
		return
	var dests: Array = []
	for sid in module.mars_spaces(state):
		if not origins.has(String(sid)):
			dests.append(String(sid))
	var moved := 0
	var removed := 0
	for origin in origins:
		for t in types:
			var n := module.count_in(state, String(origin), String(t))
			while n > 0:
				var dest := _pick(faction, column, dests) if not dests.is_empty() else ""
				if dest == "":
					module.remove_pieces(state, String(origin), String(t), n, "available")
					removed += n
					break
				module.move_pieces(state, String(origin), dest, String(t), 1)
				moved += 1
				n -= 1
	if moved > 0 or removed > 0:
		_log("Redeploy %s, istruzione %d: %d pezzi evacuati, %d rimessi fra i disponibili." % [
			faction, int(g.get("n", 0)), moved, removed])


## L'origine da cui prendere il prossimo pezzo, secondo l'ordine della scheda e
## nel rispetto delle regole «keep».
func _choose_origin(faction: String, types: Array, f: Dictionary, dest: String) -> String:
	var best := ""
	var best_rank := -1
	var best_free := 0
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if s == dest:
			continue
		var free := _count(s, types) - _keep_in(faction, s, types, f)
		if free <= 0:
			continue
		var rank := _origin_rank(faction, s, f)
		if rank > best_rank or (rank == best_rank and free > best_free):
			best = s
			best_rank = rank
			best_free = free
	return best


## Quanto è "prima" questa origine nell'ordine della scheda: le prime voci
## valgono di più, e a parità decide chi ha più pezzi da muovere.
func _origin_rank(faction: String, sid: String, f: Dictionary) -> int:
	var rules: Array = f.get("origin_order", [])
	for i in range(rules.size()):
		var r: Dictionary = rules[i]
		match String(r.get("rule", "")):
			"desert_without_coin_base":
				if module.is_desert(state, sid) \
						and module.count_in(state, sid, "mg_base") \
							+ module.count_in(state, sid, "corp_base") == 0:
					return rules.size() - i
			"desert_without_opposition_or_own_base":
				if module.is_desert(state, sid) and state.spaces[sid].support >= 0 \
						and module.count_in(state, sid, _own_base(faction)) == 0:
					return rules.size() - i
			"most_moving_pieces":
				return 0
	return 0


## Quanti pezzi devono restare in `sid` secondo le regole «keep» della scheda.
func _keep_in(faction: String, sid: String, types: Array, f: Dictionary) -> int:
	var have := _count(sid, types)
	var keep := 0
	for entry in f.get("keep", []):
		var r: Dictionary = entry
		if r.has("when") and not _keep_condition(String(r["when"]), sid):
			continue
		var want := 0
		match String(r.get("rule", "")):
			"keep_mg_gt_corp":
				want = module.count_in(state, sid, "security") \
					+ module.count_in(state, sid, "specops") \
					+ module.count_in(state, sid, "corp_base") + 1
			"keep_3_cubes":
				want = 3
			"keep_3_rebels_with_base_room":
				want = 3 if (act.can_place_base(sid)
					and module.available(state, _own_base(faction)) > 0) else 0
			"keep_1_rebel":
				want = 1
			"keep_no_control_change":
				want = _forces_to_hold_control(faction, sid, types)
		# «Keep»: se i pezzi non bastano l'istruzione si ignora (§Glossario).
		if want <= 0 or want > have:
			continue
		keep = maxi(keep, want)
	return keep


func _keep_condition(cond: String, sid: String) -> bool:
	var st: SpaceState = state.spaces[sid]
	match cond:
		"populated_at_support_with_corp_base":
			return module.population(state, sid) > 0 and st.support > 0 \
				and module.count_in(state, sid, "corp_base") > 0
		"at_support":
			return st.support > 0
		"populated_without_active_opposition":
			return module.population(state, sid) > 0 \
				and st.support != CoinEnums.Support.ACTIVE_OPPOSITION
	return true


func _redeploy_condition(cond: String, faction: String) -> bool:
	match cond:
		"no_enemy_forces_in_wilderness":
			var st: SpaceState = state.spaces["wilderness"]
			return module.coin_forces(state, st) == 0 \
				and module.control_forces(state, st, "red_dust") == 0
	return true


## §8.5.9 ❶ dei Reclaimer: una Base CR va nella Wilderness da ogni altro spazio
## che ne ha due, se là non ci sono forze nemiche.
func _cr_bases_to_wilderness() -> void:
	var moved := 0
	for sid in module.mars_spaces(state):
		var s := String(sid)
		if s == "wilderness":
			continue
		if module.count_in(state, s, "cr_base") < 2:
			continue
		if module.move_pieces(state, s, "wilderness", "cr_base", 1) > 0:
			moved += 1
	if moved > 0:
		_log("Redeploy Reclaimer, istruzione 1: %d Basi portate nella Wilderness." % moved)


func _forces_to_hold_control(faction: String, sid: String, types: Array) -> int:
	var current: String = state.spaces[sid].control
	var mine := _count(sid, types)
	for stay in range(0, mine + 1):
		if _control_with(faction, sid, mine - stay) == current:
			return stay
	return mine


func _control_with(faction: String, sid: String, gone: int) -> String:
	var st: SpaceState = state.spaces[sid]
	var coin := module.coin_forces(state, st)
	var rd := module.control_forces(state, st, "red_dust")
	var cr := module.control_forces(state, st, "reclaimer")
	match faction:
		"marsgov", "corporations": coin -= gone
		"red_dust": rd -= gone
		"reclaimer": cr -= gone
	if coin > rd + cr:
		return "coin"
	if rd > coin + cr:
		return "red_dust"
	if cr > coin + rd:
		return "reclaimer"
	return ""


func _count(sid: String, types: Array) -> int:
	var n := 0
	for t in types:
		n += module.count_in(state, sid, String(t))
	return n


func _first_type(sid: String, types: Array) -> String:
	for t in types:
		if module.count_in(state, sid, String(t)) > 0:
			return String(t)
	return ""


func _own_base(faction: String) -> String:
	match faction:
		"marsgov": return "mg_base"
		"corporations": return "corp_base"
		"red_dust": return "rd_base"
		"reclaimer": return "cr_base"
	return ""


# ---------------------------------------------------------------------------
# Reset Phase
# ---------------------------------------------------------------------------

## §8.5.9: si rimescola il mazzo Curiosity, e se l'Agitate Total di NP RD è a
## zero torna a 1d3 — altrimenti NP RD resterebbe senza mezzi per sempre.
func reset_phase() -> void:
	var cfg: Dictionary = data.get("reset", {})
	if bool(cfg.get("shuffle_curiosity", false)):
		for fid in np.np_factions:
			np.shuffle_deck(String(fid))
		_log("Reset: mazzo Curiosity rimescolato.")
	if module.is_np(state, "red_dust") and module.agitate_total(state) == 0:
		var value := rng.randi_range(1, 3)
		state.tracks["agitate_total"] = value
		_log("Reset: Agitate Total di NP RD azzerato, torna a %d (1d3)." % value)
