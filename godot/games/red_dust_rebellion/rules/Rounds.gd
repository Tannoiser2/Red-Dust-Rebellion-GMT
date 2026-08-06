class_name RDRRounds
extends RefCounted

## Flusso delle carte (§4.0), Flashpoint Round (§4.2), Dust Storm Round (§4.3)
## e tempeste (§1.10, §3.2).
##
## Le fasi che sono DECISIONI di un giocatore (Pacify/Lobby/Agitate della Support
## Phase, l'acquisto di trasporti extra da parte delle Corporations, la scelta dei
## Reclaimer sui Redeploy facoltativi) sono esposte come funzioni chiamabili ma NON
## vengono eseguite automaticamente da `dust_storm_round()`: le eseguirà la UI
## quando ci sarà l'interfaccia delle azioni. Ogni salto è annotato nel log.

const CYCLER := ["earth", "transit", "phobos"]
const MAX_STORMS := 6
const FLASHPOINT_TRIGGER := 5

var state: GameState
var module: RDRModule
var rng: RandomNumberGenerator
var cards: RDRCards = null
var log_lines: Array[String] = []

## §8.5.9: ganci del sistema Non-Player, riempiti da `RDRNonPlayerOps`. I Round
## periodici fanno scelte che al tavolo spetterebbero ai giocatori — quali pezzi
## partono da Earth, quale forza nemica toglie una tempesta, dove finiscono i
## Ribelli della Conversion se non bastano — e per un bot vanno lette dalle
## tabelle Piece Priorities e Space Selection Priorities.
## `np_piece_order.call(acting, sid, purpose) -> Array[String]`
## `np_space_order.call(acting, column, candidates) -> String`
var np_piece_order: Callable = Callable()
var np_space_order: Callable = Callable()
## §8.5.9: il Dust Storm Round delle Fazioni NP ha una scheda tutta sua, e vive
## in `RDRNonPlayerRound`. Se non c'è, i Round si comportano come sempre.
var np_round: RDRNonPlayerRound = null


func _init(p_state: GameState, p_module: RDRModule, p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	module = p_module
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func log_line(text: String) -> void:
	log_lines.append(text)


# ---------------------------------------------------------------------------
# Flusso delle carte (§4.0)
# ---------------------------------------------------------------------------

## §3.3: costruisce il mazzo e rivela Current Event e Next Event ignorando i
## valori Flashpoint stampati su queste due carte.
func begin_game() -> void:
	if cards != null:
		cards.setup()
		log_lines.append_array(cards.log_lines)
		cards.log_lines.clear()
	state.draw_deck = RDRDeck.build(rng)
	state.played_deck.clear()
	state.current_card = _draw()
	state.tracks["next_card"] = _draw()
	state.tracks["flashpoint"] = 0
	_update_haboob()
	log_line("Mazzo di %d carte. Current Event #%d, Next Event #%d." % [
		state.draw_deck.size() + 2, state.current_card, next_card()])


func current_card() -> int:
	return state.current_card


func next_card() -> int:
	return int(state.tracks.get("next_card", -1))


## §4.0: il marker Haboob è sulla Current Event quando la Next Event è una Dust
## Storm; finché c'è, Recon e March sono vietati.
func haboob_active() -> bool:
	return int(state.tracks.get("haboob", 0)) == 1


func is_game_over() -> bool:
	return int(state.tracks.get("game_over", 0)) == 1


## §4.2: chiusa la carta corrente, la Next Event diventa Current Event. Se è una
## Dust Storm si esegue subito il Dust Storm Round SENZA rivelare la Next Event;
## altrimenti si rivela la nuova Next Event, si avanza la traccia Flashpoint col
## suo valore e, se arriva in fondo, si esegue il Flashpoint Round.
func advance_card() -> void:
	if is_game_over():
		return
	if state.current_card >= 0:
		state.played_deck.append(state.current_card)
	state.current_card = next_card()
	state.tracks["next_card"] = -1
	if state.current_card < 0:
		log_line("Mazzo esaurito.")
		state.tracks["game_over"] = 1
		return
	if RDRDeck.is_dust_storm(state.current_card):
		dust_storm_round()
		return
	_reveal_next()


func _reveal_next() -> void:
	var n := _draw()
	state.tracks["next_card"] = n
	_update_haboob()
	if n < 0:
		return
	var fp := int(module.card_flashpoint.get(n, 0))
	if fp > 0:
		var t: int = int(state.tracks.get("flashpoint", 0)) + fp
		# §4.0: il valore eccedente oltre il fondo della traccia si ignora.
		state.tracks["flashpoint"] = mini(t, FLASHPOINT_TRIGGER)
		if t >= FLASHPOINT_TRIGGER:
			flashpoint_round()


func _draw() -> int:
	if state.draw_deck.is_empty():
		return -1
	return state.draw_deck.pop_back()


func _update_haboob() -> void:
	var n := next_card()
	state.tracks["haboob"] = 1 if (n >= 0 and RDRDeck.is_dust_storm(n)) else 0


# ---------------------------------------------------------------------------
# Flashpoint Round (§4.2)
# ---------------------------------------------------------------------------

func flashpoint_round() -> void:
	log_line("— Flashpoint Round —")
	aldrin_cycler()
	corporate_casualties()
	earthgov_confidence_phase()
	terraforming()
	dust_storm_phase()
	attrition()
	conversion()
	state.tracks["flashpoint"] = 0
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)


