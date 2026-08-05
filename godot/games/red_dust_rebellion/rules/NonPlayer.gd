class_name RDRNonPlayer
extends RefCounted

## Sistema Non-Player *Curiosity* (§8.0), di Joe Dewhurst.
##
## Questo è il MOTORE: i contatori surrogati delle Fazioni NP, la procedura di
## Eligibility, gli Activation Number e — soprattutto — il selettore di spazi
## guidato dalle Space Selection Priorities (§8.5.6), che è il cuore del sistema.
##
## Le tabelle del gioco fisico sono trascritte tutte: le quattro Space Selection
## Priorities, Move Priorities, Piece Priorities, Eligibility, Effective Events,
## e le 48 facce delle carte *Curiosity*.
##
## Resta fuori una cosa sola, e non è una tabella: i simboli ★ (Critical) e ⊘
## (Not Performed) stampati sotto le icone delle Fazioni sulle 51 carte Evento.
## Senza di quelli `current_critical` resta falso e la tabella di Eligibility
## cade sull'ultima riga — che è dichiarato da `degraded`.
##
## §8.2: le Fazioni NP seguono le regole normali salvo poche eccezioni. Le due
## che riguardano questo file: NP MG e NP RD non tracciano Risorse (usano il
## Supply Total e l'Agitate Total), e NP CR non tiene una mano di Asset card ma
## un Asset Total sull'edge track.

const DATA_FILE := "np_priorities.json"
const PIECE_FILE := "np_piece_priorities.json"
const MOVE_FILE := "np_move_priorities.json"
const ELIGIBILITY_FILE := "np_eligibility.json"

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
## §8.5.8 Piece Priorities e §8.5.7 Move Priorities, dalle schede del gioco.
var piece_priorities: Dictionary = {}
var move_priorities: Dictionary = {}
var eligibility_table: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule,
		p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	module = p_module
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	var parsed = _load(DATA_FILE)
	tables = parsed.get("tables", {})
	missing = parsed.get("missing", [])
	piece_priorities = _load(PIECE_FILE)
	move_priorities = _load(MOVE_FILE)
	eligibility_table = _load(ELIGIBILITY_FILE)


func _load(file_name: String) -> Dictionary:
	var path := RDRModule.DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


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
# §8.5.3 Mazzo delle carte Curiosity
# ---------------------------------------------------------------------------

## Un mazzo per Fazione NP: sei carte, che si pescano a rotazione. §8.9: «è
## possibile ciclare tutto il mazzo prima di un rimescolamento, quindi si può
## finire per pescare la stessa carta più volte».
func setup_deck(faction: String, card_ids: Array) -> void:
	var deck: Array = card_ids.duplicate()
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	_decks()[faction] = deck


func _decks() -> Dictionary:
	if not state.tracks.has("curiosity_decks"):
		state.tracks["curiosity_decks"] = {}
	return state.tracks["curiosity_decks"]


## Pesca la prossima carta della Fazione; il mazzo si richiude a ciclo continuo.
func draw_card(faction: String) -> String:
	var decks := _decks()
	var deck: Array = decks.get(faction, [])
	if deck.is_empty():
		return ""
	var card = deck.pop_front()
	deck.append(card)   # va in fondo: il mazzo gira
	return String(card)


## §4.3 Reset: il mazzo Curiosity si rimescola.
func shuffle_deck(faction: String) -> void:
	var deck: Array = _decks().get(faction, [])
	setup_deck(faction, deck)


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
# §8.5.5 Effective Events
# ---------------------------------------------------------------------------

