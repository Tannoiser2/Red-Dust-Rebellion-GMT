class_name RDRNonPlayer
extends RefCounted

## Sistema Non-Player *Curiosity* (§8.0), di Joe Dewhurst.
##
## Questo è il MOTORE: i contatori surrogati delle Fazioni NP, la procedura di
## Eligibility, gli Activation Number e — soprattutto — il selettore di spazi
## guidato dalle Space Selection Priorities (§8.5.6), che è il cuore del sistema.
##
## Quello che NON c'è ancora, perché sono componenti del gioco fisico non
## riprodotti nel libretto:
##   * le 24 carte *Curiosity* (6 per Fazione, bifacciali), che scelgono quale
##     Operazione e quale Attività Speciale eseguire;
##   * la tabella Space Selection Priorities di NP MarsGov;
##   * le tabelle Move Priorities, Piece Priorities, Eligibility, Effective
##     Events, Event Instructions e Capability & Campaign Effects.
## Finché non ci sono, `has_table()` dice cosa manca e il chiamante lo sa.
##
## §8.2: le Fazioni NP seguono le regole normali salvo poche eccezioni. Le due
## che riguardano questo file: NP MG e NP RD non tracciano Risorse (usano il
## Supply Total e l'Agitate Total), e NP CR non tiene una mano di Asset card ma
## un Asset Total sull'edge track.

const DATA_FILE := "np_priorities.json"

## §8.4.1: valori iniziali dei contatori surrogati.
const START_SUPPLY := 0
const START_ASSET := 3
## L'Asset Total non supera mai 6 (§ glossario: "may never increase beyond six").
const ASSET_MAX := 6

var state: GameState
var module: RDRModule
var rng: RandomNumberGenerator
## Fazioni gestite dal sistema NP (le altre sono dei giocatori).
var np_factions: PackedStringArray = PackedStringArray()
var tables: Dictionary = {}
var missing: Array = []
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule,
		p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	module = p_module
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	var path := RDRModule.DATA_DIR + DATA_FILE
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			tables = parsed.get("tables", {})
			missing = parsed.get("missing", [])


## C'è la tabella delle priorità per questa Fazione NP?
func has_table(faction: String) -> bool:
	return tables.has(faction)


func is_np(faction: String) -> bool:
	return Array(np_factions).has(faction)


## Una Fazione è "di un giocatore" (per le righe con la spunta rossa) se NON è
## gestita dal sistema NP.
func is_player(faction: String) -> bool:
	return not is_np(faction)


# ---------------------------------------------------------------------------
# §8.4.1 Contatori surrogati
# ---------------------------------------------------------------------------

func setup(p_np_factions: Array) -> void:
	np_factions = PackedStringArray(p_np_factions)
	state.tracks["np_factions"] = Array(np_factions)
	if is_np("marsgov"):
		state.tracks["supply_total"] = START_SUPPLY
	if is_np("red_dust"):
		# §8.4.1: l'Agitate Total parte a 1d3.
		state.tracks["agitate_total"] = rng.randi_range(1, 3)
	if is_np("reclaimer"):
		state.tracks["asset_total"] = START_ASSET
	log_lines.append("Non-Player: %s." % ", ".join(np_factions))


func supply_total() -> int:
	return int(state.tracks.get("supply_total", 0))


func agitate_total() -> int:
	return int(state.tracks.get("agitate_total", 0))


func asset_total() -> int:
	return int(state.tracks.get("asset_total", 0))


func add_supply(delta: int) -> void:
	state.tracks["supply_total"] = maxi(0, supply_total() + delta)


func add_agitate(delta: int) -> void:
	state.tracks["agitate_total"] = maxi(0, agitate_total() + delta)


## §8.2: qualunque effetto che farebbe pescare o scartare Asset card ai Reclaimer
## NP muove invece l'Asset Total, che non passa mai 6.
func add_asset(delta: int) -> void:
	state.tracks["asset_total"] = clampi(asset_total() + delta, 0, ASSET_MAX)


# ---------------------------------------------------------------------------
# §8.5.2 Eligibility dei Reclaimer NP
# ---------------------------------------------------------------------------