## §4.2 fase 1 (anche da Logistics e dal Passo delle Corporations).
## `extra`: pezzi in più che le Corporations comprano a 1 Profit l'uno oltre ai
## cinque gratuiti. Vale solo per un giocatore in carne e ossa.
func aldrin_cycler(extra: int = 0) -> void:
	# Transit -> Phobos (forze e marker).
	_move_everything("transit", "phobos")

	# I marker Popolazione arrivati su Phobos vanno in Displaced Population.
	var pop := module.marker(state, "phobos", "population")
	if pop > 0:
		module.set_marker(state, "phobos", "population", 0)
		state.tracks["displaced_population"] = int(state.tracks.get("displaced_population", 0)) + pop

	# I Satelliti su Phobos vanno in Orbit.
	var sats := module.count_in(state, "phobos", "satellite")
	if sats > 0:
		module.move_pieces(state, "phobos", "orbit", "satellite", sats)

	# Ogni Supply su Phobos vale +3 Risorse MarsGov, poi torna nel pool.
	var supply := module.marker(state, "phobos", "supply")
	if supply > 0:
		module.set_marker(state, "phobos", "supply", 0)
		# Campaign #3 "Dock Workers Lockout": metà delle Supply arrivate (per
		# eccesso) è scartata prima della conversione.
		if module.campaign_active(state, 3):
			var lost := int(ceil(supply / 2.0))
			supply -= lost
			log_line("Campaign «Dock Workers Lockout»: %d Supply scartate." % lost)
		# Campaign #8 "Earth-Based Endorsements": ogni Supply vale 2 Risorse
		# MarsGov e 1 Red Dust invece di 3 MarsGov.
		var endorsements := module.campaign_active(state, 8)
		# §8.5.4: le Supply che arriverebbero a Risorse MarsGov alzano invece il
		# Supply Total di 1 ciascuna, quante che siano le Risorse che avrebbero
		# fruttato — così la Campaign non cambia niente per NP MG.
		if module.is_np(state, "marsgov"):
			module.add_supply(state, supply)
			log_line("Aldrin Cycler: %d Supply su Phobos → Supply Total %d." % [
				supply, module.supply_total(state)])
		elif endorsements:
			state.add_resources("marsgov", supply * 2, 50)
			log_line("Aldrin Cycler: %d Supply → +%d Risorse MarsGov." % [supply, supply * 2])
		else:
			state.add_resources("marsgov", supply * 3, 50)
			log_line("Aldrin Cycler: %d Supply su Phobos → +%d Risorse MarsGov." % [supply, supply * 3])
		# La quota Red Dust della Campaign: per NP RD diventa Agitate Total.
		if endorsements:
			if module.is_np(state, "red_dust"):
				module.add_agitate(state, supply)
				log_line("Earth-Based Endorsements: Agitate Total +%d (ora %d)." % [
					supply, module.agitate_total(state)])
			else:
				state.add_resources("red_dust", supply, 50)
				log_line("Earth-Based Endorsements: +%d Risorse Red Dust." % supply)

	# Una Popolazione da Earth a Transit (al massimo una alla volta in Transit).
	if module.marker(state, "earth", "population") > 0 and module.marker(state, "transit", "population") == 0:
		module.add_marker(state, "earth", "population", -1)
		module.add_marker(state, "transit", "population", 1)

	# L'EarthGov Controller sceglie 5 altri pezzi su Earth da mandare in Transit;
	# se non c'è Controller non parte nulla.
	var controller := module.eg_controller(state)
	if controller == "":
		log_line("Aldrin Cycler: nessun EarthGov Controller, nessun pezzo parte da Earth.")
	else:
		# §4.2: oltre ai cinque, le Corporations possono comprarne altri a 1
		# Profit l'uno. §8.5.9: «NP CORP will never spend any Profits to move
		# additional pieces from Earth to Transit» — per un bot non si compra.
		var bought := 0
		if extra > 0 and controller == "corporations" and state.is_player("corporations"):
			bought = mini(extra, int(state.tracks.get("profits", 0)))
		var moved := _ship_from_earth(controller, 5 + bought)
		var paid: int = maxi(0, moved - 5)
		if paid > 0:
			_add_profits(-paid)
			log_line("Aldrin Cycler: %d pezzi in più comprati per %d Profits." % [paid, paid])
		log_line("Aldrin Cycler: %s spedisce %d pezzi da Earth a Transit." % [controller, moved])


