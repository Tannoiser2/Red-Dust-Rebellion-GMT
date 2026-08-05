extends SceneTree

## Test headless del modulo Red Dust Rebellion.
##   godot --headless --path godot -s res://tests/test_runner.gd
##
## I test di setup verificano i totali STAMPATI sull'Edge Track a inizio partita
## (Rulebook §3.1): se popolazione, adiacenze, forze o regole di Controllo sono
## sbagliate, questi numeri non tornano.

var passed := 0
var failed := 0
var module: RDRModule
var gd: GameDef
var state: GameState


func _init() -> void:
	module = RDRModule.new()
	gd = module.build_game_def()
	state = GameState.new(gd)
	module.apply_setup(state, "standard")

	test_game_def()
	test_spaces()
	test_adjacency()
	test_maglev()
	test_cards()
	test_setup_forces()
	test_setup_totals()
	test_control()
	test_eg_confidence()
	test_victory()

	test_deck()
	test_card_flow()
	test_flashpoint_trigger()
	test_haboob()
	test_sequence()
	test_pass()
	test_reclaimer_order()
	test_aldrin_cycler()
	test_corporate_casualties()
	test_eg_confidence_phase()
	test_terraforming()
	test_attrition()
	test_conversion()
	test_storm_table()
	test_storm_rolls()
	test_dust_storm_resources()
	test_dust_storm_round()
	test_game_end()

	print("\n%d passati, %d falliti" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------

func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FALLITO: %s" % label)


func eq(actual, expected, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		print("  FALLITO: %s — atteso %s, ottenuto %s" % [label, expected, actual])


# ---------------------------------------------------------------------------

func test_game_def() -> void:
	print("GameDef")
	eq(gd.title, "Red Dust Rebellion", "titolo")
	eq(gd.factions.size(), 5, "5 Fazioni (4 giocabili + EarthGov)")
	eq(gd.piece_types.size(), 11, "11 tipi di pezzo")
	# §1.3: i Satelliti non contano per il Controllo.
	eq(gd.piece_type("satellite").counts_for_control, false, "Satelliti esclusi dal Controllo")
	eq(gd.piece_type("rd_base").states, PackedStringArray(["basic", "dug_in"]), "stati Base RD")
	eq(gd.piece_type("corp_base").states, PackedStringArray(["basic", "terraforming"]), "stati Base CORP")
	eq(gd.piece_type("cr_base").states, PackedStringArray(["basic", "conversion_center"]), "stati Base CR")


func test_spaces() -> void:
	print("Spazi")
	var labyrinths := 0
	var deserts := 0
	var total_pop := 0
	for s in gd.spaces:
		match s.terrain:
			"labyrinth":
				labyrinths += 1
			"desert":
				deserts += 1
		total_pop += module.printed_pop.get(s.id, 0)
	# 8 Labirinti su Mars + Phobos; 15 Deserti settoriali + The Wilderness.
	eq(labyrinths, 9, "9 Labirinti (8 su Mars + Phobos)")
	eq(deserts, 16, "16 Deserti (15 settoriali + Wilderness)")
	eq(total_pop, 33, "Popolazione stampata totale su Mars")
	# §1.2: Wilderness e Phobos sono sempre Spopolati.
	eq(module.printed_pop["wilderness"], 0, "Wilderness spopolata")
	eq(module.printed_pop["phobos"], 0, "Phobos spopolato")
	eq(module.printed_pop["tenzing"], 3, "Tenzing pop 3")
	eq(module.printed_pop["shenzhou"], 3, "Shenzhou pop 3")


func test_adjacency() -> void:
	print("Adiacenze")
	# Simmetria: se A è adiacente a B, B deve esserlo ad A.
	var asym: Array[String] = []
	for s in gd.spaces:
		for other in s.adjacent:
			var o: SpaceDef = gd.space(other)
			if o == null:
				asym.append("%s -> %s (inesistente)" % [s.id, other])
			elif not o.adjacent.has(s.id):
				asym.append("%s -> %s" % [s.id, other])
	eq(asym, [] as Array[String], "adiacenze simmetriche")

	# §1.2: la Wilderness è adiacente a tutti i Deserti che toccano il bordo del
	# proprio Settore (13), e a nessun Labirinto.
	var wild: SpaceDef = gd.space("wilderness")
	eq(wild.adjacent.size(), 13, "Wilderness adiacente a 13 Deserti")
	var lab_adj := false
	for a in wild.adjacent:
		if gd.space(a).terrain == "labyrinth":
			lab_adj = true
	eq(lab_adj, false, "nessun Labirinto adiacente alla Wilderness")
	# I due Deserti dell'anello interno di Tharsis non toccano il bordo.
	eq(wild.adjacent.has("pavonis_mons"), false, "Pavonis Mons non tocca la Wilderness")
	eq(wild.adjacent.has("syria_planum"), false, "Syria Planum non tocca la Wilderness")

	# §1.2: gli spazi dell'Aldrin Cycler non sono adiacenti a nulla.
	for sid in ["earth", "transit", "phobos", "orbit"]:
		eq(gd.space(sid).adjacent.size(), 0, "%s senza adiacenze" % sid)


func test_maglev() -> void:
	print("Maglev")
	eq(module.maglev.size(), 5, "5 linee Maglev")
	# La Rodgers Line (Europa-Tereshkova) è in costruzione: chiusa finché
	# l'Evento #14 non la apre.
	var links := module.maglev_links(state, "europa")
	eq(links.has("tereshkova"), false, "Rodgers Line chiusa al setup")
	eq(links.has("tenzing"), true, "Europa-Tenzing aperta")
	state.active_capabilities.append("rodgers_line")
	eq(module.maglev_links(state, "europa").has("tereshkova"), true, "Rodgers Line aperta dopo #14")
	state.active_capabilities.remove_at(state.active_capabilities.size() - 1)


func test_cards() -> void:
	print("Carte Evento")
	eq(gd.cards.size(), 51, "51 carte Evento (48 + 3 Dust Storm)")
	eq(gd.card(1).title, "A Green New Deal", "titolo carta 1")
	eq(gd.card(1).faction_order, PackedStringArray(
		["marsgov", "corporations", "red_dust", "reclaimer"]), "ordine carta 1")
	eq(gd.card(14).title, "The Rodgers Line", "titolo carta 14")
	eq(gd.card(14).faction_order, PackedStringArray(
		["corporations", "red_dust", "marsgov", "reclaimer"]), "ordine carta 14")
	# §4.1: i Reclaimer sono sempre ultimi nell'ordine stampato.
	var not_last: Array[int] = []
	for c in gd.cards:
		if c.faction_order.size() == 4 and c.faction_order[3] != "reclaimer":
			not_last.append(c.number)
	eq(not_last, [] as Array[int], "Reclaimer sempre ultimi nell'ordine")
	# Ogni Evento non-Dust-Storm ha 4 Fazioni e un testo non ombreggiato.
	var bad: Array[int] = []
	for c in gd.cards:
		if c.number >= 49:
			continue
		if c.faction_order.size() != 4 or c.unshaded == "":
			bad.append(c.number)
	eq(bad, [] as Array[int], "48 Eventi con ordine e testo completi")


func test_setup_forces() -> void:
	print("Setup — inventario forze")
	# Per ogni tipo di pezzo: in gioco + disponibili = inventario della Faction mat.
	var avail: Dictionary = state.tracks.get("available", {})
	var expected := {
		"mg_troop": 30, "mg_base": 3,
		"security": 16, "specops": 8, "corp_base": 9,
		"eg_troop": 16,
		"rd_rebel": 30, "rd_base": 9,
		"cr_rebel": 20, "cr_base": 15,
	}
	for type_id in expected.keys():
		var owner: String = RDRModule.PIECE_OWNER[type_id]
		var on_map := 0
		for sid in state.spaces.keys():
			on_map += state.spaces[sid].count(owner, type_id)
		var in_pool := 0
		for fid in avail.keys():
			in_pool += int(avail[fid].get(type_id, 0))
		eq(on_map + in_pool, int(expected[type_id]), "inventario %s" % type_id)


func test_setup_totals() -> void:
	print("Setup — totali stampati sull'Edge Track")
	# §3.1: i valori iniziali dei marcatori sull'Edge Track.
	eq(module.total_support(state), 11, "Totale Supporto")
	eq(module.eg_confidence_value(state), 1, "EG Confidence")
	eq(module.total_opposition(state), 9, "Totale Opposizione")
	eq(module.bases_on_map(state, "red_dust"), 5, "Basi Red Dust")
	eq(module.bases_on_map(state, "reclaimer"), 4, "Basi Reclaimer")
	eq(module.enemy_bases(state), 10, "Basi nemiche (per i Reclaimer)")
	eq(state.resources["marsgov"], 18, "Risorse MarsGov")
	eq(state.resources["red_dust"], 14, "Risorse Red Dust")
	eq(int(state.tracks["profits"]), 0, "Profits")
	eq(int(state.tracks["displaced_population"]), 4, "Displaced Population")
	# §1.7: il Danno iniziale riduce la Popolazione degli spazi interessati.
	eq(module.population(state, "ascraeus_mons"), 0, "Ascraeus Mons spopolata dal Danno")
	eq(module.population(state, "tenzing"), 3, "Tenzing pop 3 (nessun Danno)")


func test_control() -> void:
	print("Controllo (§1.9)")
	# Coalizione COIN contro tutti i Ribelli.
	eq(module.control_of(state, "europa"), "coin", "Europa sotto Controllo COIN")
	eq(module.control_of(state, "tharsis_tholus"), "coin", "Tharsis Tholus COIN")
	eq(module.control_of(state, "ascraeus_mons"), "reclaimer", "Ascraeus Mons Reclaimer")
	eq(module.control_of(state, "wilderness"), "reclaimer", "Wilderness Reclaimer")
	eq(module.control_of(state, "trouvelot"), "reclaimer", "Trouvelot Reclaimer")
	# New Córdoba: 3 forze CR contro 2 MG + 1 RD = pareggio, nessun Controllo.
	eq(module.control_of(state, "new_cordoba"), "", "New Córdoba Incontrollata")
	eq(module.control_of(state, "noctis_labyrinthus"), "red_dust", "Noctis Labyrinthus Red Dust")
	eq(module.control_of(state, "sharma"), "red_dust", "Sharma Red Dust")
	# §1.2: Phobos è permanentemente COIN.
	eq(module.control_of(state, "phobos"), "coin", "Phobos sempre COIN")
	eq(module.cr_controlled_spaces(state), 3, "3 spazi sotto Controllo Reclaimer")


func test_eg_confidence() -> void:
	print("EarthGov Confidence (§1.2)")
	eq(module.eg_controller(state), "corporations", "Controller iniziale = Corporations")
	eq(int(state.tracks["eg_side"]), -1, "marcatore su EG-")
	# Salendo di tre caselle si arriva alla zona '6 MG'.
	state.tracks["eg_confidence"] = 6
	eq(module.eg_controller(state), "marsgov", "casella 6 -> MarsGov Controller")
	eq(module.eg_confidence_value(state), 6, "valore 6")
	state.tracks["eg_confidence"] = 0
	eq(module.eg_controller(state), "", "fondo traccia -> nessun Controller")
	state.tracks["eg_confidence"] = 3


func test_victory() -> void:
	print("Vittoria (§2.0)")
	var v := module.victory_status(state)
	eq(v["marsgov"]["value"], 12, "MarsGov: Supporto + EG Confidence")
	eq(v["red_dust"]["value"], 14, "Red Dust: Opposizione + Basi")
	eq(v["reclaimer"]["value"], 7, "Reclaimer: Controllo + Basi")
	eq(v["reclaimer"]["threshold"], 10, "Reclaimer: soglia = Basi nemiche")
	eq(v["corporations"]["value"], 0, "Corporations: Profits")
	# Nessuna Fazione vince al setup.
	for fid in v.keys():
		eq(v[fid]["won"], false, "%s non vince al setup" % fid)
	# Margini negativi al setup.
	eq(v["marsgov"]["margin"], -22, "margine MarsGov")
	eq(v["red_dust"]["margin"], -18, "margine Red Dust")
	eq(v["reclaimer"]["margin"], -3, "margine Reclaimer")
	eq(module.tiebreak_order()[0], "reclaimer", "le parità vanno ai Reclaimer")
	eq(module.pass_resources("marsgov"), 3, "MarsGov Passa: +3 Risorse")
	eq(module.pass_resources("red_dust"), 1, "Red Dust Passa: +1 Risorsa")


# ===========================================================================
# Fase 3 — mazzo, sequenza di gioco, round periodici
# ===========================================================================

## Stato fresco (lo schieramento iniziale) per i test che modificano la partita.
func fresh() -> GameState:
	var s := GameState.new(gd)
	module.apply_setup(s, "standard")
	return s


func rounds_for(s: GameState, seed_value: int = 12345) -> RDRRounds:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return RDRRounds.new(s, module, r)


func test_deck() -> void:
	print("Mazzo (§3.3)")
	var rng := RandomNumberGenerator.new()
	for seed_value in [1, 2, 99, 12345]:
		rng.seed = seed_value
		var deck := RDRDeck.build(rng)
		eq(deck.size(), 39, "39 carte nel mazzo (seed %d)" % seed_value)
		var seen := {}
		var storms := 0
		for n in deck:
			ok(not seen.has(n), "nessun doppione (carta %d, seed %d)" % [n, seed_value])
			seen[n] = true
			if RDRDeck.is_dust_storm(n):
				storms += 1
		eq(storms, 3, "3 Dust Storm nel mazzo (seed %d)" % seed_value)
		eq(RDRDeck.removed_from_play(deck).size(), 12,
			"12 Eventi fuori dal gioco (seed %d)" % seed_value)
		# Ogni Dust Storm sta nelle 7 carte in fondo alla propria pila da 13:
		# posizioni 6-12, 19-25, 32-38 contando dall'ALTO del mazzo.
		for i in range(deck.size()):
			if not RDRDeck.is_dust_storm(deck[i]):
				continue
			var from_top := deck.size() - 1 - i
			var pile := int(from_top / 13.0)
			var pos_in_pile := from_top - pile * 13
			ok(pos_in_pile >= 6, "Dust Storm nelle ultime 7 della pila %d (pos %d, seed %d)" % [
				pile + 1, pos_in_pile, seed_value])


func test_card_flow() -> void:
	print("Flusso delle carte (§4.0)")
	var s := fresh()
	var r := rounds_for(s)
	r.begin_game()
	eq(s.draw_deck.size(), 37, "37 carte restano nel mazzo dopo le due rivelate")
	ok(s.current_card > 0, "Current Event rivelata")
	ok(r.next_card() > 0, "Next Event rivelata")
	eq(int(s.tracks["flashpoint"]), 0, "Flashpoint ignorato sulle due carte iniziali")

	# La rivelazione della Next Event fa avanzare la traccia Flashpoint.
	var before := int(s.tracks["flashpoint"])
	r.advance_card()
	var revealed := r.next_card()
	if revealed > 0 and not RDRDeck.is_dust_storm(s.current_card):
		var fp: int = int(module.card_flashpoint.get(revealed, 0))
		var after := int(s.tracks["flashpoint"])
		ok(after == mini(before + fp, 5) or after == 0,
			"traccia Flashpoint avanzata di %d (o azzerata dal round)" % fp)


func test_flashpoint_trigger() -> void:
	print("Innesco del Flashpoint Round (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	r.begin_game()
	# Con la traccia a 4, qualsiasi carta di valore ≥1 fa scattare il round.
	s.tracks["flashpoint"] = 4
	var deck_before := s.draw_deck.size()
	var fired := false
	for i in range(12):
		if s.draw_deck.is_empty():
			break
		r.advance_card()
		for line in r.log_lines:
			if line.contains("Flashpoint Round"):
				fired = true
		if fired:
			break
	ok(fired, "il Flashpoint Round scatta entro poche carte")
	eq(int(s.tracks["flashpoint"]), 0, "traccia azzerata dopo il round")
	ok(deck_before > s.draw_deck.size(), "il mazzo si consuma")


func test_haboob() -> void:
	print("Haboob (§4.0)")
	var s := fresh()
	var r := rounds_for(s)
	r.begin_game()
	# Forziamo una Dust Storm come Next Event.
	s.tracks["next_card"] = 49
	r._update_haboob()
	eq(r.haboob_active(), true, "Haboob attivo con una Dust Storm in arrivo")
	s.tracks["next_card"] = 1
	r._update_haboob()
	eq(r.haboob_active(), false, "Haboob spento con un Evento normale")


func test_sequence() -> void:
	print("Sequenza della carta (§4.1)")
	var s := fresh()
	# Carta 1: ordine stampato M C D R.
	var seq := RDRSequence.new(s, module, gd.card(1))
	eq(seq.pending_faction(), "marsgov", "1ª Disponibile = MarsGov")
	eq(seq.is_first_slot(), true, "primo slot")
	var first_opts := seq.legal_actions()
	ok(first_opts.has(CoinEnums.ActionType.OPERATION), "la 1ª può fare Operazione")
	ok(first_opts.has(CoinEnums.ActionType.OPERATION_WITH_SPECIAL), "…con Attività Speciale")
	ok(first_opts.has(CoinEnums.ActionType.EVENT), "…o l'Evento")
	ok(first_opts.has(CoinEnums.ActionType.PASS), "…o Passare")

	# §4.1: dopo Operazione+SA la 2ª può fare Operazione Limitata OPPURE l'Evento
	# (nel COIN standard solo l'Evento: è la deviazione gestita da RDRSequence).
	seq.act(CoinEnums.ActionType.OPERATION_WITH_SPECIAL)
	eq(seq.pending_faction(), "corporations", "2ª Disponibile = Corporations")
	var second_opts := seq.legal_actions()
	ok(second_opts.has(CoinEnums.ActionType.LIMITED_OPERATION), "la 2ª può fare Operazione Limitata")
	ok(second_opts.has(CoinEnums.ActionType.EVENT), "…oppure l'Evento")
	ok(not second_opts.has(CoinEnums.ActionType.OPERATION), "…ma non un'Operazione piena")

	# Dopo due Fazioni che agiscono la carta è conclusa.
	seq.act(CoinEnums.ActionType.LIMITED_OPERATION)
	eq(seq.is_done(), true, "carta conclusa dopo due azioni")
	seq.finish()
	eq(s.eligibility["marsgov"], CoinEnums.Eligibility.INELIGIBLE, "MarsGov non più Disponibile")
	eq(s.eligibility["red_dust"], CoinEnums.Eligibility.ELIGIBLE, "Red Dust resta Disponibile")

	# Operazione senza SA: la 2ª può solo l'Operazione Limitata.
	var s2 := fresh()
	var seq2 := RDRSequence.new(s2, module, gd.card(1))
	seq2.act(CoinEnums.ActionType.OPERATION)
	eq(seq2.legal_actions(), [CoinEnums.ActionType.PASS, CoinEnums.ActionType.LIMITED_OPERATION],
		"dopo Operazione secca: solo Limitata (o Passo)")

	# Evento: la 2ª torna a poter fare un'Operazione piena.
	var s3 := fresh()
	var seq3 := RDRSequence.new(s3, module, gd.card(1))
	seq3.act(CoinEnums.ActionType.EVENT)
	ok(seq3.legal_actions().has(CoinEnums.ActionType.OPERATION_WITH_SPECIAL),
		"dopo l'Evento: Operazione con Attività Speciale")


func test_pass() -> void:
	print("Passo (§4.1)")
	var s := fresh()
	var seq := RDRSequence.new(s, module, gd.card(1))
	var mg_before := s.get_resources("marsgov")
	seq.act_pass()
	eq(s.get_resources("marsgov"), mg_before + 3, "MarsGov Passa: +3 Risorse")
	eq(seq.pending_faction(), "corporations", "tocca alla Fazione successiva")
	seq.act_pass()
	ok(seq.pass_effects.has("aldrin_cycler"), "il Passo delle Corporations attiva l'Aldrin Cycler")
	var rd_before := s.get_resources("red_dust")
	seq.act_pass()
	eq(s.get_resources("red_dust"), rd_before + 1, "Red Dust Passa: +1 Risorsa")
	seq.act_pass()
	ok(seq.pass_effects.has("draw_asset"), "il Passo dei Reclaimer dà una pescata di Asset")
	eq(seq.is_done(), true, "tutte le Fazioni hanno Passato: carta conclusa")
	seq.finish()
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		eq(s.eligibility[fid], CoinEnums.Eligibility.ELIGIBLE,
			"chi Passa resta Disponibile (%s)" % fid)


func test_reclaimer_order() -> void:
	print("Ordine dei Reclaimer (§4.1)")
	var s := fresh()
	# Carta 1 = M C D R: servono 3 scarti per diventare 1ª Disponibile.
	var seq := RDRSequence.new(s, module, gd.card(1))
	eq(seq.reclaimer_cost_to_reach(1), 3, "3 Asset per essere 1ª con tutti Disponibili")
	eq(seq.reclaimer_discard(3), true, "scarto accettato")
	eq(seq.pending_faction(), "reclaimer", "i Reclaimer agiscono per primi")

	# Con due Fazioni già Non Disponibili bastano meno scarti (l'avanzamento è
	# sull'ordine STAMPATO, ma il rango si conta fra le sole Disponibili).
	var s2 := fresh()
	s2.eligibility["corporations"] = CoinEnums.Eligibility.INELIGIBLE
	s2.eligibility["red_dust"] = CoinEnums.Eligibility.INELIGIBLE
	var seq2 := RDRSequence.new(s2, module, gd.card(1))
	eq(seq2.pending_faction(), "marsgov", "senza scarti tocca a MarsGov")
	eq(seq2.reclaimer_cost_to_reach(1), 3, "servono comunque 3 scarti per superare M C D")
	eq(seq2.reclaimer_cost_to_reach(2), 0, "…ma sono già 2ª Disponibili senza scartare")
	eq(seq2.reclaimer_discard(4), true, "il massimo è 3 scarti")
	eq(seq2.reclaimer_shift, 3, "scarti limitati a 3")


func test_aldrin_cycler() -> void:
	print("Aldrin Cycler (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	var mg_before := s.get_resources("marsgov")
	r.aldrin_cycler()
	# Transit → Phobos: le 3 Supply valgono 9 Risorse.
	eq(s.get_resources("marsgov"), mg_before + 9, "3 Supply su Phobos: +9 Risorse MarsGov")
	eq(module.count_in(s, "phobos", "eg_troop"), 6, "Phobos: 4+2 Truppe EG")
	eq(module.count_in(s, "phobos", "security"), 3, "Phobos: 2+1 Security")
	eq(module.count_in(s, "orbit", "satellite"), 2, "il Satellite arrivato passa in Orbit")
	eq(module.marker(s, "phobos", "supply"), 0, "nessuna Supply resta su Phobos")
	# Una Popolazione parte da Earth verso Transit.
	eq(module.marker(s, "earth", "population"), 0, "la Popolazione lascia Earth")
	eq(module.marker(s, "transit", "population"), 1, "…ed è in Transit")
	# Il Controller (Corporations al setup) spedisce 5 pezzi: le proprie unità prima.
	eq(module.count_in(s, "earth", "security"), 0, "la Security parte da Earth")
	eq(module.count_in(s, "earth", "specops"), 0, "lo SpecOps parte da Earth")
	eq(module.count_in(s, "transit", "satellite"), 2, "i 2 Satelliti sono in Transit")
	eq(module.count_in(s, "earth", "eg_troop"), 2, "le Truppe EG restano su Earth (ultima priorità)")


func test_corporate_casualties() -> void:
	print("Corporate Casualties (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	s.tracks["profits"] = 20
	s.spaces["casualties"].add_piece("corporations", "corp_base", 2, "basic")
	s.spaces["casualties"].add_piece("corporations", "security", 5, "")
	s.spaces["casualties"].add_piece("corporations", "specops", 2, "hidden")
	r.corporate_casualties()
	# 2 Basi + (5 Security / 2 arrotondato per difetto) = 2 + 2 = 4 Profits persi.
	eq(int(s.tracks["profits"]), 16, "−4 Profits (2 Basi + 2 coppie di Security)")
	eq(module.count_in(s, "casualties", "security"), 0, "le Casualties si svuotano")
	eq(module.available(s, "corp_base"), 8, "le Basi tornano fra le Disponibili (6+2)")


func test_eg_confidence_phase() -> void:
	print("Fase EarthGov Confidence (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	# Al setup il marcatore è su EG−: scende di una casella (3 → 2).
	r.earthgov_confidence_phase()
	eq(int(s.tracks["eg_confidence"]), 2, "EG− fa scendere di una casella")
	eq(module.eg_controller(s), "corporations", "il Controller resta Corporations")
	# La casella 2 dà 6 Truppe EG, 1 Supply e 0 Popolazione su Earth.
	eq(module.count_in(s, "earth", "eg_troop"), 8, "2 già presenti + 6 rinforzi")
	eq(module.marker(s, "earth", "supply"), 2, "1 già presente + 1 rinforzo")

	# Salendo da 5 a 6 il controllo passa a MarsGov.
	var s2 := fresh()
	var r2 := rounds_for(s2)
	s2.tracks["eg_confidence"] = 5
	s2.tracks["eg_side"] = 1
	eq(module.eg_controller(s2), "corporations", "casella 5: Controller Corporations")
	r2.earthgov_confidence_phase()
	eq(int(s2.tracks["eg_confidence"]), 6, "EG+ fa salire di una casella")
	eq(module.eg_controller(s2), "marsgov", "casella 6: il controllo passa a MarsGov")

	# Fondo traccia: le Truppe EG lasciano Mars.
	var s3 := fresh()
	var r3 := rounds_for(s3)
	s3.tracks["eg_confidence"] = 1
	s3.tracks["eg_side"] = -1
	module.place_from_available(s3, "europa", "eg_troop", 2)
	r3.earthgov_confidence_phase()
	eq(int(s3.tracks["eg_confidence"]), 0, "il marcatore tocca il fondo")
	eq(module.eg_controller(s3), "", "nessun EarthGov Controller")
	eq(module.count_in(s3, "europa", "eg_troop"), 0, "le Truppe EG lasciano la mappa")


func test_terraforming() -> void:
	print("Terraforming (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	s.tracks["profits"] = 10
	# Due Basi Terraforming nello stesso Deserto: 2 + 1 Profits.
	s.spaces["marth"].remove_piece("corporations", "corp_base", 1, "basic")
	s.spaces["marth"].add_piece("corporations", "corp_base", 2, "terraforming")
	# Un Conversion Center in un Deserto costa 1 Profit.
	s.spaces["ascraeus_mons"].remove_piece("reclaimer", "cr_base", 1, "basic")
	s.spaces["ascraeus_mons"].add_piece("reclaimer", "cr_base", 1, "conversion_center")
	r.terraforming()
	eq(int(s.tracks["profits"]), 12, "+3 dalle Terraforming, −1 dal Conversion Center")


func test_attrition() -> void:
	print("Attrition (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	# Al setup nessun Deserto perde pezzi: dove sono Spopolati o c'è una Base COIN,
	# o ci sono solo forze immuni (Reclaimer).
	var mg_before := 0
	for sid in module.mars_spaces(s):
		mg_before += module.count_in(s, sid, "mg_troop")
	r.attrition()
	var mg_after := 0
	for sid in module.mars_spaces(s):
		mg_after += module.count_in(s, sid, "mg_troop")
	eq(mg_after, mg_before, "lo schieramento iniziale non subisce Attrition")

	# Deserto Spopolato senza Base COIN: perde 1 Truppa MG e 1 Security.
	var s2 := fresh()
	var r2 := rounds_for(s2)
	module.place_from_available(s2, "ascraeus_mons", "mg_troop", 2)
	module.place_from_available(s2, "ascraeus_mons", "security", 2)
	var cr_before := module.count_in(s2, "ascraeus_mons", "cr_rebel")
	r2.attrition()
	eq(module.count_in(s2, "ascraeus_mons", "mg_troop"), 1, "−1 Truppa MarsGov")
	eq(module.count_in(s2, "ascraeus_mons", "security"), 1, "−1 Security")
	eq(module.count_in(s2, "ascraeus_mons", "cr_rebel"), cr_before,
		"i Ribelli Reclaimer sono immuni all'Attrition")
	eq(module.count_in(s2, "casualties", "security"), 1, "la Security va nelle Casualties")

	# Con una Base COIN nello stesso Deserto non si perde nulla.
	var s3 := fresh()
	var r3 := rounds_for(s3)
	module.place_from_available(s3, "ascraeus_mons", "mg_troop", 1)
	module.place_from_available(s3, "ascraeus_mons", "mg_base", 1)
	r3.attrition()
	eq(module.count_in(s3, "ascraeus_mons", "mg_troop"), 1, "la Base COIN protegge dall'Attrition")


func test_conversion() -> void:
	print("Conversion (§4.2)")
	var s := fresh()
	var r := rounds_for(s)
	# New Córdoba è Popolata: con un Conversion Center arriva un CR Rebel.
	s.spaces["new_cordoba"].remove_piece("reclaimer", "cr_base", 1, "basic")
	s.spaces["new_cordoba"].add_piece("reclaimer", "cr_base", 1, "conversion_center")
	var before := module.count_in(s, "new_cordoba", "cr_rebel")
	r.conversion()
	eq(module.count_in(s, "new_cordoba", "cr_rebel"), before + 1, "+1 CR Rebel")
	# La Wilderness è sempre Spopolata: nessun reclutamento.
	var s2 := fresh()
	var r2 := rounds_for(s2)
	s2.spaces["wilderness"].remove_piece("reclaimer", "cr_base", 1, "basic")
	s2.spaces["wilderness"].add_piece("reclaimer", "cr_base", 1, "conversion_center")
	var w_before := module.count_in(s2, "wilderness", "cr_rebel")
	r2.conversion()
	eq(module.count_in(s2, "wilderness", "cr_rebel"), w_before, "Wilderness Spopolata: nessun CR Rebel")


func test_storm_table() -> void:
	print("Tabella delle tempeste (§3.2)")
	var s := fresh()
	var r := rounds_for(s)
	# Ogni combinazione dei due dadi deve indicare uno spazio esistente.
	var hit := {}
	for white in range(1, 7):
		for black in range(1, 7):
			var sid := r.space_for_roll(white, black)
			ok(sid != "", "tiro %d/%d mappato su uno spazio" % [white, black])
			if sid != "":
				hit[sid] = true
	eq(hit.size(), 23, "i 23 spazi settoriali sono tutti raggiungibili")
	ok(not hit.has("wilderness"), "la Wilderness non è nella tabella")
	# I settori doppi: 1 e 2 sono Arabia Terra, 5 e 6 Hellas Planitia.
	eq(r.space_for_roll(1, 1), r.space_for_roll(2, 1), "d6 bianco 1 e 2: stesso settore")
	eq(r.space_for_roll(5, 5), r.space_for_roll(6, 5), "d6 bianco 5 e 6: stesso settore")
	eq(r.space_for_roll(1, 1), "new_cordoba", "1/1 = New Córdoba")
	eq(r.space_for_roll(3, 1), "ascraeus_mons", "3/1 = Ascraeus Mons")
	eq(r.space_for_roll(4, 1), "europa", "4/1 = Europa")
	# Hellas Chaos occupa due risultati del dado nero.
	eq(r.space_for_roll(5, 3), "hellas_chaos", "5/3 = Hellas Chaos")
	eq(r.space_for_roll(5, 4), "hellas_chaos", "5/4 = Hellas Chaos")


func test_storm_rolls() -> void:
	print("Tiri delle tempeste (§4.2)")
	var s := fresh()
	var r := rounds_for(s, 7)
	r.storm_rolls(4)
	ok(r.storms_on_map() > 0, "sono comparse tempeste")
	ok(r.storms_on_map() <= 4, "al massimo un marker per tiro")
	# Il limite di 6 marker sulla mappa non si supera mai.
	var s2 := fresh()
	var r2 := rounds_for(s2, 11)
	r2.storm_rolls(40)
	eq(r2.storms_on_map(), 6, "limite di 6 marker tempesta")

	# Un secondo risultato sullo stesso spazio porta la tempesta a Raging.
	var s3 := fresh()
	var r3 := rounds_for(s3)
	module.set_marker(s3, "radau", "storm", 1)
	eq(module.storm(s3, "radau"), 1, "tempesta in arrivo su Radau")
	r3._reclaimer_strike("radau")
	eq(module.count_in(s3, "radau", "rd_rebel"), 0,
		"i Reclaimer rimuovono una forza nemica sul secondo risultato")

	# Fase tempeste: le Raging spariscono, le Approaching diventano Raging.
	var s4 := fresh()
	var r4 := rounds_for(s4)
	module.set_marker(s4, "radau", "storm", 2)
	module.set_marker(s4, "marth", "storm", 1)
	s4.tracks["next_card"] = -1
	r4.dust_storm_phase()
	eq(module.storm(s4, "radau"), 0, "la Raging Storm si dissolve")
	eq(module.storm(s4, "marth"), 2, "l'Approaching diventa Raging")


func test_dust_storm_resources() -> void:
	print("Dust Storm Round — Resources (§4.3)")
	var s := fresh()
	var r := rounds_for(s)
	var mg := s.get_resources("marsgov")
	var rd := s.get_resources("red_dust")
	r.resources_phase()
	# MarsGov: Popolazione degli spazi con Controllo COIN e senza Opposizione
	# (Europa 2 + Tenzing 3 + Tereshkova 2 + Shenzhou 3 = 10).
	eq(s.get_resources("marsgov"), mg + 10, "MarsGov +10")
	# Red Dust: Popolazione in Opposizione Attiva (Sharma 2) + 5 Basi RD.
	eq(s.get_resources("red_dust"), rd + 7, "Red Dust +7")
	# Corporations: 2 Profits per Base in un Labirinto (solo Shenzhou).
	eq(int(s.tracks["profits"]), 2, "Corporations +2 Profits")


func test_dust_storm_round() -> void:
	print("Dust Storm Round completo (§4.3)")
	var s := fresh()
	var r := rounds_for(s)
	r.begin_game()
	var mg_before := s.get_resources("marsgov")
	r.dust_storm_round()
	eq(int(s.tracks["dust_storm_rounds"]), 1, "primo Dust Storm Round contato")
	eq(int(s.tracks.get("game_over", 0)), 0, "nessuno vince al primo round")
	# Displaced Population: 4 marker → −6 Risorse MarsGov, poi +10 dalla fase Risorse.
	eq(s.get_resources("marsgov"), mg_before - 6 + 10, "penalità Displaced + entrate")
	# Redeploy: le Truppe EG lasciano Mars.
	for sid in module.mars_spaces(s):
		eq(module.count_in(s, sid, "eg_troop"), 0, "nessuna Truppa EG su Mars (%s)" % sid)
	# Il Redeploy spazza via tutte le tempeste; quelle presenti a fine round sono
	# state tirate DOPO, nella fase di Reset (§4.3), sui Flashpoint delle due
	# nuove carte — quindi non se ne pretende zero qui.
	var s_storm := fresh()
	var r_storm := rounds_for(s_storm)
	module.set_marker(s_storm, "radau", "storm", 2)
	module.set_marker(s_storm, "marth", "storm", 1)
	r_storm.redeploy_phase()
	eq(r_storm.storms_on_map(), 0, "il Redeploy rimuove tutti i marker tempesta")
	# Reset: tutti Disponibili, Ribelli Nascosti, nuove carte rivelate.
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		eq(s.eligibility[fid], CoinEnums.Eligibility.ELIGIBLE, "%s di nuovo Disponibile" % fid)
	var active := 0
	for sid in s.spaces.keys():
		for type_id in ["rd_rebel", "cr_rebel", "specops"]:
			active += module.count_in(s, sid, type_id, "active")
	eq(active, 0, "tutti i Ribelli e gli SpecOps sono Nascosti")
	ok(s.current_card > 0, "nuova Current Event rivelata")
	eq(module.marker(s, "earth", "population"),
		module.eg_confidence_value(s), "la Popolazione su Earth pareggia la EG Confidence")


func test_game_end() -> void:
	print("Fine partita (§2.0/§4.3)")
	# Terzo Dust Storm Round senza vincitori: vince il margine più alto.
	var s := fresh()
	var r := rounds_for(s)
	r.begin_game()
	s.tracks["dust_storm_rounds"] = 2
	r.dust_storm_round()
	eq(int(s.tracks["dust_storm_rounds"]), 3, "terzo Dust Storm Round")
	eq(int(s.tracks["game_over"]), 1, "la partita finisce")
	ok(String(s.tracks.get("winner", "")) != "", "un vincitore è determinato")

	# Vittoria anticipata: Profits oltre 36 al check.
	var s2 := fresh()
	var r2 := rounds_for(s2)
	r2.begin_game()
	s2.tracks["profits"] = 45
	var over := r2.victory_phase()
	eq(over, true, "il check di vittoria chiude la partita")
	eq(String(s2.tracks.get("winner", "")), "corporations", "vincono le Corporations")