## §4.1: i Reclaimer scartano carte per anticipare il turno; da NP "scartano"
## riducendo l'Asset Total. Si tirano 3d6 e si contano i dadi ≤ Asset Total:
## se bastano a coprire gli scarti richiesti, i Reclaimer avanzano.
## `cost_first` e `cost_second` sono gli scarti necessari per diventare 1ª o 2ª
## Disponibile (li calcola RDRSequence.reclaimer_cost_to_reach).
## Restituisce {rank: 0 (niente) | 1 | 2, spent: int, dice: [d1,d2,d3]}.
func reclaimer_eligibility_check(cost_first: int, cost_second: int) -> Dictionary:
	var out := {"rank": 0, "spent": 0, "dice": []}
	if not is_np("reclaimer"):
		return out
	var total := asset_total()
	var dice: Array = []
	var hits := 0
	for i in range(3):
		var d := rng.randi_range(1, 6)
		dice.append(d)
		if d <= total:
			hits += 1
	out["dice"] = dice
	if cost_first > 0 and hits >= cost_first and total >= cost_first:
		add_asset(-cost_first)
		out["rank"] = 1
		out["spent"] = cost_first
	elif cost_second > 0 and hits >= cost_second and total >= cost_second:
		add_asset(-cost_second)
		out["rank"] = 2
		out["spent"] = cost_second
	if out["rank"] > 0:
		log_lines.append("NP CR spende %d di Asset Total per essere %dª Disponibile." % [
			out["spent"], out["rank"]])
	return out


# ---------------------------------------------------------------------------
# §8.5.4 Activation Number
# ---------------------------------------------------------------------------

## Tira 1d6 dopo aver eseguito l'Operazione in uno spazio: se il risultato è
## maggiore dell'Activation Number si può scegliere un altro spazio.
## §8.5.4: NP MG e NP CR trattano come riuscito anche un tiro fallito, se il dado
## è ≤ al proprio contatore, spendendone uno (Supply Total / Asset Total): è il
## modo in cui il sistema simula le Risorse che non traccia.
## Restituisce {ok, die, spent}.
func activation_check(faction: String, activation_number: int,
		limited: bool = false) -> Dictionary:
	var die := rng.randi_range(1, 6)
	var out := {"ok": die > activation_number, "die": die, "spent": false}
	if out["ok"]:
		return out
	match faction:
		"marsgov":
			if die <= supply_total():
				add_supply(-1)
				out["ok"] = true
				out["spent"] = true
		"reclaimer":
			# Solo fuori dalle Operazioni Limitate (§8.5.4).
			if not limited and die <= asset_total():
				add_asset(-1)
				out["ok"] = true
				out["spent"] = true
	if out["spent"]:
		log_lines.append("NP %s: tiro %d fallito ma convertito spendendo un contatore." % [
			faction, die])
	return out


## §8.5.4: le Operazioni Limitate di NP CR si fermano comunque al quinto spazio.
func limited_space_cap(faction: String) -> int:
	return 5 if faction == "reclaimer" else 1


# ---------------------------------------------------------------------------
# §8.5.6 Space Selection Priorities
# ---------------------------------------------------------------------------