## Politica provvisoria per la scelta dei 5 pezzi (§4.2): è una decisione del
## Controller, qui automatizzata con una priorità sensata finché non c'è la UI.
## MarsGov privilegia Supply e Truppe EG; le Corporations le proprie unità.
func _ship_from_earth(controller: String, budget: int) -> int:
	var order: Array[String] = ["supply", "eg_troop", "satellite", "security", "specops"]
	if controller == "corporations":
		order = ["security", "specops", "satellite", "supply", "eg_troop"]
	# §8.5.9: per un EarthGov Controller gestito dal bot l'ordine lo detta la
	# tabella Piece Priorities — che per NP MG mette le Supply in cima, e sono
	# proprio quelle che gli servono, visto che il Supply Total sostituisce le
	# sue Risorse.
	if not np_piece_order.is_null() and module.is_np(state, controller):
		var np_order: Array = np_piece_order.call(controller, "", "friendly_place")
		var out: Array[String] = []
		for token in np_order:
			var t := String(token).split(":")[0]
			if order.has(t) and not out.has(t):
				out.append(t)
		for t in order:
			if not out.has(t):
				out.append(t)
		order = out
	var moved := 0
	for key in order:
		if moved >= budget:
			break
		var want := budget - moved
		if key == "supply":
			var have := module.marker(state, "earth", "supply")
			var take: int = mini(have, want)
			if take > 0:
				module.add_marker(state, "earth", "supply", -take)
				module.add_marker(state, "transit", "supply", take)
				moved += take
		else:
			moved += module.move_pieces(state, "earth", "transit", key, want)
	return moved


## §4.2 fase 2 / §4.3: le perdite delle Corporations costano Profits, poi
## tornano fra le Disponibili. Gli SpecOps nelle Casualties non costano nulla.
func corporate_casualties() -> void:
	var bases := module.count_in(state, "casualties", "corp_base")
	var sec := module.count_in(state, "casualties", "security")
	var loss := bases + int(sec / 2.0)
	if loss > 0:
		_add_profits(-loss)
		log_line("Corporate Casualties: −%d Profits (%d Basi, %d Security)." % [loss, bases, sec])
	for type_id in ["corp_base", "security", "specops"]:
		var n := module.count_in(state, "casualties", type_id)
		if n > 0:
			module.remove_pieces(state, "casualties", type_id, n, "available")