## Cosa «aggiunge o aumenta» e cosa «rimuove o riduce» rende un Evento efficace
## per ciascuna Fazione NP (tabella Effective Events della scheda del gioco).
const EFFECTIVE := {
	"marsgov": {
		"adds": ["support", "population_at_support", "own_forces", "eg_up", "supply"],
		"removes": ["enemy_forces", "profits", "opposition", "population_at_opposition",
			"asset_cards", "player_resources"],
	},
	"corporations": {
		"adds": ["profits", "own_forces", "eg_up", "terraforming_bases"],
		"removes": ["enemy_forces", "eg_down", "asset_cards", "player_resources"],
	},
	"red_dust": {
		"adds": ["opposition", "population_at_opposition", "agitate_total", "own_forces",
			"hidden_rebels"],
		"removes": ["enemy_forces", "support", "profits", "eg_down",
			"population_at_support", "asset_cards", "supply", "player_resources"],
	},
	"reclaimer": {
		"adds": ["asset_total", "own_forces", "conversion_centers", "hidden_rebels"],
		"removes": ["profits", "enemy_forces", "support", "opposition", "population",
			"eg_down", "supply", "player_resources"],
	},
}


## §8.5.5: un Evento è efficace per una Fazione NP se almeno uno dei suoi effetti
## compare nella riga di quella Fazione.
##
## Qui gli effetti non si indovinano dal testo: si leggono da `event_effects.json`,
## che li ha già scomposti in operazioni atomiche. Ogni operazione viene tradotta
## nella categoria corrispondente della tabella e confrontata con la riga.
## Restituisce {effective, matched} — `matched` dice quali categorie hanno preso.
func event_effective(faction: String, effects: Array) -> Dictionary:
	var row: Dictionary = EFFECTIVE.get(faction, {})
	var got := _categories(faction, effects)
	var matched: Array[String] = []
	for key in got["adds"]:
		if Array(row.get("adds", [])).has(String(key)) and not matched.has(String(key)):
			matched.append(String(key))
	for key2 in got["removes"]:
		if Array(row.get("removes", [])).has(String(key2)) and not matched.has(String(key2)):
			matched.append(String(key2))
	return {"effective": not matched.is_empty(), "matched": matched}


## Traduce le operazioni di un Evento nelle categorie della tabella, SEPARANDO
## ciò che aggiunge da ciò che toglie: la stessa grandezza sta in colonne diverse
## per Fazioni diverse — le Corporations vogliono i Profits che salgono, il Red
## Dust quelli che scendono, e confonderli renderebbe ogni Evento efficace per
## tutti.
func _categories(faction: String, effects: Array) -> Dictionary:
	var adds: Array[String] = []
	var removes: Array[String] = []
	for entry in effects:
		var e: Dictionary = entry
		var delta := int(e.get("delta", e.get("delta_per", 0)))
		match String(e.get("op", "")):
			"profits":
				(adds if delta > 0 else removes).append("profits")
			"resources":
				# «Player Resources»: conta solo se quella Fazione è di un giocatore.
				var who := String(e.get("faction", ""))
				if delta < 0 and who != faction and is_player(who):
					removes.append("player_resources")
			"eg_side":
				if String(e.get("side", "EG+")) == "EG+":
					adds.append("eg_up")
				else:
					removes.append("eg_down")
			"eg_confidence":
				if delta > 0:
					adds.append("eg_up")
				else:
					removes.append("eg_down")
			"supply_earth":
				(adds if delta > 0 else removes).append("supply")
			"clear_supply":
				removes.append("supply")
			"population_earth", "house":
				adds.append("population")
			"damage", "displaced_clear":
				removes.append("population")
			"displaced":
				(adds if delta > 0 else removes).append("population")
			"repair":
				adds.append("population")
			"shift":
				# Spostare verso il Supporto AGGIUNGE Supporto e TOGLIE Opposizione.
				var levels := int(e.get("levels", 1))
				if String(e.get("toward", "")) == "neutral":
					removes.append("support")
					removes.append("opposition")
				elif levels > 0:
					adds.append("support")
					adds.append("population_at_support")
					removes.append("opposition")
					removes.append("population_at_opposition")
				else:
					adds.append("opposition")
					adds.append("population_at_opposition")
					removes.append("support")
					removes.append("population_at_support")
			"set_support":
				removes.append("support")
				removes.append("opposition")
			"place", "replace":
				adds.append_array(_piece_categories(faction, e))
			"remove":
				removes.append("enemy_forces")
			"hide":
				adds.append("hidden_rebels")
			"flip":
				match String(e.get("to_state", "")):
					"terraforming": adds.append("terraforming_bases")
					"conversion_center": adds.append("conversion_centers")
			"draw_asset":
				adds.append("asset_total")
			"discard_asset":
				removes.append("asset_cards")
			"free_op":
				# «An X Operation or Special Activity»: vale se tocca alla Fazione.
				# Il campo può essere una scelta ({"choice": …}): allora è di chi
				# esegue, quindi buono per chiunque stia agendo.
				var who2 = e.get("faction", "executing")
				if typeof(who2) != TYPE_STRING or String(who2) in [faction, "executing"]:
					adds.append("own_forces")
	return {"adds": adds, "removes": removes}