## Sceglie UNO spazio fra i candidati usando la colonna indicata della tabella
## della Fazione. Restituisce {space, row, trace} — `trace` elenca le righe
## applicate, così il Log può spiegare la scelta invece di limitarsi a farla.
func select_space(faction: String, column: String, candidates: Array) -> Dictionary:
	var pool: Array = []
	for sid in candidates:
		pool.append(String(sid))
	var trace: Array[String] = []
	if pool.is_empty():
		return {"space": "", "row": "", "trace": trace}
	if pool.size() == 1:
		return {"space": String(pool[0]), "row": "unico candidato", "trace": trace}
	if not has_table(faction):
		# Senza tabella non si inventa una priorità: si sceglie a caso e lo si dice.
		trace.append("tabella NP %s mancante: scelta casuale" % faction)
		return {"space": String(pool[rng.randi_range(0, pool.size() - 1)]),
			"row": "casuale (tabella mancante)", "trace": trace}

	for r in tables[faction].get("rows", []):
		var rule: Dictionary = r
		if not Array(rule.get("columns", [])).has(column):
			continue
		# Riga con la spunta rossa: vale solo se quella Fazione è di un giocatore.
		if rule.has("only_if_player") and not is_player(String(rule["only_if_player"])):
			continue
		var kept := _apply_row(rule.get("test", {}), pool, faction)
		if kept.is_empty():
			continue  # nessuno spazio soddisfa: si salta la riga
		trace.append("%s → %d spazi" % [rule.get("label", "?"), kept.size()])
		pool = kept
		if pool.size() == 1:
			return {"space": String(pool[0]), "row": String(rule.get("label", "")),
				"trace": trace}
	# Esaurite le righe si sceglie a caso fra quelli rimasti (§8.2 "When in Doubt").
	return {"space": String(pool[rng.randi_range(0, pool.size() - 1)]),
		"row": "a pari merito: scelta casuale", "trace": trace}


## Sceglie fino a `count` spazi, uno alla volta, come prescrive §8.5.6 punto 4.
func select_spaces(faction: String, column: String, candidates: Array,
		count: int) -> Array:
	var pool: Array = []
	for sid in candidates:
		pool.append(String(sid))
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		var pick := select_space(faction, column, pool)
		var sid := String(pick["space"])
		if sid == "":
			break
		out.append(sid)
		pool.erase(sid)
	return out


## Applica una riga della tabella al gruppo di spazi ancora in gioco.
func _apply_row(test: Dictionary, pool: Array, faction: String) -> Array:
	match String(test.get("kind", "")):
		"flag":
			var kept: Array = []
			for sid in pool:
				if _predicate(String(sid), test, faction):
					kept.append(sid)
			return kept
		"max", "min":
			var best := 0
			var kept2: Array = []
			var first := true
			for sid in pool:
				var v := _metric(String(sid), test, faction)
				if first or (String(test["kind"]) == "max" and v > best) \
						or (String(test["kind"]) == "min" and v < best):
					best = v
					kept2 = [sid]
					first = false
				elif v == best:
					kept2.append(sid)
			# Una riga "most/fewest" che non discrimina non serve a nulla: se tutti
			# sono a pari merito si passa alla successiva.
			return [] if kept2.size() == pool.size() else kept2
		"random":
			return [pool[rng.randi_range(0, pool.size() - 1)]]
	return []


# ---------------------------------------------------------------------------
# Predicati e metriche delle righe
# ---------------------------------------------------------------------------

const REBEL_FORCES := ["rd_rebel", "cr_rebel", "rd_base", "cr_base"]
const COIN_UNITS := ["mg_troop", "security", "specops", "eg_troop", "satellite"]
const COIN_FORCES := ["mg_troop", "security", "specops", "eg_troop", "satellite",
	"mg_base", "corp_base"]


func _count(sid: String, types: Array, piece_state = null) -> int:
	var n := 0
	for t in types:
		n += module.count_in(state, sid, String(t), piece_state)
	return n


func _rebel_of(faction: String) -> String:
	return "cr_rebel" if faction == "reclaimer" else "rd_rebel"


func _base_of(faction: String) -> String:
	match faction:
		"reclaimer": return "cr_base"
		"red_dust": return "rd_base"
		"corporations": return "corp_base"
	return "mg_base"


## Forze nemiche per una Fazione NP: tutto ciò che non è suo.
func _enemy_types(faction: String) -> Array:
	var out: Array = []
	for t in RDRModule.PIECE_OWNER.keys():
		if String(RDRModule.PIECE_OWNER[t]) != faction:
			out.append(String(t))
	return out