## §4.2 fase 3.
func earthgov_confidence_phase() -> void:
	# I Satelliti su Mars tornano in Orbit.
	for sid in module.mars_spaces(state):
		var n := module.count_in(state, sid, "satellite")
		if n > 0:
			module.move_pieces(state, sid, "orbit", "satellite", n)

	var before := int(state.tracks.get("eg_confidence", 0))
	var side := int(state.tracks.get("eg_side", -1))
	var after: int = clampi(before + (1 if side > 0 else -1), 0, 8)
	state.tracks["eg_confidence"] = after
	log_line("EG Confidence: %s → casella %d (Controller: %s)." % [
		"EG+" if side > 0 else "EG-", after,
		module.eg_controller(state) if module.eg_controller(state) != "" else "nessuno"])

	if after == 0:
		# Fondo traccia: le Truppe EG lasciano la mappa, i Satelliti in Orbit
		# tornano su Earth (quelli nelle Casualties restano dove sono).
		var off_map_ids: Array[String] = ["phobos"]
		for sid in Array(module.mars_spaces(state)) + off_map_ids:
			var t := module.count_in(state, String(sid), "eg_troop")
			if t > 0:
				module.remove_pieces(state, String(sid), "eg_troop", t, "available")
		var o := module.count_in(state, "orbit", "satellite")
		if o > 0:
			module.move_pieces(state, "orbit", "earth", "satellite", o)
		log_line("EG Confidence al fondo: Truppe EG fuori dalla mappa, Satelliti su Earth.")

	# Rinforzi su Earth secondo la casella raggiunta.
	var box: Dictionary = module.eg_box(state)
	var troops := int(box.get("eg_troops", 0))
	if troops > 0:
		module.place_from_available(state, "earth", "eg_troop", troops)
	module.add_marker(state, "earth", "supply", int(box.get("supply", 0)))
	module.add_marker(state, "earth", "population", int(box.get("population", 0)))


## §4.2 fase 4: le Basi Terraforming producono Profits, i Conversion Center nei
## Deserti li erodono.
func terraforming() -> void:
	var gain := 0
	for sid in module.mars_spaces(state):
		if not module.is_desert(state, sid):
			continue
		var terra := module.count_in(state, sid, "corp_base", "terraforming")
		if terra > 0:
			gain += 2 + (terra - 1)
		gain -= module.count_in(state, sid, "cr_base", "conversion_center")
	if gain != 0:
		_add_profits(gain)
		log_line("Terraforming: %+d Profits." % gain)


## §4.2 fase 5: via le Raging, le Approaching diventano Raging, poi nuovi tiri
## pari al Flashpoint della Next Event.
func dust_storm_phase() -> void:
	for sid in module.mars_spaces(state):
		match module.storm(state, sid):
			2: module.set_marker(state, sid, "storm", 0)
			1: module.set_marker(state, sid, "storm", 2)
	var n := next_card()
	var rolls := int(module.card_flashpoint.get(n, 0)) if n >= 0 else 0
	storm_rolls(rolls)


## §4.2 fase 6: nei Deserti Spopolati o in tempesta senza Base amica.
## Truppe EG, SpecOps e Ribelli Reclaimer non sono mai toccati.
func attrition() -> void:
	for sid in module.mars_spaces(state):
		if not module.is_desert(state, sid):
			continue
		if module.population(state, sid) > 0 and not module.has_raging_storm(state, sid):
			continue
		var coin_base := module.count_in(state, sid, "mg_base") + module.count_in(state, sid, "corp_base")
		if coin_base == 0:
			module.remove_pieces(state, sid, "mg_troop", 1, "available")
			module.remove_pieces(state, sid, "security", 1, "casualties")
		if module.count_in(state, sid, "rd_base") == 0:
			module.remove_pieces(state, sid, "rd_rebel", 1, "available")