func _piece_categories(faction: String, e: Dictionary) -> Array:
	var out: Array[String] = []
	for spec in e.get("pieces", [e]):
		var type_id := String((spec as Dictionary).get("type", ""))
		if type_id.begins_with("@"):
			out.append("own_forces")
			continue
		var owner: String = RDRModule.PIECE_OWNER.get(type_id, "")
		if owner == faction or (faction in RDRModule.COIN_FACTIONS
				and owner in RDRModule.COIN_FACTIONS):
			out.append("own_forces")
	for t in e.get("to", []):
		var owner2: String = RDRModule.PIECE_OWNER.get(String(t), "")
		if owner2 == faction:
			out.append("own_forces")
	return out


# ---------------------------------------------------------------------------
# §8.5.2 Tabella di Eligibility: cosa sceglie di fare una Fazione NP
# ---------------------------------------------------------------------------

## Decide l'azione della Fazione NP di turno leggendo la tabella dall'alto: vince
## la prima riga la cui condizione è vera.
##
## `slot` è "first" o "second". `ctx` porta ciò che il chiamante sa della carta:
##   current_critical, current_effective, current_performed,
##   current_critical_for_second, next_critical, first_on_next_if_pass,
##   first_chose ("event" | "op_sa" | …), next_is_dust_storm,
##   critical_asset_event, any_asset_event
## Le condizioni su Critical/Performed/effective vengono dalle tabelle Effective
## Events ed Event Instructions: finché non sono trascritte restano false e la
## tabella cade sull'ultima riga — Op+SA da 1ª, Operazione Limitata da 2ª. È una
## degradazione dichiarata, non un caso non gestito: `degraded` lo segnala.
## Restituisce {action, row, label, degraded}.
func choose_action(faction: String, slot: String, ctx: Dictionary = {}) -> Dictionary:
	var rows: Array = eligibility_table.get(slot, [])
	var knows_events := ctx.has("current_critical") or ctx.has("next_critical")
	for entry in rows:
		var rule: Dictionary = entry
		if rule.has("only_faction") and String(rule["only_faction"]) != faction:
			continue
		if rule.has("requires") and not _elig_condition(String(rule["requires"]), faction, ctx):
			continue
		if not _elig_condition(String(rule["cond"]), faction, ctx):
			continue
		return {"action": String(rule["action"]), "row": int(rule["n"]),
			"label": String(rule["label"]), "degraded": not knows_events}
	return {"action": "pass", "row": 0, "label": "nessuna riga applicabile",
		"degraded": not knows_events}


func _elig_condition(cond: String, faction: String, ctx: Dictionary) -> bool:
	var b := func(key: String) -> bool: return bool(ctx.get(key, false))
	match cond:
		"otherwise":
			return true
		"current_event_critical_and_effective":
			return b.call("current_critical") and b.call("current_effective")
		"critical_asset_event":
			return b.call("critical_asset_event")
		"any_asset_event":
			return b.call("any_asset_event")
		"first_chose_op_sa":
			return String(ctx.get("first_chose", "")) == "op_sa"
		"current_event_critical_for_second":
			return b.call("current_critical_for_second")
		"next_event_critical_and_first_if_pass":
			return b.call("next_critical") and b.call("first_on_next_if_pass")
		"next_critical_and_first_if_pass_and_current_not_critical_effective":
			return b.call("next_critical") and b.call("first_on_next_if_pass") \
				and not (b.call("current_critical") and b.call("current_effective"))
		"first_chose_event":
			return String(ctx.get("first_chose", "")) == "event"
		"first_chose_op_sa_and_current_critical_or_performed_effective":
			return String(ctx.get("first_chose", "")) == "op_sa" \
				and (b.call("current_critical") or b.call("current_performed")) \
				and b.call("current_effective")
		"first_on_next_if_pass":
			return b.call("first_on_next_if_pass")
		"asset_total_5plus_and_next_not_dust_storm":
			return asset_total() >= 5 and not b.call("next_is_dust_storm")
	return false


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
# §8.5.8 Piece Priorities
# ---------------------------------------------------------------------------