func _predicate(sid: String, test: Dictionary, faction: String) -> bool:
	var st: SpaceState = state.spaces[sid]
	match String(test.get("pred", "")):
		"base_without_hidden_rebel":
			var f := String(test.get("faction", faction))
			return module.count_in(state, sid, _base_of(f)) > 0 \
				and module.count_in(state, sid, _rebel_of(f), "hidden") == 0
		"support_not":
			return st.support != _support_level(String(test.get("level", "neutral")))
		"support_is":
			return st.support == _support_level(String(test.get("level", "neutral")))
		"base_or_control":
			var f2 := String(test.get("faction", faction))
			return module.count_in(state, sid, _base_of(f2)) > 0 or st.control == f2
		"no_control":
			return st.control != String(test.get("faction", faction))
		"terrain":
			return (module.is_desert(state, sid) if String(test.get("value", "")) == "desert"
				else module.is_labyrinth(state, sid))
		"storm_is":
			return module.storm(state, sid) == int(test.get("value", 0))
		"vulnerable_enemy_base":
			return _vulnerable_enemy_base(sid, String(test.get("faction", faction)))
		"rebels_and_base_room":
			var f3 := String(test.get("faction", faction))
			var n := module.count_in(state, sid, _rebel_of(f3))
			return n >= int(test.get("min", 1)) and n <= int(test.get("max", 2)) \
				and module.available(state, _base_of(f3)) > 0 \
				and _has_base_room(sid)
		"rebel_at_base":
			var f4 := String(test.get("faction", faction))
			return module.count_in(state, sid, _base_of(f4)) > 0 \
				and _count(sid, ["rd_rebel", "cr_rebel"]) > 0
		"base_with_few_cubes":
			var f5 := String(test.get("faction", faction))
			return module.count_in(state, sid, _base_of(f5)) > 0 \
				and _count(sid, ["mg_troop", "security", "eg_troop"]) <= int(test.get("max", 3))
		"coin_units_below_rebels_with_corp":
			return _count(sid, ["security", "specops", "corp_base"]) > 0 \
				and _count(sid, COIN_UNITS) < _count(sid, REBEL_FORCES)
		"labyrinth_corp_over_mg":
			return module.is_labyrinth(state, sid) \
				and _count(sid, ["security", "specops"]) > module.count_in(state, sid, "mg_troop")
		"has_conversion_center":
			return module.count_in(state, sid, "cr_base", "conversion_center") > 0
		"rebel_base_present":
			return _count(sid, ["rd_base", "cr_base"]) > 0
	return false


## Glossario: una Base è vulnerabile se nel suo spazio ci sono meno di quattro
## unità amiche (non-Base). Le unità MG e CORP sono amiche fra loro.
func _vulnerable_enemy_base(sid: String, faction: String) -> bool:
	for base_id in ["mg_base", "corp_base", "rd_base", "cr_base"]:
		if String(RDRModule.PIECE_OWNER[base_id]) == faction:
			continue
		if module.count_in(state, sid, base_id) == 0:
			continue
		var guards := 0
		match base_id:
			"mg_base", "corp_base":
				guards = _count(sid, ["mg_troop", "security", "specops", "eg_troop"])
			"rd_base":
				guards = module.count_in(state, sid, "rd_rebel")
			"cr_base":
				guards = module.count_in(state, sid, "cr_rebel")
		if guards < 4:
			return true
	return false


func _has_base_room(sid: String) -> bool:
	var act := RDRActions.new(state, module)
	return act.can_place_base(sid)


func _support_level(name: String) -> int:
	return RDRModule.SUPPORT_KEY_MAP.get(name, CoinEnums.Support.NEUTRAL)


## Metriche delle righe "most/fewest". Il glossario è preciso su Support e
## Opposition: contano il TOTALE (livello × Popolazione), e gli spazi senza
## Supporto valgono zero.
func _metric(sid: String, test: Dictionary, faction: String) -> int:
	var st: SpaceState = state.spaces[sid]
	match String(test.get("metric", "")):
		"population":
			return module.population(state, sid)
		"damage":
			return module.marker(state, sid, "damage")
		"support":
			return st.support * module.population(state, sid) if st.support > 0 else 0
		"opposition":
			return -st.support * module.population(state, sid) if st.support < 0 else 0
		"pieces":
			return _count(sid, test.get("types", []))
		"enemy_forces":
			return _count(sid, _enemy_types(String(test.get("faction", faction))))
		"rebel_forces":
			return _count(sid, REBEL_FORCES)
	return 0