## §4.2 fase 7: un Ribelle Reclaimer in ogni spazio Popolato con un Conversion
## Center. §8.5.9: se i Ribelli disponibili non bastano per tutti, quali spazi
## servire lo decide la colonna Place Rebels — e solo allora, perché finché ce
## n'è per tutti non c'è niente da scegliere.
func conversion() -> void:
	var centers: Array = []
	for sid in module.mars_spaces(state):
		if module.population(state, sid) <= 0:
			continue
		if module.count_in(state, sid, "cr_base", "conversion_center") > 0:
			centers.append(String(sid))
	if centers.is_empty():
		return
	var stock := module.available(state, "cr_rebel")
	if stock < centers.size() and not np_space_order.is_null() \
			and module.is_np(state, "reclaimer"):
		var ordered: Array = []
		var pool: Array = centers.duplicate()
		while not pool.is_empty():
			var pick := String(np_space_order.call("reclaimer", "place_rebels", pool))
			if pick == "":
				break
			ordered.append(pick)
			pool.erase(pick)
		ordered.append_array(pool)   # quel che la tabella non ordina resta in coda
		centers = ordered
		log_line("Conversion: %d Ribelli per %d Conversion Center, ordine dalla tabella." % [
			stock, ordered.size()])
	for sid in centers:
		module.place_from_available(state, String(sid), "cr_rebel", 1, "hidden")


# ---------------------------------------------------------------------------
# Tempeste (§1.10, §3.2, §4.2)
# ---------------------------------------------------------------------------

## Spazio corrispondente a un tiro (d6 bianco = Settore, d6 nero = spazio).
## I settori 1/2 e 5/6 condividono le stesse tabelle; Hellas Chaos occupa i
## risultati 3 e 4 del suo settore.
func space_for_roll(white: int, black: int) -> String:
	var sector := white
	if white == 2:
		sector = 1
	elif white == 6:
		sector = 5
	for sid in module.storm_table.keys():
		var d: Array = module.storm_table[sid]
		for pair in d:
			if int(pair[0]) == sector and int(pair[1]) == black:
				return sid
	return ""


func storms_on_map() -> int:
	var n := 0
	for sid in module.mars_spaces(state):
		if module.storm(state, sid) > 0:
			n += 1
	return n


## §4.2: `count` tiri, o finché ci sono 6 marker tempesta sulla mappa. Se lo
## spazio ha già una tempesta, questa passa a Raging e i Reclaimer possono
## rimuovere una forza nemica (qui rimossa automaticamente, vedi `_reclaimer_strike`).
func storm_rolls(count: int) -> void:
	for i in range(count):
		if storms_on_map() >= MAX_STORMS:
			log_line("Tempeste: raggiunto il limite di %d marker." % MAX_STORMS)
			return
		var white := rng.randi_range(1, 6)
		var black := rng.randi_range(1, 6)
		var sid := space_for_roll(white, black)
		if sid == "":
			continue
		var cur := module.storm(state, sid)
		if cur == 0:
			module.set_marker(state, sid, "storm", 1)
			log_line("Tempesta in arrivo su %s (%d/%d)." % [
				state.game_def.space(sid).name, white, black])
		else:
			if cur == 1:
				module.set_marker(state, sid, "storm", 2)
			_reclaimer_strike(sid)
			log_line("Tempesta furiosa su %s (%d/%d)." % [
				state.game_def.space(sid).name, white, black])