## Ordine in cui una Fazione NP tocca i pezzi presenti in uno spazio.
## `purpose`:
##   "enemy"           — rimuovere, sostituire o Attivare pezzi nemici
##   "friendly_place"  — piazzare o muovere pezzi amici
##   "friendly_remove" — rimuovere pezzi PROPRI: si legge la tabella al contrario
## §8.5.8: prima dei pezzi delle Fazioni NP si tolgono sempre quelli dei giocatori.
## Restituisce token "tipo" oppure "tipo:stato", nell'ordine di priorità.
func piece_order(acting: String, sid: String, purpose: String) -> Array:
	var out: Array = []
	for group in piece_priorities.get("order", []):
		var g: Dictionary = group
		match String(g.get("when", "")):
			"acting_is_np_marsgov":
				if not (acting == "marsgov" and is_np("marsgov")):
					continue
			"space_with_vulnerable_enemy_base":
				# Le unità amiche della Base vulnerabile: si espandono a runtime.
				if sid == "" or not _vulnerable_enemy_base(sid, acting):
					continue
				out.append_array(_friends_of_vulnerable_base(sid, acting))
				continue
		out.append_array(g.get("pieces", []))
	if purpose == "friendly_remove":
		out.reverse()
	elif purpose == "enemy" and bool(piece_priorities.get("player_pieces_first", true)):
		# §8.5.8 nota A: prima i pezzi dei giocatori, poi quelli delle Fazioni NP.
		var players: Array = []
		var nps: Array = []
		for token in out:
			var owner: String = RDRModule.PIECE_OWNER.get(String(token).split(":")[0], "")
			if owner != "" and is_np(owner):
				nps.append(token)
			else:
				players.append(token)
		out = players + nps
	return out


## Le unità nemiche amiche della Base vulnerabile presente nello spazio.
func _friends_of_vulnerable_base(sid: String, acting: String) -> Array:
	for base_id in ["corp_base", "cr_base", "rd_base", "mg_base"]:
		if String(RDRModule.PIECE_OWNER[base_id]) == acting:
			continue
		if module.count_in(state, sid, base_id) == 0:
			continue
		match base_id:
			"mg_base", "corp_base":
				return ["security", "mg_troop", "eg_troop", "specops:active"]
			"rd_base":
				return ["rd_rebel:hidden", "rd_rebel:active"]
			"cr_base":
				return ["cr_rebel:hidden", "cr_rebel:active"]
	return []


## Il primo pezzo davvero presente nello spazio, secondo le priorità.
## Restituisce {type, state} oppure {} se non c'è nulla di ammissibile.
func pick_piece(acting: String, sid: String, purpose: String,
		allowed: Array = []) -> Dictionary:
	for token in piece_order(acting, sid, purpose):
		var parts := String(token).split(":")
		var type_id := String(parts[0])
		if not RDRModule.PIECE_OWNER.has(type_id):
			continue  # Population e Supply sono marker, non pezzi
		if not allowed.is_empty() and not allowed.has(type_id):
			continue
		var piece_state = String(parts[1]) if parts.size() > 1 else null
		if module.count_in(state, sid, type_id, piece_state) > 0:
			return {"type": type_id, "state": "" if piece_state == null else String(piece_state)}
	return {}


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
		"rebels_at_support":
			return st.support > 0 and _count(sid, ["rd_rebel", "cr_rebel"]) > 0
		"labyrinth_or_base":
			return module.is_labyrinth(state, sid) \
				or module.count_in(state, sid, _base_of(String(test.get("faction", faction)))) > 0
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