## §4.2/§3.2: sul secondo risultato nello stesso spazio i Reclaimer possono
## rimuovere una forza nemica (le Basi solo se non restano unità amiche).
## §8.5.9: se i Reclaimer sono un bot, quale forza cade lo dice la tabella Piece
## Priorities; per un giocatore resta l'ordine automatico — prima le unità, poi
## le Basi indifese — perché l'interfaccia la scelta non la sa ancora chiedere.
func _reclaimer_strike(sid: String) -> void:
	var units: Array = ["mg_troop", "security", "eg_troop", "specops", "rd_rebel"]
	if not np_piece_order.is_null() and module.is_np(state, "reclaimer"):
		var np_order: Array = np_piece_order.call("reclaimer", sid, "enemy")
		var out: Array = []
		for token in np_order:
			var t := String(token).split(":")[0]
			if units.has(t) and not out.has(t):
				out.append(t)
		for t in units:
			if not out.has(t):
				out.append(t)
		units = out
	for type_id in units:
		if module.count_in(state, sid, String(type_id)) > 0:
			var dest := "casualties" if type_id in ["security", "specops", "eg_troop"] else "available"
			module.remove_pieces(state, sid, String(type_id), 1, dest)
			return
	for base_id in ["rd_base", "mg_base", "corp_base"]:
		if module.count_in(state, sid, base_id) == 0:
			continue
		var guard := "rd_rebel" if base_id == "rd_base" else ""
		if guard != "" and module.count_in(state, sid, guard) > 0:
			continue
		if base_id != "rd_base":
			var cubes := module.count_in(state, sid, "mg_troop") + module.count_in(state, sid, "security") \
				+ module.count_in(state, sid, "eg_troop") + module.count_in(state, sid, "specops")
			if cubes > 0:
				continue
		module.remove_pieces(state, sid, base_id, 1,
			"casualties" if base_id == "corp_base" else "available")
		return


# ---------------------------------------------------------------------------
# Dust Storm Round (§4.3)
# ---------------------------------------------------------------------------

func dust_storm_round() -> void:
	state.tracks["dust_storm_rounds"] = int(state.tracks.get("dust_storm_rounds", 0)) + 1
	var n := int(state.tracks["dust_storm_rounds"])
	log_line("— Dust Storm Round %d/3 —" % n)

	if victory_phase():
		return
	resources_phase()
	support_phase()
	redeploy_phase()
	if n >= 3:
		log_line("Terzo Dust Storm Round completato: fine partita.")
		_end_game()
		return
	reset_phase()


## §4.3 fase 1. Restituisce true se la partita finisce qui.
func victory_phase() -> bool:
	corporate_casualties()
	earthgov_casualties()
	displaced_population_penalty()
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)
	var v := module.victory_status(state)
	var winners: Array[String] = []
	for fid in v.keys():
		if v[fid]["won"]:
			winners.append(String(fid))
	if winners.is_empty():
		return false
	if np_round != null \
			and np_round.victory_blocked(int(state.tracks.get("dust_storm_rounds", 0))):
		return false
	log_line("Check di vittoria: %s ha raggiunto la propria condizione." % ", ".join(winners))
	_end_game()
	return true


## §4.3: −1 EG Confidence per Satellite e ogni 2 Truppe EG nelle Casualties.
func earthgov_casualties() -> void:
	var sats := module.count_in(state, "casualties", "satellite")
	var troops := module.count_in(state, "casualties", "eg_troop")
	var drop := sats + int(troops / 2.0)
	if drop > 0:
		state.tracks["eg_confidence"] = maxi(0, int(state.tracks.get("eg_confidence", 0)) - drop)
		log_line("EarthGov Casualties: −%d EG Confidence." % drop)
	if troops > 0:
		module.remove_pieces(state, "casualties", "eg_troop", troops, "available")
	if sats > 0:
		module.move_pieces(state, "casualties", "earth", "satellite", sats)


## §4.3: ogni 2 marker in Displaced Population, −3 Risorse MarsGov e −1 Profit.
func displaced_population_penalty() -> void:
	var pairs := int(int(state.tracks.get("displaced_population", 0)) / 2.0)
	if pairs <= 0:
		return
	# §8.5.9: NP MG paga in Supply Total, non in Risorse. NP CORP i Profits li
	# traccia comunque (§8.5.4), quindi quelli si tolgono a chiunque.
	if np_round == null or not np_round.displaced_population_penalty(pairs):
		state.add_resources("marsgov", -3 * pairs, 50)
		log_line("Displaced Population: −%d Risorse MarsGov." % (3 * pairs))
	_add_profits(-pairs)
	log_line("Displaced Population: −%d Profits." % pairs)


## §4.3 fase 2.
func resources_phase() -> void:
	var mg := 0
	var rd := 0
	var corp := 0
	for sid in module.mars_spaces(state):
		var st: SpaceState = state.spaces[sid]
		var pop := module.population(state, sid)
		if st.control == "coin" and st.support >= 0:
			mg += pop
		if st.support == CoinEnums.Support.ACTIVE_OPPOSITION:
			rd += pop
		if module.is_labyrinth(state, sid):
			corp += 2 * module.count_in(state, sid, "corp_base")
	rd += module.bases_on_map(state, "red_dust")
	# §8.5.4: «Resources are not tracked for NP MG or NP RD, so we skip their
	# steps». NP CORP invece i Profits li traccia e li incassa come tutti.
	if module.is_np(state, "marsgov"):
		mg = 0
	else:
		state.add_resources("marsgov", mg, 50)
	if module.is_np(state, "red_dust"):
		rd = 0
	else:
		state.add_resources("red_dust", rd, 50)
	_add_profits(corp)
	log_line("Resources: MarsGov +%d, Red Dust +%d, Corporations +%d Profits." % [mg, rd, corp])
	# §4.3: i Reclaimer pescano 1 Asset per ogni simbolo scoperto sulla traccia
	# Basi Disponibili, poi scartano fino al limite di 6 carte in mano.
	if cards != null:
		var symbols := int(module.available(state, "cr_base") / 4.0)
		var drawn := cards.draw_asset(maxi(1, symbols))
		log_line("Reclaimer Earnings: %d Asset card pescate." % drawn)
		log_lines.append_array(cards.log_lines)
		cards.log_lines.clear()
	else:
		log_line("Reclaimer Earnings: mazzo Asset non collegato.")


## §4.3 fase 3. Per un giocatore Pacify, Lobby e Agitate sono decisioni sue e
## l'interfaccia non le sa ancora chiedere; per una Fazione NP la scheda §8.5.9
## le prescrive, e allora si risolvono.
func support_phase() -> void:
	if np_round != null:
		np_round.support_phase()
	var waiting: Array[String] = []
	for fid in ["marsgov", "red_dust"]:
		if state.is_player(fid):
			waiting.append(fid)
	if not waiting.is_empty():
		log_line("Support Phase: Pacify/Lobby/Agitate di %s restano ai giocatori (UI non ancora pronta)." %
			", ".join(waiting))


## §4.3 fase 4. Sono automatizzati solo gli spostamenti OBBLIGATORI; quelli
## facoltativi (Truppe MG in più, Ribelli RD/CR verso le proprie Basi, Basi CR
## nella Wilderness) restano ai giocatori.
func redeploy_phase() -> void:
	for sid in module.mars_spaces(state):
		module.set_marker(state, sid, "storm", 0)

	# §8.5.9: chi è gestito dal bot ridispiega con le proprie istruzioni, e la
	# procedura minima qui sotto non lo tocca più.
	var np_done: Array = np_round.redeploy_phase() if np_round != null else []

	# Truppe EarthGov: da Mars a Phobos (o su spazi con Base MG; qui Phobos).
	var eg_ctrl := module.eg_controller(state)
	if eg_ctrl == "" or state.is_player(eg_ctrl):
		for sid in module.mars_spaces(state):
			var eg := module.count_in(state, sid, "eg_troop")
			if eg > 0:
				module.move_pieces(state, sid, "phobos", "eg_troop", eg)

	# Truppe MarsGov nei Deserti senza Base COIN.
	if not np_done.has("marsgov"):
		var mg_dest := _mg_redeploy_targets()
		for sid in module.mars_spaces(state):
			if not module.is_desert(state, sid):
				continue
			if module.count_in(state, sid, "mg_base") + module.count_in(state, sid, "corp_base") > 0:
				continue
			var t := module.count_in(state, sid, "mg_troop")
			if t <= 0:
				continue
			if mg_dest == "":
				log_line("Redeploy: nessuna destinazione valida per le Truppe MarsGov in %s." % sid)
				continue
			module.move_pieces(state, sid, mg_dest, "mg_troop", t)

	# Ribelli Red Dust nei Deserti senza Opposizione né Base RD.
	if not np_done.has("red_dust"):
		var rd_dest := _rd_redeploy_target()
		for sid in module.mars_spaces(state):
			if not module.is_desert(state, sid):
				continue
			var st: SpaceState = state.spaces[sid]
			if st.support < 0 or module.count_in(state, sid, "rd_base") > 0:
				continue
			var r := module.count_in(state, sid, "rd_rebel")
			if r <= 0:
				continue
			if rd_dest == "":
				# §4.3: senza Basi RD in gioco i Ribelli che devono muovere sono rimossi.
				module.remove_pieces(state, sid, "rd_rebel", r, "available")
			else:
				module.move_pieces(state, sid, rd_dest, "rd_rebel", r)

	module.recompute_all_control(state)


func _mg_redeploy_targets() -> String:
	for sid in module.mars_spaces(state):
		if module.is_labyrinth(state, sid) and state.spaces[sid].control == "coin":
			return sid
	for sid in module.mars_spaces(state):
		if module.count_in(state, sid, "mg_base") > 0:
			return sid
	return ""


func _rd_redeploy_target() -> String:
	for sid in module.mars_spaces(state):
		if module.count_in(state, sid, "rd_base") > 0:
			return sid
	return ""


## §4.3 fase 5.
func reset_phase() -> void:
	if np_round != null:
		np_round.reset_phase()
	# La Popolazione su Earth pareggia il valore della traccia EG Confidence.
	module.set_marker(state, "earth", "population", module.eg_confidence_value(state))

	# Tutti i Ribelli e gli SpecOps tornano Nascosti.
	for sid in state.spaces.keys():
		for type_id in ["rd_rebel", "cr_rebel", "specops"]:
			var n := module.count_in(state, sid, type_id, "active")
			if n > 0:
				var fid: String = RDRModule.PIECE_OWNER[type_id]
				state.spaces[sid].remove_piece(fid, type_id, n, "active")
				state.spaces[sid].add_piece(fid, type_id, n, "hidden")

	# §4.3: la Campaign attiva esce dal gioco, gli Asset scartati rientrano nel mazzo.
	state.active_momentum = PackedStringArray()
	if cards != null:
		cards.remove_campaign()
		cards.reshuffle_discards()
		log_line("Reset: Campaign card rimossa, Asset scartate rimescolate.")
	else:
		log_line("Reset: mazzi Asset/Campaign non collegati.")

	for f in state.game_def.factions:
		state.eligibility[f.id] = CoinEnums.Eligibility.ELIGIBLE

	# Si rivelano Current e Next ignorando i loro Flashpoint, poi si tira per le
	# tempeste per un totale pari alla somma dei due valori.
	state.played_deck.append(state.current_card)
	state.current_card = _draw()
	state.tracks["next_card"] = _draw()
	_update_haboob()
	state.tracks["flashpoint"] = 0
	var total := 0
	for n in [state.current_card, next_card()]:
		if n >= 0:
			total += int(module.card_flashpoint.get(n, 0))
	storm_rolls(total)
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)


func _end_game() -> void:
	state.tracks["game_over"] = 1
	var v := module.victory_status(state)
	var best := ""
	var best_margin := -999
	for fid in module.tiebreak_order():
		var d: Dictionary = v[fid]
		if int(d["margin"]) > best_margin:
			best_margin = int(d["margin"])
			best = String(fid)
	state.tracks["winner"] = best
	log_line("Vincitore: %s (margine %+d)." % [best, best_margin])


func _add_profits(delta: int) -> void:
	state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) + delta, 0, 50)


## Sposta forze e marker (Supply/Popolazione) da uno spazio all'altro.
func _move_everything(from_sid: String, to_sid: String) -> void:
	for type_id in RDRModule.PIECE_OWNER.keys():
		var n := module.count_in(state, from_sid, String(type_id))
		if n > 0:
			module.move_pieces(state, from_sid, to_sid, String(type_id), n)
	for key in ["supply", "population"]:
		var m := module.marker(state, from_sid, key)
		if m > 0:
			module.set_marker(state, from_sid, key, 0)
			module.add_marker(state, to_sid, key, m)
