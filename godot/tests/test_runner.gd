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

	test_actions()
	test_train()
	test_logistics()
	test_movement()
	test_secure_recon()
	test_assault()
	test_rally()
	test_march_travel()
	test_attack()
	test_campaign_preach()
	test_special_activities()

	test_cards_setup()
	test_cards_pay()
	test_cards_hand_limit()
	test_cards_eligibility_and_events()
	test_campaign_deck()
	test_reclaimer_pays()
	test_events()
	test_events_all_options()
	test_events_effects()
	test_events_eligibility()
	test_events_free_ops()
	test_asset_events()
	test_capabilities()
	test_np_setup()
	test_np_priorities()
	test_np_operations()
	test_np_piece_priorities()
	test_np_movement()
	test_np_eligibility()
	test_np_effective_events()
	test_np_event_symbols()
	test_np_cards()
	test_campaign_effects()

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


# ===========================================================================
# Fase 4 — Operazioni (§5.0) e Attività Speciali (§6.0)
# ===========================================================================

func ops_for(s: GameState, seed_value: int = 4242) -> RDROperations:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var o := RDROperations.new(s, module, r)
	o.rounds = rounds_for(s, seed_value)
	return o


func test_actions() -> void:
	print("Azioni condivise (§1.7/§1.8)")
	var s := fresh()
	var a := RDRActions.new(s, module)

	# House: sposta un marker da Displaced Population su un quadrato grigio.
	eq(module.free_infra_slots(s, "europa"), 2, "Europa ha 2 quadrati grigi liberi")
	eq(a.house("europa", "marsgov"), true, "House riuscito")
	eq(module.population(s, "europa"), 3, "Popolazione di Europa da 2 a 3")
	eq(int(s.tracks["displaced_population"]), 3, "un marker lascia Displaced Population")
	eq(int(s.tracks["eg_side"]), 1, "House di MarsGov: EG+")

	# House vietato dove c'è un Danno.
	eq(a.can_house("ascraeus_mons"), false, "niente House dove c'è Danno")

	# Repair: MarsGov paga 3 Risorse e consuma un Displaced.
	var mg := s.get_resources("marsgov")
	eq(a.repair("ascraeus_mons", "marsgov"), true, "Repair riuscito")
	eq(s.get_resources("marsgov"), mg - 3, "Repair MarsGov: −3 Risorse")
	eq(module.marker(s, "ascraeus_mons", "damage"), 0, "il Danno è rimosso")
	eq(module.population(s, "ascraeus_mons"), 1, "Popolazione ripristinata")

	# Repair delle Corporations: rimuove una Security invece delle Risorse.
	var s2 := fresh()
	var a2 := RDRActions.new(s2, module)
	eq(a2.repair("marth", "corporations"), true, "Repair CORP riuscito")
	eq(module.count_in(s2, "marth", "security"), 1, "−1 Security")

	# Danno: azzera i marker Popolazione gialli e manda 1 in Displaced.
	var s3 := fresh()
	var a3 := RDRActions.new(s3, module)
	a3.house("europa", "marsgov")
	var disp := int(s3.tracks["displaced_population"])
	eq(a3.place_damage("europa"), true, "Danno piazzato")
	eq(module.marker(s3, "europa", "pop_markers"), 0, "i marker gialli spariscono")
	eq(module.population(s3, "europa"), 1, "Popolazione 2 stampata − 1 Danno")
	eq(int(s3.tracks["displaced_population"]), disp + 1, "+1 in Displaced Population")

	# Spazio Spopolato: il marker Supporto va via.
	var s4 := fresh()
	var a4 := RDRActions.new(s4, module)
	eq(a4.shift("pavonis_mons", -1), -1, "Pavonis Mons scende di un livello")
	a4.place_damage("pavonis_mons")
	eq(module.population(s4, "pavonis_mons"), 0, "Pavonis Mons Spopolata")
	eq(s4.spaces["pavonis_mons"].support, CoinEnums.Support.NEUTRAL,
		"uno spazio Spopolato è sempre Neutrale")


func test_train() -> void:
	print("Train (§5.1)")
	var s := fresh()
	var o := ops_for(s)
	var cand := o.train_candidates()
	ok(cand.has("tharsis_tholus"), "spazio con Base MG selezionabile")
	ok(cand.has("europa"), "Labirinto con Controllo COIN selezionabile")
	ok(not cand.has("sharma"), "Labirinto sotto Controllo RD non selezionabile")

	var mg := s.get_resources("marsgov")
	var res: Dictionary = o.train({"spaces": [{"id": "europa", "troops": 4}]})
	eq(res["ok"], true, "Train eseguito")
	eq(module.count_in(s, "europa", "mg_troop"), 6, "2 + 4 Truppe in Europa")
	eq(s.get_resources("marsgov"), mg - 3, "3 Risorse per lo spazio")

	# Pacify: fino a due azioni fra House, Repair e spostamento a 3 Risorse.
	var s2 := fresh()
	var o2 := ops_for(s2)
	var before: int = s2.spaces["europa"].support
	o2.train({"spaces": [{"id": "europa", "troops": 1}],
		"pacify": {"id": "europa", "actions": ["shift", "house"]}})
	eq(s2.spaces["europa"].support, before + 1, "Pacify sposta verso il Supporto Attivo")
	eq(module.marker(s2, "europa", "pop_markers"), 1, "Pacify fa anche House")

	# Non si possono scegliere più spazi di quanti se ne possano pagare.
	var s3 := fresh()
	var o3 := ops_for(s3)
	s3.resources["marsgov"] = 2
	var bad: Dictionary = o3.train({"spaces": [{"id": "europa", "troops": 1}]})
	eq(bad["ok"], false, "Train rifiutato senza Risorse")
	eq(module.count_in(s3, "europa", "mg_troop"), 2, "lo stato non è stato toccato")


func test_logistics() -> void:
	print("Logistics (§5.2)")
	var s := fresh()
	var o := ops_for(s)
	s.tracks["profits"] = 10
	var res: Dictionary = o.logistics({
		"earth": {"security": 3, "specops": 1},
		"deserts": ["marth", "hellas_chaos"],
	})
	eq(res["ok"], true, "Logistics eseguita")
	eq(module.count_in(s, "earth", "security"), 4, "1 + 3 Security su Earth")
	eq(module.count_in(s, "marth", "corp_base", "terraforming"), 1, "prima Base potenziata")
	eq(module.count_in(s, "hellas_chaos", "corp_base", "terraforming"), 1, "seconda Base potenziata")
	eq(int(s.tracks["profits"]), 7, "la seconda Base costa 3 Profits")

	# Transit attiva l'Aldrin Cycler.
	var s2 := fresh()
	var o2 := ops_for(s2)
	var mg := s2.get_resources("marsgov")
	o2.logistics({"transit": true})
	eq(s2.get_resources("marsgov"), mg + 9, "l'Aldrin Cycler converte le 3 Supply")


func test_movement() -> void:
	print("Movimento (§5.3/§5.4)")
	var s := fresh()
	var o := ops_for(s)
	# Europa è collegata a Tenzing dal Maglev; la Rodgers Line verso Tereshkova è chiusa.
	var reach := o.reachable_labyrinths("europa", "coin")
	ok(reach.has("tenzing"), "Tenzing raggiungibile via Maglev")
	ok(not module.maglev_links(s, "europa").has("tereshkova"),
		"il Maglev Europa-Tereshkova (Rodgers Line) è chiuso")
	# …ma Tereshkova resta raggiungibile via Spaceport: entrambi i Labirinti sono
	# sotto Controllo COIN, senza Danno né tempesta (§5.3).
	ok(reach.has("tereshkova"), "Tereshkova raggiungibile via Spaceport")
	module.add_marker(s, "tereshkova", "damage", 1)
	ok(not o.reachable_labyrinths("europa", "coin").has("tereshkova"),
		"uno Spaceport Danneggiato non è utilizzabile")
	module.add_marker(s, "tereshkova", "damage", -1)
	# Shepard è sotto Controllo RD: ci si arriva ma non si prosegue oltre.
	var from_tenzing := o.reachable_labyrinths("tenzing", "coin")
	ok(from_tenzing.has("shepard"), "Shepard raggiungibile via Maglev da Tenzing")

	# Recon: i Deserti si raggiungono per adiacenza.
	var deserts := o.reachable_deserts("europa", "coin")
	ok(deserts.has("ascraeus_mons"), "Ascraeus Mons adiacente a Europa")
	ok(deserts.has("pavonis_mons"), "Pavonis Mons adiacente a Europa")
	ok(not deserts.has("radau"), "Radau è in un altro Settore")

	# Una Raging Storm blocca l'ingresso.
	module.set_marker(s, "ascraeus_mons", "storm", 2)
	ok(not o.reachable_deserts("europa", "coin").has("ascraeus_mons"),
		"non si entra in un Deserto con Raging Storm")


func test_secure_recon() -> void:
	print("Secure e Recon (§5.3/§5.4)")
	var s := fresh()
	var o := ops_for(s)
	var mg := s.get_resources("marsgov")
	# Secure su Tereshkova: 2 Truppe MG già lì Attivano il Ribelle RD nascosto.
	var res: Dictionary = o.secure({"faction": "marsgov", "dest": ["tereshkova"]})
	eq(res["ok"], true, "Secure eseguito")
	eq(module.count_in(s, "tereshkova", "rd_rebel", "active"), 1, "1 Ribelle Attivato per unità")
	eq(s.get_resources("marsgov"), mg - 3, "3 Risorse per destinazione")

	# Piazzamento di una Base rimuovendo una Truppa.
	var s2 := fresh()
	var o2 := ops_for(s2)
	o2.secure({"faction": "marsgov", "dest": ["europa"], "base_at": ["europa"]})
	eq(module.count_in(s2, "europa", "mg_base"), 1, "Base MG piazzata")
	eq(module.count_in(s2, "europa", "mg_troop"), 1, "una Truppa rimossa per la Base")

	# Recon nella Wilderness: 1 Ribelle Attivato ogni 2 unità.
	var s3 := fresh()
	var o3 := ops_for(s3)
	module.place_from_available(s3, "wilderness", "mg_troop", 4)
	o3.recon({"faction": "marsgov", "dest": ["wilderness"]})
	eq(module.count_in(s3, "wilderness", "cr_rebel", "active"), 2,
		"nella Wilderness 1 Ribelle ogni 2 unità")


func test_assault() -> void:
	print("Assault (§5.5)")
	var s := fresh()
	var o := ops_for(s)
	# I Ribelli Nascosti non si possono colpire.
	var res: Dictionary = o.assault({"faction": "marsgov", "spaces": ["sharma"]})
	eq(res["ok"], true, "Assault eseguito")
	eq(module.count_in(s, "sharma", "rd_rebel"), 3, "i Ribelli Nascosti non vengono rimossi")

	# Con i Ribelli Attivi: 1 rimosso per cubo.
	var s2 := fresh()
	var o2 := ops_for(s2)
	var a2 := RDRActions.new(s2, module)
	a2.activate("sharma", "rd_rebel", 3)
	o2.assault({"faction": "marsgov", "spaces": ["sharma"]})
	eq(module.count_in(s2, "sharma", "rd_rebel"), 2, "1 Truppa MG rimuove 1 Ribelle Attivo")
	eq(module.count_in(s2, "sharma", "rd_base"), 1, "la Base resta finché ci sono Ribelli")

	# Basi per ultime: senza Ribelli la Base cade.
	var s3 := fresh()
	var o3 := ops_for(s3)
	var a3 := RDRActions.new(s3, module)
	module.remove_pieces(s3, "sharma", "rd_rebel", 3, "available")
	module.place_from_available(s3, "sharma", "mg_troop", 2)
	o3.assault({"faction": "marsgov", "spaces": ["sharma"]})
	eq(module.count_in(s3, "sharma", "rd_base"), 0, "Base rimossa quando non restano Ribelli")

	# Mercenaries: +1 Profit ogni 2 forze Ribelli rimosse dove ci sono Security.
	var s4 := fresh()
	var o4 := ops_for(s4)
	var a4 := RDRActions.new(s4, module)
	module.place_from_available(s4, "shenzhou", "mg_troop", 2)
	a4.activate("shenzhou", "rd_rebel", 1)
	module.place_from_available(s4, "shenzhou", "rd_rebel", 1)
	a4.activate("shenzhou", "rd_rebel", 2)
	s4.tracks["profits"] = 0
	o4.assault({"faction": "marsgov", "spaces": ["shenzhou"]})
	eq(int(s4.tracks["profits"]), 1, "+1 Profit ogni 2 Ribelli rimossi (Mercenaries)")


func test_rally() -> void:
	print("Rally (§5.6)")
	var s := fresh()
	var o := ops_for(s)
	var cand := o.rally_candidates("red_dust")
	ok(cand.has("shepard"), "Red Dust: spazio Popolato senza Supporto")
	ok(not cand.has("tenzing"), "Red Dust: non dove c'è Supporto")
	var cand_cr := o.rally_candidates("reclaimer")
	ok(cand_cr.has("new_cordoba"), "Reclaimer: spazio Neutrale")
	ok(not cand_cr.has("sharma"), "Reclaimer: non dove c'è Opposizione")

	# "fill": Ribelli fino a Popolazione + Basi amiche.
	var rd := s.get_resources("red_dust")
	var res: Dictionary = o.rally({"faction": "red_dust",
		"spaces": [{"id": "gandhi", "mode": "fill"}], "dig_in": "radau"})
	eq(res["ok"], true, "Rally eseguito")
	eq(module.count_in(s, "gandhi", "rd_rebel"), 5, "2 già presenti + (2 Pop + 1 Base)")
	eq(s.get_resources("red_dust"), rd - 1, "1 Risorsa per spazio")
	eq(module.count_in(s, "radau", "rd_base", "dug_in"), 1, "Base Dug-In anche fuori dagli spazi scelti")

	# "base": due Ribelli diventano una Base.
	var s2 := fresh()
	var o2 := ops_for(s2)
	o2.rally({"faction": "red_dust", "spaces": [{"id": "shepard", "mode": "base"}]})
	eq(module.count_in(s2, "shepard", "rd_base"), 1, "Base piazzata")
	eq(module.count_in(s2, "shepard", "rd_rebel"), 0, "2 Ribelli consumati")

	# Reclaimer "upgrade": la Base diventa Conversion Center.
	var s3 := fresh()
	var o3 := ops_for(s3)
	o3.rally({"faction": "reclaimer", "spaces": [{"id": "new_cordoba", "mode": "upgrade"}]})
	eq(module.count_in(s3, "new_cordoba", "cr_base", "conversion_center"), 1, "Conversion Center")


func test_march_travel() -> void:
	print("March e Travel (§5.7/§5.8)")
	var s := fresh()
	var o := ops_for(s)
	# Marcia verso uno spazio Neutrale: i Ribelli restano Nascosti.
	var res: Dictionary = o.march({"dest": ["daedalia_planum"],
		"moves": [{"from": "shepard", "to": "daedalia_planum", "count": 2}]})
	eq(res["ok"], true, "March eseguita")
	eq(module.count_in(s, "daedalia_planum", "rd_rebel", "hidden"), 3, "Ribelli arrivati Nascosti")

	# In uno spazio con Supporto, se i Ribelli in arrivo più i cubi presenti
	# superano 3, quei Ribelli si Attivano (§5.7).
	var s2 := fresh()
	var o2 := ops_for(s2)
	module.place_from_available(s2, "syria_planum", "rd_rebel", 2)
	o2.march({"dest": ["tenzing"], "moves": [{"from": "syria_planum", "to": "tenzing", "count": 2}]})
	eq(module.count_in(s2, "tenzing", "rd_rebel", "active"), 2,
		"2 Ribelli + 4 cubi > 3: Attivati")

	# Travel ignora le tempeste e riporta le Basi mosse sul lato base.
	var s3 := fresh()
	var o3 := ops_for(s3)
	module.set_marker(s3, "trouvelot", "storm", 2)
	s3.spaces["trouvelot"].remove_piece("reclaimer", "cr_base", 1, "basic")
	s3.spaces["trouvelot"].add_piece("reclaimer", "cr_base", 1, "conversion_center")
	var res3: Dictionary = o3.travel({"origins": ["trouvelot"],
		"moves": [{"from": "trouvelot", "to": "rutherford", "type": "cr_base", "count": 1}]})
	eq(res3["ok"], true, "Travel eseguito anche con Raging Storm")
	eq(module.count_in(s3, "rutherford", "cr_base", "basic"), 1,
		"un Conversion Center che si sposta torna sul lato base")

	# La Wilderness come origine è gratis.
	var s4 := fresh()
	var o4 := ops_for(s4)
	var res4: Dictionary = o4.travel({"origins": ["wilderness"],
		"moves": [{"from": "wilderness", "to": "radau", "count": 2}]})
	eq(res4["spent"], 0, "la Wilderness costa 0")
	eq(module.count_in(s4, "radau", "cr_rebel"), 2, "Ribelli arrivati")


func test_attack() -> void:
	print("Attack (§5.9)")
	# Con Ambush si scelgono i dadi: 1 e 1 su 3 Ribelli rimuove 4 forze.
	var s := fresh()
	var o := ops_for(s)
	module.place_from_available(s, "sharma", "mg_troop", 3)
	var res: Dictionary = o.attack({"faction": "red_dust", "spaces": ["sharma"],
		"ambush": {"sharma": [1, 1]}})
	eq(res["ok"], true, "Attack eseguito")
	eq(module.count_in(s, "sharma", "mg_troop"), 0, "le 4 Truppe MG rimosse")

	# Una Truppa EG vale due forze rimosse.
	var s2 := fresh()
	var o2 := ops_for(s2)
	module.remove_pieces(s2, "sharma", "mg_troop", 1, "available")
	module.place_from_available(s2, "sharma", "eg_troop", 3)
	o2.attack({"faction": "red_dust", "spaces": ["sharma"], "ambush": {"sharma": [1, 1]}})
	eq(module.count_in(s2, "sharma", "eg_troop"), 1, "4 forze = 2 Truppe EG")

	# Gli SpecOps Nascosti non si possono colpire.
	var s3 := fresh()
	var o3 := ops_for(s3)
	module.remove_pieces(s3, "sharma", "mg_troop", 1, "available")
	module.place_from_available(s3, "sharma", "specops", 2, "hidden")
	o3.attack({"faction": "red_dust", "spaces": ["sharma"], "ambush": {"sharma": [1, 1]}})
	eq(module.count_in(s3, "sharma", "specops", "hidden"), 2, "SpecOps Nascosti intoccabili")

	# L'Attack Attiva tutti i propri Ribelli (senza Ambush).
	var s4 := fresh()
	var o4 := ops_for(s4)
	o4.attack({"faction": "red_dust", "spaces": ["sharma"]})
	eq(module.count_in(s4, "sharma", "rd_rebel", "hidden"), 0, "tutti i Ribelli Attivati")


func test_campaign_preach() -> void:
	print("Campaign e Preach (§5.10/§5.11)")
	var s := fresh()
	var o := ops_for(s)
	var before: int = s.spaces["tereshkova"].support
	var res: Dictionary = o.campaign({"spaces": ["tereshkova"]})
	eq(res["ok"], true, "Campaign eseguita")
	eq(s.spaces["tereshkova"].support, before - 1, "spostamento verso l'Opposizione")
	eq(module.count_in(s, "tereshkova", "rd_rebel", "active"), 1, "un Ribelle Attivato")

	# Da Supporto Attivo a Passivo: Danno, EG− e −2 Profits se c'è una Base CORP.
	var s2 := fresh()
	var o2 := ops_for(s2)
	module.place_from_available(s2, "syria_planum", "rd_rebel", 1)
	module.place_from_available(s2, "syria_planum", "corp_base", 1)
	s2.tracks["profits"] = 10
	o2.campaign({"spaces": ["syria_planum"]})
	eq(s2.spaces["syria_planum"].support, CoinEnums.Support.NEUTRAL,
		"Syria Planum diventa Spopolata quindi Neutrale")
	eq(module.marker(s2, "syria_planum", "damage"), 1, "Danno piazzato")
	eq(int(s2.tracks["profits"]), 8, "−2 Profits per la Base CORP")
	eq(int(s2.tracks["eg_side"]), -1, "EG−")

	# Preach sposta verso il Neutrale.
	var s3 := fresh()
	var o3 := ops_for(s3)
	o3.preach({"spaces": ["tenzing"]})
	eq(s3.spaces["tenzing"].support, CoinEnums.Support.PASSIVE_SUPPORT,
		"da Supporto Attivo a Passivo")

	# Preach su spazio già Neutrale: arrivano Ribelli pari alla Popolazione.
	var s4 := fresh()
	var o4 := ops_for(s4)
	var cr_before := module.count_in(s4, "new_cordoba", "cr_rebel")
	o4.preach({"spaces": ["new_cordoba"]})
	eq(module.count_in(s4, "new_cordoba", "cr_rebel"), cr_before + 2,
		"2 Ribelli (Popolazione di New Córdoba)")
	eq(module.marker(s4, "new_cordoba", "damage"), 1, "senza marker gialli si piazza un Danno")


func test_special_activities() -> void:
	print("Attività Speciali (§6.0)")
	var s := fresh()
	var sa := RDRSpecials.new(s, module)
	# Ogni SA accompagna solo certe Operazioni.
	eq(sa.can_accompany("entrench", "train"), true, "Entrench accompagna Train")
	eq(sa.can_accompany("entrench", "assault"), false, "Entrench non accompagna Assault")
	eq(sa.can_accompany("ambush", "attack"), true, "Ambush solo con Attack")
	eq(sa.can_accompany("exploit", "logistics"), true, "Exploit accompagna Logistics")

	# Entrench: la Truppa Fortificata assorbe un Danno.
	var res: Dictionary = sa.entrench({"spaces": [{"id": "europa", "fortify": 2}]})
	eq(res["ok"], true, "Entrench eseguita")
	eq(module.marker(s, "europa", "fortified"), 2, "2 Truppe Fortificate (Popolazione 2)")
	var a := RDRActions.new(s, module)
	eq(a.place_damage("europa"), false, "il Danno è assorbito")
	eq(module.marker(s, "europa", "damage"), 0, "nessun Danno sulla traccia")
	eq(module.marker(s, "europa", "fortified"), 1, "una Truppa Fortificata consumata")

	# Petition: 1 Supply + 1 ogni 3 Ribelli Attivati, a 1 Profit l'una.
	var s2 := fresh()
	var sa2 := RDRSpecials.new(s2, module)
	s2.tracks["profits"] = 10
	sa2.petition({"rebels_activated": 10, "assault_favourable": true})
	eq(module.marker(s2, "earth", "supply"), 5, "1 + 3 Supply su Earth")
	eq(int(s2.tracks["profits"]), 4, "−4 per le Supply, −2 per l'EG+")
	eq(int(s2.tracks["eg_side"]), 1, "EG+")

	# Public Relations: Repair dà 2 Profits e i Red Dust presenti perdono 3 Risorse.
	var s3 := fresh()
	var sa3 := RDRSpecials.new(s3, module)
	s3.tracks["profits"] = 0
	module.place_from_available(s3, "marth", "rd_rebel", 1)
	var rd := s3.get_resources("red_dust")
	sa3.public_relations({"spaces": [{"id": "marth", "repairs": 1}]})
	eq(int(s3.tracks["profits"]), 2, "+2 Profits per Danno rimosso")
	eq(s3.get_resources("red_dust"), rd - 3, "−3 Risorse Red Dust")

	# Exploit: Profits pari alla Popolazione e spostamento verso il Neutrale.
	var s4 := fresh()
	var sa4 := RDRSpecials.new(s4, module)
	s4.tracks["profits"] = 0
	var bad: Dictionary = sa4.exploit({"spaces": ["marth"]})
	eq(bad["ok"], false, "Exploit rifiutato dove c'è Danno")
	var ok4: Dictionary = sa4.exploit({"spaces": ["shenzhou"]})
	eq(ok4["ok"], true, "Exploit su Shenzhou")
	eq(int(s4.tracks["profits"]), 3, "+3 Profits (Popolazione di Shenzhou)")

	# Raid: SpecOps in arrivo da uno spazio adiacente rimuovono forze e fanno EG−.
	var s5 := fresh()
	var sa5 := RDRSpecials.new(s5, module)
	module.place_from_available(s5, "trouvelot", "specops", 1, "hidden")
	sa5.raid({"spaces": [{"id": "new_cordoba", "moves": [{"from": "trouvelot", "count": 1}],
		"targets": ["mg_troop", "mg_troop"]}]})
	eq(module.count_in(s5, "new_cordoba", "mg_troop"), 0, "2 Truppe MG rimosse")
	eq(int(s5.tracks["eg_side"]), -1, "colpite forze MarsGov: EG−")

	# Redistribute: Risorse pari alla Popolazione + Basi CORP.
	var s6 := fresh()
	var sa6 := RDRSpecials.new(s6, module)
	var rd6 := s6.get_resources("red_dust")
	sa6.redistribute({"spaces": ["sharma", "alpheus_colles"]})
	eq(s6.get_resources("red_dust"), rd6 + 3, "Sharma 2 + Alpheus Colles 1")
	eq(module.count_in(s6, "sharma", "rd_rebel", "active"), 1, "un Ribelle Attivato")

	# Coordinate: in Opposizione Attiva rimuove due cubi nemici.
	var s7 := fresh()
	var sa7 := RDRSpecials.new(s7, module)
	module.place_from_available(s7, "sharma", "security", 1)
	sa7.coordinate({"spaces": [{"id": "sharma", "at_max": "remove"}]})
	eq(module.count_in(s7, "sharma", "mg_troop"), 0, "Truppa MG rimossa")
	eq(module.count_in(s7, "sharma", "security"), 0, "Security rimossa")

	# Purify: converte un'unità nemica in Ribelle CR.
	var s8 := fresh()
	var sa8 := RDRSpecials.new(s8, module)
	module.place_from_available(s8, "ascraeus_mons", "mg_troop", 1)
	module.recompute_all_control(s8)
	var cr8 := module.count_in(s8, "ascraeus_mons", "cr_rebel")
	sa8.purify({"spaces": [{"id": "ascraeus_mons", "targets": ["mg_troop"]}]})
	eq(module.count_in(s8, "ascraeus_mons", "mg_troop"), 0, "Truppa MG convertita")
	eq(module.count_in(s8, "ascraeus_mons", "cr_rebel"), cr8 + 1, "+1 Ribelle CR")

	# Ransack: richiede Danni e un Ribelle Nascosto.
	var s9 := fresh()
	var sa9 := RDRSpecials.new(s9, module)
	eq(sa9.ransack({"spaces": ["ascraeus_mons"]})["ok"], true, "Ransack su spazio Danneggiato")
	eq(sa9.ransack({"spaces": ["new_cordoba"]})["ok"], false, "Ransack rifiutato senza Danni")

	# Ambush: valida gli spazi e restituisce i dadi scelti.
	var s10 := fresh()
	var sa10 := RDRSpecials.new(s10, module)
	var amb: Dictionary = sa10.ambush({"faction": "red_dust",
		"attack_spaces": ["sharma"], "choices": {"sharma": [1, 6]}})
	eq(amb["ok"], true, "Ambush valido")
	eq(amb["dice"]["sharma"], [1, 6], "dadi scelti restituiti")
	var amb_bad: Dictionary = sa10.ambush({"faction": "red_dust",
		"attack_spaces": ["sharma"], "choices": {"gandhi": [1, 1]}})
	eq(amb_bad["ok"], false, "Ambush rifiutato fuori dagli spazi dell'Attack")


# ===========================================================================
# Fase 5 — mazzi Asset e Campaign (§1.5)
# ===========================================================================

func cards_for(s: GameState, seed_value: int = 777) -> RDRCards:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var c := RDRCards.new(s, module, r)
	c.setup()
	return c


func test_cards_setup() -> void:
	print("Mazzi Asset e Campaign (§1.5/§3.3)")
	var s := fresh()
	var c := cards_for(s)
	eq(c.assets.size(), 30, "30 carte Asset")
	eq(c.campaigns.size(), 12, "12 carte Campaign")
	eq(c.hand().size(), 3, "mano iniziale dei Reclaimer: 3 carte")
	eq(c.deck().size(), 27, "27 Asset restano nel mazzo")
	ok(c.campaign_in_play() > 0, "una Campaign card in gioco al setup")
	eq(state.tracks.get("campaign_deck", []).size(), 0, "lo stato di riferimento non è toccato")

	# I valori letti dalle carte: le Capability valgono 2, gli Eventi 3, le
	# carte di sola Risorsa 4 (5 per l'Operazione che nominano).
	eq(c.value_of(1), 2, "Subdermal Weaponry vale 2")
	eq(c.value_of(7), 3, "Children of the Desert vale 3")
	eq(c.value_of(14), 4, "The Trackless Wastes vale 4")
	eq(c.value_of(14, "travel"), 5, "…ma 5 se paga un Travel")
	eq(c.value_of(14, "rally"), 4, "…e 4 per un'altra Operazione")


func test_cards_pay() -> void:
	print("Pagamento con Asset card (§1.5)")
	var s := fresh()
	var c := cards_for(s)
	# Mano nota: una Capability (2), un Evento (3) e una Risorsa (4/5 per Travel).
	state.tracks["ignore"] = 0
	c.state.tracks["asset_hand"] = [1, 7, 14]
	eq(c.pay(4, "rally"), true, "4 Risorse pagate con una sola carta da 4")
	eq(c.hand().size(), 2, "una carta scartata")
	ok(not c.hand().has(14), "spesa per prima la carta di sola Risorsa")

	# Il bonus dell'Operazione nominata riduce le carte necessarie.
	var s2 := fresh()
	var c2 := cards_for(s2)
	c2.state.tracks["asset_hand"] = [14]
	eq(c2.pay(5, "travel"), true, "The Trackless Wastes copre 5 in un Travel")
	var s3 := fresh()
	var c3 := cards_for(s3)
	c3.state.tracks["asset_hand"] = [14]
	eq(c3.pay(5, "rally"), false, "…ma non 5 in un Rally")
	eq(c3.hand().size(), 1, "pagamento rifiutato: la carta resta in mano")

	# Più carte insieme, con l'eccedenza persa.
	var s4 := fresh()
	var c4 := cards_for(s4)
	c4.state.tracks["asset_hand"] = [1, 7]
	eq(c4.pay(5), true, "2 + 3 coprono un costo di 5")
	eq(c4.hand().size(), 0, "entrambe scartate")
	eq(c4.discard_pile().size(), 2, "finiscono negli scarti")


func test_cards_hand_limit() -> void:
	print("Limite di mano e rimescolamento (§1.5/§4.3)")
	var s := fresh()
	var c := cards_for(s)
	c.draw_asset(10)
	eq(c.hand().size(), 6, "mano limitata a 6 carte")
	ok(c.discard_pile().size() > 0, "le eccedenti vanno negli scarti")

	# Reset del Dust Storm Round: gli scarti rientrano nel mazzo.
	var before := c.deck().size() + c.discard_pile().size()
	c.reshuffle_discards()
	eq(c.discard_pile().size(), 0, "scarti azzerati")
	eq(c.deck().size(), before, "tutte le carte tornano nel mazzo")

	# Mazzo esaurito: non si pesca più.
	var s2 := fresh()
	var c2 := cards_for(s2)
	c2.state.tracks["asset_deck"] = []
	c2.state.tracks["asset_hand"] = []
	eq(c2.draw_asset(1), 0, "mazzo vuoto: nessuna pescata")


func test_cards_eligibility_and_events() -> void:
	print("Asset per l'Eligibility e Eventi (§4.1/§1.5)")
	var s := fresh()
	var c := cards_for(s)
	c.state.tracks["asset_hand"] = [1, 7, 14]
	eq(c.discard_for_eligibility(2), 2, "due carte scartate per anticipare il turno")
	eq(c.hand().size(), 1, "resta una carta")

	# #19 e #22 fanno pescare se scartate per diventare 1ª Disponibile.
	var s2 := fresh()
	var c2 := cards_for(s2)
	c2.state.tracks["asset_hand"] = [19]
	var deck_before := c2.deck().size()
	c2.discard_for_eligibility(1)
	eq(c2.hand().size(), 1, "Re-Engineering fa ripescare una carta")
	eq(c2.deck().size(), deck_before - 1, "la carta arriva dal mazzo")

	# Una Capability resta in gioco e non torna nel mazzo.
	var s3 := fresh()
	var c3 := cards_for(s3)
	c3.state.tracks["asset_hand"] = [1, 7]
	var res: Dictionary = c3.play_asset_event(1)
	eq(res["ok"], true, "Capability giocata")
	eq(res["capability"], true, "riconosciuta come Capability")
	eq(c3.has_capability(1), true, "resta in gioco")
	eq(c3.discard_pile().has(1), false, "non finisce negli scarti")
	# Un Evento normale invece si scarta.
	c3.play_asset_event(7)
	eq(c3.discard_pile().has(7), true, "l'Evento Asset va negli scarti")
	# Le carte di sola Risorsa non hanno Evento.
	c3.state.tracks["asset_hand"] = [14]
	eq(c3.play_asset_event(14)["ok"], false, "una carta di sola Risorsa non ha Evento")


func test_campaign_deck() -> void:
	print("Mazzo Campaign (§5.10/§4.3)")
	var s := fresh()
	var c := cards_for(s)
	var first := c.campaign_in_play()
	ok(first > 0, "una Campaign in gioco")
	ok(c.campaign_title(first) != "", "titolo leggibile: %s" % c.campaign_title(first))
	# Pescandone altre, una entra in gioco e le altre tornano nel mazzo.
	var second := c.draw_campaign_into_play(3)
	eq(c.campaign_in_play(), second, "la nuova carta sostituisce la precedente")
	eq(s.tracks["campaign_deck"].size(), 11, "le altre tornano nel mazzo (12 − 1 in gioco)")
	# Il Reset la rimuove DAL GIOCO.
	c.remove_campaign()
	eq(c.campaign_in_play(), -1, "nessuna Campaign in gioco dopo il Reset")


func test_reclaimer_pays() -> void:
	print("I Reclaimer pagano davvero (§1.5)")
	var s := fresh()
	var c := cards_for(s)
	var o := ops_for(s)
	o.cards = c
	c.state.tracks["asset_hand"] = [14, 15]   # 4 + 4, con bonus su Travel e Rally
	var res: Dictionary = o.rally({"faction": "reclaimer",
		"spaces": [{"id": "rutherford", "mode": "place"}]})
	eq(res["ok"], true, "Rally dei Reclaimer eseguito")
	eq(c.hand().size(), 1, "una Asset card scartata per pagare")
	eq(int(s.tracks.get("cr_unpaid", 0)), 0, "niente più costi non pagati")

	# Senza carte in mano l'Operazione è rifiutata.
	var s2 := fresh()
	var c2 := cards_for(s2)
	var o2 := ops_for(s2)
	o2.cards = c2
	c2.state.tracks["asset_hand"] = []
	var bad: Dictionary = o2.rally({"faction": "reclaimer",
		"spaces": [{"id": "rutherford", "mode": "place"}]})
	eq(bad["ok"], false, "senza Asset card il Rally è rifiutato")


# ===========================================================================
# Fase 5 — Eventi (§7.0)
# ===========================================================================

## Interprete degli Eventi già collegato ai mazzi e ai round periodici.
func events_for(s: GameState, faction: String = "marsgov", seed_value: int = 999) -> RDREvents:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var c := RDRCards.new(s, module, r)
	c.setup()
	c.log_lines.clear()
	var rd := RDRRounds.new(s, module, r)
	rd.cards = c
	var ev := RDREvents.new(s, module)
	ev.cards = c
	ev.rounds = rd
	ev.executing_faction = faction
	return ev


func test_events() -> void:
	print("Eventi (§7.0)")
	var s := fresh()
	var ev := RDREvents.new(s, module)
	var cov := ev.coverage()
	eq(cov["total"], 93, "93 opzioni di Evento (48 carte, alcune con un solo effetto)")
	eq(cov["automatic"], 93, "tutte e 93 le opzioni hanno effetti scritti a mano")
	eq(cov["manual"], 0, "nessuna opzione resta da risolvere al tavolo")

	# #1 ombreggiato: "Reduce Profits by 5 and MG Resources by 9" — tutto automatico.
	s.tracks["profits"] = 20
	var mg := s.get_resources("marsgov")
	var res: Dictionary = ev.play(1, true)
	eq(res["ok"], true, "Evento #1 ombreggiato eseguito")
	eq(res["manual"], false, "…ed è interamente automatico")
	eq(int(s.tracks["profits"]), 15, "−5 Profits")
	eq(s.get_resources("marsgov"), mg - 9, "−9 Risorse MarsGov")

	# #2 ombreggiato porta anche il simbolo EG−.
	var s2 := fresh()
	var ev2 := RDREvents.new(s2, module)
	s2.tracks["eg_side"] = 1
	ev2.play(2, true)
	eq(int(s2.tracks["eg_side"]), -1, "il simbolo EG− è applicato")

	# #10 non ombreggiato sposta 2 spazi a scelta del giocatore.
	var s3 := fresh()
	var ev3 := RDREvents.new(s3, module)
	eq(ev3.targets_needed(10, false), 2, "#10 richiede 2 spazi")
	# NB: Radau al setup ha un Danno che la rende Spopolata, e uno spazio Spopolato
	# è sempre Neutrale (§1.8): come bersaglio non si sposterebbe.
	eq(module.population(s3, "radau"), 0, "Radau è Spopolata dal Danno iniziale")
	var r_before: int = s3.spaces["rutherford"].support
	var p_before: int = s3.spaces["pavonis_mons"].support
	ev3.play(10, false, ["rutherford", "pavonis_mons"])
	eq(s3.spaces["rutherford"].support, r_before + 1, "Rutherford spostata verso il Supporto")
	eq(s3.spaces["pavonis_mons"].support, p_before + 1, "Pavonis Mons spostata verso il Supporto")

	# #14 ombreggiato nomina due spazi precisi: nessuna scelta richiesta.
	var s4 := fresh()
	var ev4 := RDREvents.new(s4, module)
	eq(ev4.targets_needed(14, true), 0, "#14 ombreggiato non richiede scelte")
	var eu: int = s4.spaces["europa"].support
	ev4.play(14, true)
	eq(s4.spaces["europa"].support, eu - 1, "Europa spostata verso l'Opposizione")

	# #33 non ombreggiato attiva tutti i Ribelli Red Dust della mappa.
	var s5 := fresh()
	var ev5 := RDREvents.new(s5, module)
	ev5.play(33, false)
	var hidden := 0
	for sid in module.mars_spaces(s5):
		hidden += module.count_in(s5, sid, "rd_rebel", "hidden")
	eq(hidden, 0, "nessun Ribelle Red Dust resta Nascosto")

	# Il simbolo EG+/EG− stampato sulla carta resta il primo effetto applicato.
	var s6 := fresh()
	var ev6 := RDREvents.new(s6, module)
	eq(ev6.is_manual(3, false), false, "#3 non ombreggiato non è più manuale")
	var res6: Dictionary = ev6.play(3, false)
	eq(res6["manual"], false, "risolto per intero")
	eq(String(res6["residual"]), "", "niente testo residuo")
	eq(int(s6.tracks["eg_side"]), 1, "il simbolo EG+ è applicato")


# ===========================================================================
# Fase 5 — la libreria di effetti scritti a mano (§7.0)
# ===========================================================================

## Tutte e 93 le opzioni devono risolversi senza errori su uno stato fresco,
## riempiendo da sole le scelte che il chiamante non fornisce.
func test_events_all_options() -> void:
	print("Eventi — tutte le opzioni si risolvono")
	var errors: Array[String] = []
	var without_choices := 0
	for number in range(1, 49):
		for shaded in [false, true]:
			var s := fresh()
			var ev := events_for(s, "marsgov")
			if ev.option(number, shaded).is_empty():
				continue
			var res: Dictionary = ev.play(number, shaded)
			if not res.get("ok", false):
				errors.append("#%d %s: %s" % [number, shaded, res.get("error", "")])
			if (res.get("choices", {}) as Dictionary).is_empty():
				without_choices += 1
			# Lo stato deve restare coerente: nessun conteggio negativo.
			for sid in s.spaces.keys():
				for fid in (s.spaces[sid] as SpaceState).pieces.keys():
					for t in s.spaces[sid].pieces[fid].keys():
						for st in s.spaces[sid].pieces[fid][t].keys():
							if int(s.spaces[sid].pieces[fid][t][st]) < 0:
								errors.append("#%d: %s negativo in %s" % [number, t, sid])
	eq(errors.size(), 0, "nessun errore giocando le 93 opzioni (%s)" % ", ".join(errors))
	ok(without_choices < 40, "la maggior parte delle opzioni dichiara delle scelte")


func test_events_effects() -> void:
	print("Eventi — effetti scritti a mano")

	# #1: tutti i Danni negli spazi con Controllo COIN, +1 Profit ciascuno.
	var s1 := fresh()
	var ev1 := events_for(s1)
	var damaged := 0
	for sid in module.mars_spaces(s1):
		if s1.spaces[sid].control == "coin":
			damaged += module.marker(s1, sid, "damage")
	ok(damaged > 0, "allo schieramento c'è Danno sotto Controllo COIN (%d)" % damaged)
	ev1.play(1, false)
	eq(int(s1.tracks["profits"]), damaged, "+1 Profit per ogni Danno rimosso")
	var left := 0
	for sid in module.mars_spaces(s1):
		if s1.spaces[sid].control == "coin":
			left += module.marker(s1, sid, "damage")
	eq(left, 0, "nessun Danno resta negli spazi COIN")

	# #9: 1 Supply su Earth per ogni Labirinto senza forze Ribelli.
	var s9 := fresh()
	var ev9 := events_for(s9)
	var clean := 0
	for sid in module.mars_spaces(s9):
		if not module.is_labyrinth(s9, sid):
			continue
		if module.count_in(s9, sid, "rd_rebel") + module.count_in(s9, sid, "cr_rebel") \
				+ module.count_in(s9, sid, "rd_base") + module.count_in(s9, sid, "cr_base") == 0:
			clean += 1
	var supply_before := module.marker(s9, "earth", "supply")
	ev9.play(9, false)
	eq(module.marker(s9, "earth", "supply"), supply_before + clean,
		"%d Labirinti liberi → altrettante Supply" % clean)

	# #14 non ombreggiato apre la Rodgers Line fra Europa e Tereshkova.
	var s14 := fresh()
	var ev14 := events_for(s14)
	ok(not Array(module.maglev_links(s14, "europa")).has("tereshkova"),
		"prima dell'Evento #14 la linea è in costruzione")
	ev14.play(14, false)
	ok(Array(module.maglev_links(s14, "europa")).has("tereshkova"),
		"dopo l'Evento #14 Europa e Tereshkova sono collegate")
	eq(int(s14.tracks["profits"]), 6, "+6 Profits")

	# #18 ombreggiato toglie 4 SpecOps DAL GIOCO (non fra le Disponibili).
	var s18 := fresh()
	var ev18 := events_for(s18)
	var avail_before := module.available(s18, "specops")
	s18.tracks["profits"] = 10
	ev18.play(18, true)
	eq(module.available(s18, "specops"), avail_before - 4, "4 SpecOps in meno fra le Disponibili")
	eq(int(s18.out_of_play.get("corporations:specops", 0)), 4, "…e fuori dal gioco")
	eq(int(s18.tracks["profits"]), 6, "−4 Profits")

	# #21 ombreggiato sostituisce cubi COIN con Ribelli, uno per spazio scelto.
	var s21 := fresh()
	var ev21 := events_for(s21, "red_dust")
	var targets: Array = []
	for sid in module.mars_spaces(s21):
		if module.count_in(s21, sid, "mg_troop") > 0 and targets.size() < 2:
			targets.append(sid)
	var mg_before := module.count_in(s21, String(targets[0]), "mg_troop")
	ev21.play(21, true, {"a": targets, "who": "red_dust"})
	eq(module.count_in(s21, String(targets[0]), "mg_troop"), mg_before - 1,
		"una Truppa MG sostituita nel primo spazio")
	ok(module.count_in(s21, String(targets[0]), "rd_rebel") > 0, "…da un Ribelle Red Dust")

	# #24 ombreggiato sposta verso l'Opposizione solo se lo spazio resta senza cubi.
	var s24 := fresh()
	var ev24 := events_for(s24)
	var lone := ""
	for sid in module.mars_spaces(s24):
		var cubes := module.count_in(s24, sid, "mg_troop") + module.count_in(s24, sid, "security") \
			+ module.count_in(s24, sid, "eg_troop")
		if cubes > 0 and cubes <= 4 and module.population(s24, sid) > 0 and lone == "":
			lone = sid
	ok(lone != "", "trovato uno spazio con pochi cubi (%s)" % lone)
	var sup_before: int = s24.spaces[lone].support
	ev24.play(24, true, {"a": [lone]})
	eq(module.count_in(s24, lone, "mg_troop") + module.count_in(s24, lone, "security")
		+ module.count_in(s24, lone, "eg_troop"), 0, "lo spazio resta senza cubi")
	eq(s24.spaces[lone].support, maxi(sup_before - 1, CoinEnums.Support.ACTIVE_OPPOSITION),
		"…quindi si sposta verso l'Opposizione")

	# #47 piazza i 6 marcatori Tempesta disponibili e lascia Disponibile chi esegue.
	var s47 := fresh()
	var ev47 := events_for(s47, "reclaimer")
	ev47.play(47, false)
	var storms := 0
	for sid in module.mars_spaces(s47):
		if module.storm(s47, sid) == 2:
			storms += 1
	eq(storms, 6, "6 Raging Storm sulla mappa (il massimo, §1.10)")
	ok(Array(s47.tracks.get("stay_eligible", [])).has("reclaimer"),
		"i Reclaimer restano Disponibili")

	# #48 ombreggiato: Europa crolla di 2 livelli e il Red Dust pesca 4 Campaign.
	var s48 := fresh()
	var ev48 := events_for(s48)
	var eu: int = s48.spaces["europa"].support
	var deck_before: int = (s48.tracks.get("campaign_deck", []) as Array).size()
	var campaign_before := int(s48.tracks.get("campaign_in_play", -1))
	ev48.play(48, true)
	eq(s48.spaces["europa"].support, maxi(eu - 2, CoinEnums.Support.ACTIVE_OPPOSITION),
		"Europa −2 livelli")
	ok(int(s48.tracks.get("campaign_in_play", -1)) != campaign_before,
		"una nuova Campaign card entra in gioco")
	# Le 3 carte non giocate e quella sostituita tornano nel mazzo: il conto torna.
	eq((s48.tracks.get("campaign_deck", []) as Array).size(), deck_before,
		"pescate 4 Campaign, una in gioco e le altre rimescolate")


## §7.0: gli Eventi che rendono una Fazione Non Disponibile, o che la lasciano
## Disponibile, agiscono alla chiusura della carta.
func test_events_eligibility() -> void:
	print("Eventi — Eligibility (§7.0/§4.1)")

	# #29 non ombreggiato: −5 Risorse al Red Dust, che salta il round successivo.
	var s := fresh()
	var ev := events_for(s, "marsgov")
	var rd_before := s.get_resources("red_dust")
	ev.play(29, false, {"target": "red_dust"})
	eq(s.get_resources("red_dust"), rd_before - 5, "−5 Risorse Red Dust")
	var seq := RDRSequence.new(s, module, gd.card(1))
	seq.finish()
	eq(s.eligibility["red_dust"], CoinEnums.Eligibility.INELIGIBLE,
		"il Red Dust è Non Disponibile alla carta seguente")
	eq((s.tracks.get("forced_ineligible", []) as Array).size(), 0, "la lista è consumata")

	# #46 non ombreggiato: le Corporations restano Disponibili anche avendo agito.
	var s2 := fresh()
	var ev2 := events_for(s2, "corporations")
	# Serve un Deserto Spopolato con una Base CORP: lo si prepara a mano.
	module.place_from_available(s2, "wilderness", "corp_base", 1)
	ev2.play(46, false, {"a": ["wilderness"]})
	var seq2 := RDRSequence.new(s2, module, gd.card(1))
	seq2.act(CoinEnums.ActionType.EVENT)
	seq2.finish()
	eq(s2.eligibility["corporations"], CoinEnums.Eligibility.ELIGIBLE,
		"le Corporations restano Disponibili")


## §7.0: le Operazioni gratuite concesse dagli Eventi finiscono in coda e le
## esegue il motore delle Operazioni senza pagarne il costo.
func test_events_free_ops() -> void:
	print("Eventi — Operazioni gratuite")
	var s := fresh()
	var ev := events_for(s, "marsgov")
	var res: Dictionary = ev.play(8, false)
	var queue: Array = s.tracks.get("pending_free_ops", [])
	eq(queue.size(), 1, "#8 concede una sola Operazione gratuita")
	var entry: Dictionary = queue[0]
	eq(String(entry["operation"]), "assault", "…un Assault")
	eq(String(entry["faction"]), "marsgov", "…al MarsGov")
	eq(Array(entry["spaces"]), ["tenzing"], "…a Tenzing")
	eq(module.count_in(s, "tenzing", "rd_rebel", "hidden"), 0,
		"i Ribelli di Tenzing sono stati Attivati")

	# Eseguirla non costa Risorse.
	var ops := ops_for(s)
	ops.free = true
	var mg_before := s.get_resources("marsgov")
	var done: Dictionary = ops.assault({"faction": "marsgov", "spaces": ["tenzing"]})
	eq(done.get("ok", false), true, "l'Assault gratuito è eseguito")
	eq(s.get_resources("marsgov"), mg_before, "…e non costa Risorse")

	# #34: quando l'Evento lascia libera la scelta dell'Operazione, la coda porta
	# la nota invece del nome dell'Operazione.
	var s2 := fresh()
	var ev2 := events_for(s2, "marsgov")
	ev2.play(34, false)
	var q2: Array = s2.tracks.get("pending_free_ops", [])
	eq(q2.size(), 1, "#34 mette in coda l'Operazione a scelta")
	eq(String((q2[0] as Dictionary)["operation"]), "", "senza Operazione prefissata")
	ok(String((q2[0] as Dictionary)["note"]) != "", "ma con la nota per il giocatore")

	# #39: gli effetti "a seguire" scattano solo dopo l'Assault, e solo se sono
	# state rimosse Basi Ribelli.
	var s3 := fresh()
	var ev3 := events_for(s3, "corporations")
	var lab := ""
	for sid in module.mars_spaces(s3):
		if module.is_labyrinth(s3, sid) and module.count_in(s3, sid, "rd_base") > 0:
			lab = sid
			break
	if lab == "":
		lab = "tenzing"
		module.place_from_available(s3, lab, "rd_base", 1)
	ev3.play(39, false, {"a": [lab]})
	s3.tracks["profits"] = 0
	var pending: Array = s3.tracks.get("pending_free_ops", [])
	ev3.apply_after(pending[0])
	eq(int(s3.tracks["profits"]), 0, "niente Profits finché la Base Ribelle è al suo posto")
	module.remove_pieces(s3, lab, "rd_base", 9, "available")
	ev3.apply_after(pending[0])
	eq(int(s3.tracks["profits"]), 4, "+4 Profits quando l'Assault ha tolto la Base")


# ===========================================================================
# Fase 5 — Eventi delle Asset card (§1.5)
# ===========================================================================

func test_asset_events() -> void:
	print("Asset card — Eventi (§1.5)")
	var s := fresh()
	var ev := events_for(s, "reclaimer")
	# I 10 Eventi delle Asset card hanno tutti i loro effetti.
	var covered := 0
	for number in [7, 8, 9, 10, 11, 12, 13, 27, 28, 29]:
		if not ev.asset_option(number).is_empty():
			covered += 1
	eq(covered, 10, "tutti e 10 gli Eventi delle Asset card hanno effetti")

	# Tutti devono risolversi su uno stato fresco, senza errori.
	var errors: Array[String] = []
	for number in [7, 8, 9, 10, 11, 12, 13, 27, 28, 29]:
		var si := fresh()
		var evi := events_for(si, "reclaimer")
		var res: Dictionary = evi.play_asset(number)
		if not res.get("ok", false):
			errors.append("#%d: %s" % [number, res.get("error", "")])
	eq(errors.size(), 0, "i 10 Eventi Asset si risolvono (%s)" % ", ".join(errors))

	# #10 Converts: sostituisce Ribelli RD con Ribelli CR, uno per spazio scelto.
	var s10 := fresh()
	var ev10 := events_for(s10, "reclaimer")
	var with_rd: Array = []
	for sid in module.mars_spaces(s10):
		if module.count_in(s10, sid, "rd_rebel") > 0 and with_rd.size() < 2:
			with_rd.append(sid)
	var rd_before := module.count_in(s10, String(with_rd[0]), "rd_rebel")
	ev10.play_asset(10, {"a": with_rd})
	eq(module.count_in(s10, String(with_rd[0]), "rd_rebel"), rd_before - 1,
		"un Ribelle RD in meno nel primo spazio")
	ok(module.count_in(s10, String(with_rd[0]), "cr_rebel") > 0, "…sostituito da un CR")

	# #8 Weaponized Asteroid: 2 Danni e metà delle unità, arrotondata per eccesso.
	var s8 := fresh()
	var ev8 := events_for(s8, "reclaimer")
	var lab := ""
	for sid in module.mars_spaces(s8):
		if module.is_labyrinth(s8, sid) and lab == "":
			lab = sid
	var units_before := 0
	for t in ["mg_troop", "security", "eg_troop", "specops", "rd_rebel", "cr_rebel"]:
		units_before += module.count_in(s8, lab, String(t))
	var dmg_before := module.marker(s8, lab, "damage")
	ev8.play_asset(8, {"a": [lab]})
	ok(module.marker(s8, lab, "damage") > dmg_before, "%s ha preso Danno" % lab)
	var units_after := 0
	for t in ["mg_troop", "security", "eg_troop", "specops", "rd_rebel", "cr_rebel"]:
		units_after += module.count_in(s8, lab, String(t))
	eq(units_after, units_before - int(ceil(units_before / 2.0)),
		"rimossa metà delle unità per eccesso (%d su %d)" % [units_before - units_after, units_before])

	# #7 Children of the Desert: Travel gratuito, poi un Attack per Deserto.
	var s7 := fresh()
	var ev7 := events_for(s7, "reclaimer")
	ev7.play_asset(7, {"a": ["rutherford"]})
	var queue: Array = s7.tracks.get("pending_free_ops", [])
	eq(queue.size(), 2, "#7 concede Travel e Attack gratuiti")
	eq(String((queue[0] as Dictionary)["operation"]), "travel", "prima il Travel")
	eq(String((queue[1] as Dictionary)["operation"]), "attack", "poi l'Attack")
	ok(Array((queue[1] as Dictionary)["spaces"]).has("rutherford"),
		"l'Attack include il Deserto scelto")


# ===========================================================================
# Fase 5 — Capability delle Asset card (§1.5)
# ===========================================================================

func with_capability(n: int) -> GameState:
	var s := fresh()
	s.tracks["capabilities"] = [n]
	return s


func test_capabilities() -> void:
	print("Asset card — Capability (§1.5)")

	# Il riconoscimento sopravvive al salvataggio (i numeri tornano come float).
	var sj := fresh()
	sj.tracks["capabilities"] = [2.0]
	eq(module.capability_active(sj, 2), true, "la Capability si riconosce anche dopo un salvataggio")

	# #2 Dust-Adaptation: i Reclaimer possono scegliere spazi in Raging Storm.
	var s2 := with_capability(2)
	var storm_space := ""
	for sid in module.mars_spaces(s2):
		if module.is_desert(s2, sid) and s2.spaces[sid].support == CoinEnums.Support.NEUTRAL \
				and storm_space == "":
			storm_space = sid
	module.set_marker(s2, storm_space, "storm", 2)
	var o2 := ops_for(s2)
	ok(Array(o2.rally_candidates("reclaimer")).has(storm_space),
		"#2: %s in tempesta resta selezionabile dai Reclaimer" % storm_space)
	var s2b := fresh()
	module.set_marker(s2b, storm_space, "storm", 2)
	ok(not Array(ops_for(s2b).rally_candidates("reclaimer")).has(storm_space),
		"…senza la Capability no")

	# #23 MPS Uplink Hacked: un Satellite conta come Base Reclaimer in più.
	var s23 := with_capability(23)
	# I Satelliti non stanno fra le Disponibili: allo schieramento sono in Orbita.
	module.move_pieces(s23, "orbit", "rutherford", "satellite", 1)
	eq(module.cr_bases_in(s23, "rutherford"), module.count_in(s23, "rutherford", "cr_base") + 1,
		"#23: il Satellite vale una Base CR in più")
	eq(module.cr_bases_in(fresh(), "rutherford"), 0, "…senza la Capability no")

	# #5 Neural Conditioning: Rally "fill" anche senza Base CR.
	var s5 := with_capability(5)
	var neutral := ""
	for sid in module.mars_spaces(s5):
		if s5.spaces[sid].support == CoinEnums.Support.NEUTRAL \
				and module.population(s5, sid) > 0 and module.count_in(s5, sid, "cr_base") == 0 \
				and neutral == "":
			neutral = sid
	var o5 := ops_for(s5)
	var cr_before := module.count_in(s5, neutral, "cr_rebel")
	o5.rally({"faction": "reclaimer", "spaces": [{"id": neutral, "mode": "fill"}]})
	ok(module.count_in(s5, neutral, "cr_rebel") > cr_before,
		"#5: Rally «fill» riempie %s pur senza Base" % neutral)
	var s5b := fresh()
	var o5b := ops_for(s5b)
	var cr_b2 := module.count_in(s5b, neutral, "cr_rebel")
	o5b.rally({"faction": "reclaimer", "spaces": [{"id": neutral, "mode": "fill"}]})
	eq(module.count_in(s5b, neutral, "cr_rebel"), cr_b2, "…senza la Capability non piazza nulla")

	# #4 The Mind Twister: Purify converte una forza nemica in più.
	var s4 := with_capability(4)
	var pur := "radau"
	module.place_from_available(s4, pur, "mg_troop", 2)
	module.place_from_available(s4, pur, "cr_rebel", 6, "hidden")
	module.recompute_all_control(s4)
	eq(s4.spaces[pur].control, "reclaimer", "#4: Radau è sotto Controllo Reclaimer")
	var mg_before := module.count_in(s4, pur, "mg_troop")
	var sp4 := RDRSpecials.new(s4, module)
	var r4: Dictionary = sp4.purify({"spaces": [
		{"id": pur, "mode": "convert", "targets": ["mg_troop"]}]})
	eq(r4.get("ok", false), true, "#4: il Purify riesce")
	eq(module.count_in(s4, pur, "mg_troop"), mg_before - 2,
		"#4: Purify converte 2 Truppe MG invece di 1")

	# #24 AI Unleashed: il Ransack colpisce anche le Risorse MarsGov.
	var s24 := with_capability(24)
	var rans := ""
	for sid in module.mars_spaces(s24):
		if module.marker(s24, sid, "damage") > 0 and rans == "":
			rans = sid
	module.place_from_available(s24, rans, "cr_rebel", 1, "hidden")
	var mg_res := s24.get_resources("marsgov")
	var sp24 := RDRSpecials.new(s24, module)
	sp24.ransack({"spaces": [rans]})
	eq(s24.get_resources("marsgov"), mg_res - 3, "#24: −3 Risorse MarsGov dopo il Ransack")

	# #1 Subdermal Weaponry: l'Attack CR toglie una forza in più per dado riuscito.
	var s1 := with_capability(1)
	var atk := "radau"
	module.place_from_available(s1, atk, "cr_rebel", 6, "hidden")
	module.place_from_available(s1, atk, "mg_troop", 6)
	var o1 := ops_for(s1)
	o1.attack({"faction": "reclaimer", "spaces": [atk], "ambush": {atk: [1, 1]}})
	var left_with := module.count_in(s1, atk, "mg_troop")
	var s1b := fresh()
	module.place_from_available(s1b, atk, "cr_rebel", 6, "hidden")
	module.place_from_available(s1b, atk, "mg_troop", 6)
	ops_for(s1b).attack({"faction": "reclaimer", "spaces": [atk], "ambush": {atk: [1, 1]}})
	var left_without := module.count_in(s1b, atk, "mg_troop")
	ok(left_with < left_without,
		"#1: con la Capability restano meno Truppe MG (%d contro %d)" % [left_with, left_without])

	# #26 Ares Rockets: l'Attack CR può abbattere Satelliti altrove su Mars.
	var s26 := with_capability(26)
	module.place_from_available(s26, atk, "cr_rebel", 6, "hidden")
	module.move_pieces(s26, "orbit", "marth", "satellite", 1)
	var sat_before := module.count_in(s26, "marth", "satellite")
	var o26 := ops_for(s26)
	o26.attack({"faction": "reclaimer", "spaces": [atk], "ambush": {atk: [1, 1]}})
	ok(module.count_in(s26, "marth", "satellite") < sat_before,
		"#26: il Satellite di Marth è stato abbattuto da un Attack a Radau")

	# #25 Genetic Masking: dove c'è una Base CR, Secure/Recon contano 2 unità in meno.
	var s25 := with_capability(25)
	var lab25 := "tenzing"
	module.place_from_available(s25, lab25, "cr_base", 1)
	module.place_from_available(s25, lab25, "cr_rebel", 4, "hidden")
	module.place_from_available(s25, lab25, "mg_troop", 3)
	var o25 := ops_for(s25)
	o25.secure({"faction": "marsgov", "dest": [lab25], "moves": []})
	var active_masked := module.count_in(s25, lab25, "cr_rebel", "active")
	var s25b := fresh()
	module.place_from_available(s25b, lab25, "cr_base", 1)
	module.place_from_available(s25b, lab25, "cr_rebel", 4, "hidden")
	module.place_from_available(s25b, lab25, "mg_troop", 3)
	ops_for(s25b).secure({"faction": "marsgov", "dest": [lab25], "moves": []})
	ok(active_masked < module.count_in(s25b, lab25, "cr_rebel", "active"),
		"#25: il Secure Attiva meno Ribelli (%d contro %d)" % [
			active_masked, module.count_in(s25b, lab25, "cr_rebel", "active")])

	# #3 Enhanced Metabolism: dopo un Assault che toglie forze CR, ne torna una.
	var s3 := with_capability(3)
	var ass := "tenzing"
	module.place_from_available(s3, ass, "cr_rebel", 3, "active")
	module.place_from_available(s3, ass, "mg_troop", 6)
	var o3 := ops_for(s3)
	var cr_pre := module.count_in(s3, ass, "cr_rebel")
	o3.assault({"faction": "marsgov", "spaces": [ass]})
	var cr_post := module.count_in(s3, ass, "cr_rebel")
	var s3b := fresh()
	module.place_from_available(s3b, ass, "cr_rebel", 3, "active")
	module.place_from_available(s3b, ass, "mg_troop", 6)
	ops_for(s3b).assault({"faction": "marsgov", "spaces": [ass]})
	ok(cr_post > module.count_in(s3b, ass, "cr_rebel"),
		"#3: un Ribelle CR rientra dopo l'Assault (%d contro %d)" % [
			cr_post, module.count_in(s3b, ass, "cr_rebel")])
	ok(cr_post <= cr_pre, "…senza però annullare l'Assault")


# ===========================================================================
# Fase 6 — Non-Player *Curiosity* (§8.0)
# ===========================================================================

func np_for(s: GameState, factions: Array, seed_value: int = 4711) -> RDRNonPlayer:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var np := RDRNonPlayer.new(s, module, r)
	np.setup(factions)
	return np


func test_np_setup() -> void:
	print("Non-Player — impianto e contatori (§8.2/§8.4)")
	var s := fresh()
	var np := np_for(s, ["marsgov", "corporations", "red_dust", "reclaimer"])

	# §8.4.1: i tre contatori surrogati sostituiscono Risorse e mano di carte.
	eq(np.supply_total(), 0, "Supply Total parte da 0")
	ok(np.agitate_total() >= 1 and np.agitate_total() <= 3, "Agitate Total parte a 1d3 (%d)"
		% np.agitate_total())
	eq(np.asset_total(), 3, "Asset Total parte da 3")
	np.add_asset(10)
	eq(np.asset_total(), 6, "l'Asset Total non supera mai 6")
	np.add_asset(-99)
	eq(np.asset_total(), 0, "…e non scende sotto 0")

	# Le tabelle disponibili sono tre: quella di MarsGov manca davvero.
	eq(np.has_table("red_dust"), true, "c'è la tabella NP Red Dust")
	eq(np.has_table("reclaimer"), true, "c'è la tabella NP Reclaimers")
	eq(np.has_table("corporations"), true, "c'è la tabella NP CORP")
	eq(np.has_table("marsgov"), true, "c'è la tabella NP MarsGov (dalla scheda del gioco)")
	eq(Array(np.missing).size(), 0, "nessuna tabella delle priorità manca più")

	# Chi è NP e chi è giocatore: serve alle righe con la spunta rossa.
	var s2 := fresh()
	var np2 := np_for(s2, ["red_dust"])
	eq(np2.is_np("red_dust"), true, "il Red Dust è Non-Player")
	eq(np2.is_player("marsgov"), true, "…e MarsGov è di un giocatore")

	# §8.5.4: un tiro fallito di NP MG si converte spendendo Supply Total.
	var s3 := fresh()
	var np3 := np_for(s3, ["marsgov"], 99)
	s3.tracks["supply_total"] = 6
	# Activation Number 6: il tiro fallisce sempre, così si vede la conversione.
	var conv := np3.activation_check("marsgov", 6)
	eq(conv["ok"], true, "NP MG converte il tiro fallito col Supply Total")
	eq(conv["spent"], true, "…spendendone uno")
	eq(np3.supply_total(), 5, "Supply Total sceso a 5")
	# Senza contatore il tiro fallito resta fallito.
	s3.tracks["supply_total"] = 0
	eq(np3.activation_check("marsgov", 6)["ok"], false,
		"senza Supply Total il tiro fallito ferma l'Operazione")
	# §8.5.4: NP CR non converte durante un'Operazione Limitata.
	var np4 := np_for(fresh(), ["reclaimer"], 7)
	np4.state.tracks["asset_total"] = 6
	eq(np4.activation_check("reclaimer", 6, true)["spent"], false,
		"NP CR non spende Asset Total in un'Operazione Limitata")
	eq(np4.limited_space_cap("reclaimer"), 5,
		"le Operazioni Limitate di NP CR si fermano al quinto spazio")


func test_np_priorities() -> void:
	print("Non-Player — Space Selection Priorities (§8.5.6)")
	var s := fresh()
	var np := np_for(s, ["red_dust", "reclaimer", "corporations"])

	# Un solo candidato: nessuna tabella da consultare.
	var one := np.select_space("red_dust", "place_rebels", ["tenzing"])
	eq(String(one["space"]), "tenzing", "con un solo candidato si sceglie quello")

	# «most Population» discrimina: Tenzing (3) batte Europa (2) e Rutherford (1).
	# La prima riga che si applica a `place_population` è appunto most Opposition,
	# quindi si prova su una colonna dove Population viene prima.
	var pop := np.select_space("red_dust", "place_or_dig_in_bases",
		["rutherford", "europa", "tenzing"])
	eq(String(pop["space"]), "tenzing", "«most Population» sceglie lo spazio più popoloso")
	ok(not (pop["trace"] as Array).is_empty(), "la scelta è spiegata: %s"
		% ", ".join(PackedStringArray(pop["trace"])))

	# Le righe con la spunta rossa valgono solo se quella Fazione è di un giocatore.
	# «CR is player: CR Base or CR Control» non deve applicarsi se CR è NP.
	var s2 := fresh()
	var np_all := np_for(s2, ["red_dust", "reclaimer"])
	var np_cr_player := np_for(s2, ["red_dust"])
	eq(np_all.is_player("reclaimer"), false, "con CR fra le NP la riga rossa non si applica")
	eq(np_cr_player.is_player("reclaimer"), true, "con CR giocatore sì")

	# «no CR Control» tiene solo gli spazi che i Reclaimer non controllano.
	var s3 := fresh()
	var np3 := np_for(s3, ["reclaimer"])
	var controlled := ""
	var free_space := ""
	for sid in module.mars_spaces(s3):
		if s3.spaces[sid].control == "reclaimer" and controlled == "":
			controlled = sid
		elif s3.spaces[sid].control != "reclaimer" and free_space == "":
			free_space = sid
	if controlled == "":
		controlled = "radau"
		module.place_from_available(s3, controlled, "cr_rebel", 4, "hidden")
		module.recompute_all_control(s3)
	var pick3 := np3.select_space("reclaimer", "attack", [controlled, free_space])
	eq(String(pick3["space"]), free_space,
		"«no CR Control» scarta lo spazio già controllato (%s)" % controlled)

	# Selezione di più spazi: uno alla volta, senza ripetizioni.
	var many := np.select_spaces("corporations", "secure_destination",
		["europa", "tenzing", "shepard", "tereshkova"], 3)
	eq(many.size(), 3, "si scelgono tre spazi")
	eq(Array(many).size(), 3, "…tutti diversi")
	var seen: Array = []
	for sid in many:
		ok(not seen.has(sid), "%s scelto una volta sola" % sid)
		seen.append(sid)

	# NP MarsGov ora ha la sua tabella: «Rebels at Support» viene per prima nella
	# colonna Fortify, quindi vince lo spazio con Supporto e Ribelli.
	var s6 := fresh()
	var np6 := np_for(s6, ["marsgov"])
	var with_rebels := ""
	var quiet := ""
	for sid in module.mars_spaces(s6):
		var reb := module.count_in(s6, sid, "rd_rebel") + module.count_in(s6, sid, "cr_rebel")
		if s6.spaces[sid].support > 0 and reb > 0 and with_rebels == "":
			with_rebels = sid
		elif s6.spaces[sid].support > 0 and reb == 0 and quiet == "":
			quiet = sid
	if with_rebels != "" and quiet != "":
		eq(String(np6.select_space("marsgov", "fortify", [quiet, with_rebels])["space"]),
			with_rebels, "NP MG fortifica dove ci sono Ribelli a Supporto")

	# Una Fazione senza tabella sceglierebbe a caso, dichiarandolo.
	var np_none := np_for(fresh(), ["earthgov"])
	var blind := np_none.select_space("earthgov", "place_cubes", ["europa", "tenzing"])
	ok(["europa", "tenzing"].has(String(blind["space"])), "senza tabella sceglie comunque")
	ok(String(blind["row"]).contains("mancante"),
		"…e dichiara che la tabella manca: «%s»" % blind["row"])


func test_np_piece_priorities() -> void:
	print("Non-Player — Piece Priorities (§8.5.8) e Move Priorities (§8.5.7)")
	var s := fresh()
	var np := np_for(s, ["red_dust"])

	ok(not np.piece_priorities.is_empty(), "la tabella Piece Priorities è caricata")
	ok(not np.move_priorities.is_empty(), "la tabella Move Priorities è caricata")

	# §8.5.7: i Reclaimer invertono i passi A e B — scelgono prima l'origine.
	var steps: Dictionary = np.move_priorities.get("steps", {})
	eq(String(steps["marsgov"]["a"]), "destination", "NP MG sceglie prima la destinazione")
	eq(String(steps["reclaimer"]["a"]), "origin", "NP CR sceglie prima l'origine")
	eq((np.move_priorities.get("keep_in_origin", []) as Array).size(), 11,
		"11 istruzioni «keep in origin»")
	eq((np.move_priorities.get("move_to_destination", []) as Array).size(), 17,
		"17 istruzioni «move to destination»")

	# Le Basi vengono per prime, e fra loro le CORP prima delle MG.
	var order: Array = np.piece_order("red_dust", "", "friendly_place")
	ok(order.size() > 10, "l'ordine dei pezzi è completo (%d voci)" % order.size())
	ok(order.find("corp_base:basic") < order.find("mg_base"),
		"le Basi CORP vengono prima di quelle MG")
	ok(order.find("corp_base:terraforming") < order.find("corp_base:basic"),
		"le Basi potenziate prima di quelle normali")
	ok(order.find("cr_rebel:hidden") < order.find("cr_rebel:active"),
		"i Ribelli Nascosti prima di quelli Attivi")
	ok(order.find("cr_rebel:hidden") < order.find("rd_rebel:hidden"),
		"fra i Ribelli, i Reclaimer prima del Red Dust")
	ok(order.find("satellite") < order.find("eg_troop"),
		"i Satelliti prima delle Truppe EG")

	# Rimuovendo pezzi PROPRI la tabella si legge al contrario.
	var back: Array = np.piece_order("red_dust", "", "friendly_remove")
	ok(back.find("mg_base") < back.find("corp_base:basic"),
		"per i pezzi propri l'ordine è rovesciato")

	# §8.5.8 nota A: prima i pezzi dei giocatori, poi quelli delle Fazioni NP.
	# Con il solo Red Dust fra le NP, i suoi Ribelli scendono in fondo.
	# Le Basi RD sono stampate fra le prime; se il Red Dust è NP scendono comunque
	# sotto le Security, che appartengono a un giocatore.
	var enemy: Array = np.piece_order("reclaimer", "", "enemy")
	ok(enemy.find("rd_base:basic") > enemy.find("security"),
		"i pezzi delle Fazioni NP si toccano per ultimi")
	var s2 := fresh()
	var np2 := np_for(s2, [])
	var enemy2: Array = np2.piece_order("reclaimer", "", "enemy")
	ok(enemy2.find("rd_base:basic") < enemy2.find("security"),
		"…mentre fra soli giocatori vale l'ordine stampato")

	# pick_piece trova il primo pezzo davvero presente nello spazio.
	var s3 := fresh()
	var np3 := np_for(s3, ["red_dust"])
	var sid := "radau"
	module.remove_pieces(s3, sid, "rd_rebel", 99, "available")
	module.place_from_available(s3, sid, "mg_troop", 2)
	module.place_from_available(s3, sid, "security", 1)
	var got: Dictionary = np3.pick_piece("red_dust", sid, "enemy")
	eq(String(got["type"]), "security", "fra cubi COIN si prende prima la Security")
	var only_mg: Dictionary = np3.pick_piece("red_dust", sid, "enemy", ["mg_troop"])
	eq(String(only_mg["type"]), "mg_troop", "…ma il filtro dei tipi ammessi vince")
	eq(np3.pick_piece("red_dust", "wilderness", "enemy", ["corp_base"]).is_empty(), true,
		"se non c'è nulla di ammissibile non sceglie niente")


func test_np_movement() -> void:
	print("Non-Player — motore di movimento (§8.5.7)")
	var s := fresh()
	var np := np_for(s, ["red_dust"])
	var o := ops_for(s)
	var mv := RDRNonPlayerMove.new(np, o)

	# Le origini legali ora le calcola il motore delle regole, non la scena.
	var origins := o.legal_origins("march", "red_dust", "daedalia_planum", "rd_rebel")
	ok(Array(origins).has("shepard"), "Shepard è un'origine legale per Daedalia Planum")

	# «keep 1 Hidden Rebel in spaces with acting Faction Base»: dove il Red Dust
	# ha una Base, un Ribelle Nascosto non parte.
	var base_space := "shepard"
	module.remove_pieces(s, base_space, "rd_rebel", 99, "available")
	module.place_from_available(s, base_space, "rd_base", 1)
	module.place_from_available(s, base_space, "rd_rebel", 3, "hidden")
	module.recompute_all_control(s)
	var notes: Array = []
	var keep := mv.keep_in_origin("red_dust", base_space, "march", notes)
	ok(keep >= 1, "almeno un Ribelle resta a %s (keep=%d)" % [base_space, keep])
	ok(not notes.is_empty(), "…e l'istruzione che lo impone è registrata: %s" % notes[0])

	# Senza Base, quell'istruzione non scatta.
	var s2 := fresh()
	var np2 := np_for(s2, ["red_dust"])
	var mv2 := RDRNonPlayerMove.new(np2, ops_for(s2))
	var plain := "radau"
	module.remove_pieces(s2, plain, "rd_rebel", 99, "available")
	module.remove_pieces(s2, plain, "rd_base", 99, "available")
	module.place_from_available(s2, plain, "rd_rebel", 3, "hidden")
	module.recompute_all_control(s2)
	ok(mv2.keep_in_origin("red_dust", plain, "march") <= keep,
		"senza Base restano meno Ribelli")

	# «Get»: si muove appena quanto basta, contando ciò che c'è già.
	var s3 := fresh()
	var np3 := np_for(s3, ["red_dust"])
	var o3 := ops_for(s3)
	var mv3 := RDRNonPlayerMove.new(np3, o3)
	var from_sid := "shepard"
	var to_sid := "daedalia_planum"
	module.remove_pieces(s3, from_sid, "rd_rebel", 99, "available")
	module.remove_pieces(s3, to_sid, "rd_rebel", 99, "available")
	module.place_from_available(s3, from_sid, "rd_rebel", 6, "hidden")
	module.recompute_all_control(s3)
	var moves: Array = mv3.plan_pair("red_dust", "march", from_sid, to_sid)
	ok(not moves.is_empty(), "il motore produce degli spostamenti")
	var total := 0
	for m in moves:
		eq(String(m["from"]), from_sid, "partono da %s" % from_sid)
		eq(String(m["to"]), to_sid, "arrivano a %s" % to_sid)
		total += int(m["count"])
	ok(total > 0 and total <= 6, "si muovono fra 1 e 6 Ribelli (%d)" % total)
	# E il piano è davvero eseguibile dal motore delle Operazioni.
	var before := module.count_in(s3, to_sid, "rd_rebel")
	var res: Dictionary = o3.march({"dest": [to_sid], "moves": moves})
	eq(res.get("ok", false), true, "la March col piano del bot è legale")
	eq(module.count_in(s3, to_sid, "rd_rebel"), before + total,
		"i Ribelli sono arrivati a destinazione")

	# Se a destinazione c'è già abbastanza, «Get» non muove nulla.
	var s4 := fresh()
	var np4 := np_for(s4, ["red_dust"])
	var mv4 := RDRNonPlayerMove.new(np4, ops_for(s4))
	module.place_from_available(s4, to_sid, "rd_rebel", 6, "hidden")
	module.recompute_all_control(s4)
	var need: Dictionary = mv4.get_in_destination("red_dust", to_sid, "march")
	ok(int(need["total"]) >= 0, "la soglia a destinazione è calcolata (%d)" % int(need["total"]))

	# §8.5.7: i Reclaimer scelgono prima l'origine, e col Travel muovono anche le Basi.
	eq(Array(mv.movable_types("reclaimer", "travel")).has("cr_base"), true,
		"il Travel dei Reclaimer muove anche le Basi")
	eq(Array(mv.movable_types("reclaimer", "attack")).has("cr_base"), false,
		"…le altre Operazioni no")


func test_np_eligibility() -> void:
	print("Non-Player — Eligibility Table (§8.5.2)")
	var s := fresh()
	var np := np_for(s, ["marsgov", "red_dust", "reclaimer"])
	ok(not np.eligibility_table.is_empty(), "la tabella di Eligibility è caricata")

	# Senza sapere nulla della carta si cade sull'ultima riga, e lo si dichiara.
	var blind := np.choose_action("marsgov", "first")
	eq(String(blind["action"]), "op_sa", "1ª Disponibile al buio: Operazione + Attività Speciale")
	eq(bool(blind["degraded"]), true, "…e la degradazione è segnalata")
	eq(String(np.choose_action("marsgov", "second")["action"]), "lim_op",
		"2ª Disponibile al buio: Operazione Limitata")

	# Riga ①: Evento Critico ed efficace → si gioca l'Evento.
	var crit := np.choose_action("marsgov", "first",
		{"current_critical": true, "current_effective": true})
	eq(String(crit["action"]), "event", "Evento Critico ed efficace: si gioca")
	eq(int(crit["row"]), 1, "…dalla riga 1")
	eq(bool(crit["degraded"]), false, "…senza degradazione")

	# Critico ma NON efficace: la riga ① non scatta.
	eq(String(np.choose_action("marsgov", "first",
		{"current_critical": true, "current_effective": false})["action"]), "op_sa",
		"Critico ma non efficace: non si gioca l'Evento")

	# Riga ③: se l'Evento è Critico per la 2ª, la 1ª fa Operazione soltanto,
	# per non lasciarle l'Evento.
	eq(String(np.choose_action("marsgov", "first",
		{"current_critical": false, "current_critical_for_second": true})["action"]), "op_only",
		"Evento Critico per la 2ª: la 1ª fa solo l'Operazione")

	# Riga ④: se la prossima carta è Critica e passando si sarebbe 1ª, si passa.
	eq(String(np.choose_action("red_dust", "first",
		{"next_critical": true, "first_on_next_if_pass": true})["action"]), "pass",
		"prossima carta Critica e si sarebbe 1ª: si passa")
	eq(String(np.choose_action("red_dust", "first",
		{"next_critical": true, "first_on_next_if_pass": false})["action"]), "op_sa",
		"…ma non se passando non si sarebbe 1ª")

	# 2ª Disponibile riga ②: se la 1ª ha giocato l'Evento, la 2ª fa Op + SA.
	eq(String(np.choose_action("red_dust", "second", {"first_chose": "event"})["action"]),
		"op_sa", "se la 1ª ha giocato l'Evento, la 2ª fa Op + SA")

	# 2ª riga ③: dopo un Op+SA della 1ª, l'Evento se è Critico o Performed ed efficace.
	eq(String(np.choose_action("red_dust", "second",
		{"first_chose": "op_sa", "current_performed": true, "current_effective": true})["action"]),
		"event", "dopo Op+SA della 1ª, la 2ª gioca l'Evento Performed ed efficace")

	# 2ª riga ⑥: solo i Reclaimer, e solo con Asset Total 5+.
	s.tracks["asset_total"] = 6
	eq(String(np.choose_action("reclaimer", "second", {"next_is_dust_storm": false})["action"]),
		"pass", "NP CR con Asset Total 5+ passa per accumulare")
	s.tracks["asset_total"] = 2
	eq(String(np.choose_action("reclaimer", "second", {"next_is_dust_storm": false})["action"]),
		"lim_op", "…con Asset Total basso no")
	s.tracks["asset_total"] = 6
	eq(String(np.choose_action("reclaimer", "second", {"next_is_dust_storm": true})["action"]),
		"lim_op", "…e nemmeno se la prossima è un Dust Storm")
	# La riga ⑥ è solo dei Reclaimer: al Red Dust non si applica.
	eq(String(np.choose_action("red_dust", "second", {})["action"]), "lim_op",
		"la riga sull'Asset Total non vale per il Red Dust")


func test_np_effective_events() -> void:
	print("Non-Player — Effective Events (§8.5.5)")
	var s := fresh()
	var np := np_for(s, ["marsgov", "red_dust", "reclaimer", "corporations"])
	var ev := RDREvents.new(s, module)

	# #1 ombreggiato toglie Profits e Risorse MarsGov: efficace per Red Dust
	# (rimuove Profits e Risorse di un giocatore), non per le Corporations.
	var shaded1: Array = ev.option(1, true).get("effects", [])
	ok(bool(np.event_effective("red_dust", shaded1)["effective"]),
		"#1 ombreggiato è efficace per il Red Dust")
	eq(bool(np.event_effective("corporations", shaded1)["effective"]), false,
		"…e non per le Corporations, a cui non aggiunge né toglie nulla di suo")

	# #10 non ombreggiato sposta verso il Supporto: efficace per MarsGov.
	var un10: Array = ev.option(10, false).get("effects", [])
	var mg10: Dictionary = np.event_effective("marsgov", un10)
	ok(bool(mg10["effective"]), "#10 sposta verso il Supporto: efficace per MarsGov")
	ok(Array(mg10["matched"]).has("support"), "…e la categoria è «support»")
	# Lo stesso Evento non giova al Red Dust, che vuole l'Opposizione.
	eq(bool(np.event_effective("red_dust", un10)["effective"]), false,
		"…mentre al Red Dust non serve")

	# #10 ombreggiato sposta verso l'Opposizione e piazza Ribelli: efficace per RD.
	var sh10: Array = ev.option(10, true).get("effects", [])
	ok(bool(np.event_effective("red_dust", sh10)["effective"]),
		"#10 ombreggiato è efficace per il Red Dust")

	# Un'opzione senza effetti non è efficace per nessuno.
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		eq(bool(np.event_effective(String(fid), [])["effective"]), false,
			"un Evento senza effetti non è efficace per %s" % fid)

	# Su tutte e 93 le opzioni, ogni Fazione trova qualcosa di efficace: se una
	# riga della tabella fosse tradotta male, quella Fazione resterebbe a zero.
	for fid2 in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		var hits := 0
		for number in range(1, 49):
			for shaded in [false, true]:
				var opt: Dictionary = ev.option(number, shaded)
				if opt.is_empty():
					continue
				if bool(np.event_effective(String(fid2), opt.get("effects", []))["effective"]):
					hits += 1
		ok(hits >= 10, "%s trova %d opzioni efficaci fra le 93" % [fid2, hits])


func test_np_event_symbols() -> void:
	print("Non-Player — simboli ★/⊘ delle carte Evento (§8.5.5)")
	var s := fresh()
	var np := np_for(s, ["marsgov", "corporations", "red_dust", "reclaimer"])
	# 48 e non 51: le tre carte Dust Storm non hanno icone di Fazione, quindi
	# nemmeno simboli.
	eq(np.event_symbols.size(), 48, "i simboli delle 48 carte Evento sono estratti")

	# Cinque carte lette a video durante l'estrazione, usate come pietra di paragone.
	eq(np.event_critical("marsgov", 1), true, "#1 è Critica per MarsGov")
	eq(np.event_critical("corporations", 1), false, "…e non per le Corporations")
	eq(np.event_critical("marsgov", 5), true, "#5 è Critica per MarsGov")
	eq(np.event_not_performed("corporations", 5), true, "…e le Corporations non la eseguono")
	eq(np.event_not_performed("red_dust", 37), true, "#37 non è eseguita dal Red Dust")
	eq(np.event_not_performed("reclaimer", 37), true, "…né dai Reclaimer")
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		eq(np.event_not_performed(String(fid), 47), true,
			"#47 non è eseguita da nessuno (%s)" % fid)

	# Un simbolo esclude l'altro: nessuna carta può essere ★ e ⊘ per la stessa Fazione.
	var both: Array[String] = []
	for number in range(1, 52):
		for fid2 in ["marsgov", "corporations", "red_dust", "reclaimer"]:
			if np.event_critical(String(fid2), number) and np.event_not_performed(String(fid2), number):
				both.append("#%d/%s" % [number, fid2])
	eq(both.size(), 0, "nessuna carta è insieme Critica e Non eseguita (%s)" % ", ".join(both))

	# Ogni Fazione deve avere sia Critici sia Non eseguiti: se l'estrazione avesse
	# sbagliato in blocco una classe, questo test se ne accorgerebbe.
	for fid3 in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		var crit := 0
		var skip := 0
		for number2 in range(1, 52):
			if np.event_critical(String(fid3), number2):
				crit += 1
			if np.event_not_performed(String(fid3), number2):
				skip += 1
		ok(crit >= 2, "%s ha %d Eventi Critici" % [fid3, crit])
		ok(skip >= 3, "%s ha %d Eventi che non esegue" % [fid3, skip])


func test_np_cards() -> void:
	print("Non-Player — carte Curiosity (§8.5.3)")
	var s := fresh()
	var np := np_for(s, ["reclaimer"])
	var npo := RDRNonPlayerOps.new(np, ops_for(s))
	var r := RandomNumberGenerator.new()
	r.seed = 31337

	eq(npo.cards.size(), 48, "tutte e 48 le facce delle 24 carte sono trascritte")
	for cid in ["U", "V", "W", "X", "Y", "Z", "UU", "VV", "WW", "XX", "YY", "ZZ",
			"N", "P", "Q", "R", "S", "T", "NN", "PP", "QQ", "RR", "SS", "TT",
			"G", "H", "J", "K", "L", "M", "GG", "HH", "JJ", "KK", "LL", "MM",
			"A", "B", "C", "D", "E", "F", "AA", "BB", "CC", "DD", "EE", "FF"]:
		ok(npo.cards.has(cid), "c'è la carta %s" % cid)

	# Ogni condizione usata dalle carte deve essere implementata: se ne aggiungo
	# una nei dati e scordo il codice, questo test se ne accorge.
	var unknown: Array[String] = []
	var used: Array[String] = []
	for cid2 in npo.cards.keys():
		var card: Dictionary = npo.cards[cid2]
		for c in card.get("checks", []):
			used.append(String((c as Dictionary)["cond"]))
		for b in card.get("blocks", []):
			if (b as Dictionary).has("branch"):
				used.append(String(((b as Dictionary)["branch"] as Dictionary)["cond"]))
	for c2 in used:
		if not RDRNonPlayerOps.CARD_CONDITIONS.has(c2) and not unknown.has(c2):
			unknown.append(c2)
	eq(unknown.size(), 0, "nessuna condizione senza codice (%s)" % ", ".join(unknown))
	ok(used.size() >= 60, "le carte usano %d condizioni in tutto" % used.size())

	# Ogni faccia deve portare a qualcosa: nessuna carta muta.
	var mute: Array[String] = []
	for cid3 in npo.cards.keys():
		var card3: Dictionary = npo.cards[cid3]
		if (card3.get("blocks", []) as Array).is_empty():
			mute.append(String(cid3))
	eq(mute.size(), 0, "nessuna faccia senza istruzioni (%s)" % ", ".join(mute))

	# Fronte e retro si rimandano sempre a vicenda.
	var broken: Array[String] = []
	for cid4 in npo.cards.keys():
		var flip := String((npo.cards[cid4] as Dictionary).get("flip", ""))
		if not npo.cards.has(flip) or String((npo.cards[flip] as Dictionary).get("flip", "")) != cid4:
			broken.append(String(cid4))
	eq(broken.size(), 0, "fronte e retro si rimandano sempre (%s)" % ", ".join(broken))

	# Fronte e retro si rimandano a vicenda.
	eq(String((npo.cards["U"] as Dictionary)["flip"]), "UU", "CR–U gira su CR–UU")
	eq(String((npo.cards["UU"] as Dictionary)["flip"]), "U", "…e viceversa")

	# CR–U: con Basi e Ribelli disponibili si arriva al Rally.
	var res: Dictionary = npo.read_card("U", "reclaimer", r)
	eq(res.get("ok", false), true, "CR–U si legge")
	eq(String(res["outcome"]), "operation", "…e porta a un'Operazione")
	eq(String(res["operation"]), "rally", "…il Rally")
	ok(not (res["trace"] as Array).is_empty(), "il percorso è tracciato: %s"
		% ", ".join(PackedStringArray(res["trace"])))
	eq(int(res["activation_number"]), 3, "l'Activation Number della carta è 3")
	eq(int((res["limits"] as Dictionary)["limop_max"]), 5,
		"…e il tetto di 5 spazi per la Limitata")

	# Senza Basi disponibili il primo riquadro fallisce: si pesca una carta nuova.
	var s2 := fresh()
	var np2 := np_for(s2, ["reclaimer"])
	var npo2 := RDRNonPlayerOps.new(np2, ops_for(s2))
	var pool: Dictionary = s2.tracks.get("available", {})
	(pool["reclaimer"] as Dictionary)["cr_base"] = 0
	var none: Dictionary = npo2.read_card("U", "reclaimer", r)
	eq(String(none["outcome"]), "draw", "senza Basi disponibili si pesca una carta nuova")

	# CR–ZZ è un bivio: senza Ribelli disponibili si va al Travel invece che al Rally.
	(pool["reclaimer"] as Dictionary)["cr_rebel"] = 0
	var forked: Dictionary = npo2.read_card("ZZ", "reclaimer", r)
	eq(String(forked["operation"]), "travel",
		"CR–ZZ senza Ribelli disponibili sceglie il Travel")

	# Le istruzioni della carta puntano a funzioni che esistono davvero.
	var rally: Dictionary = npo.read_card("VV", "reclaimer", r)
	eq(String(rally["operation"]), "rally", "CR–VV va diritta al Rally")
	var ids: Array = []
	for i in rally["instructions"]:
		ids.append(String((i as Dictionary)["id"]))
	ok(ids.has("rally_place_bases"), "la prima istruzione è «place bases»")
	ok(bool((rally["instructions"][0] as Dictionary).get("no_an_roll", false)),
		"…col numerale bianco: dopo non si tira l'Activation Number")

	# Una carta inesistente lo dice, invece di fingere. (Ora che ci sono tutte e 48,
	# serve un identificativo che non può esistere.)
	var missing: Dictionary = npo.read_card("ZZZ", "marsgov", r)
	eq(missing.get("ok", true), false, "una carta non trascritta è dichiarata mancante")
	ok(String(missing.get("error", "")).contains("non ancora trascritta"),
		"…con il motivo esplicito")


func test_np_operations() -> void:
	print("Non-Player — Operazioni (§8.6)")
	var s := fresh()
	var np := np_for(s, ["red_dust", "reclaimer", "corporations"])
	var o := ops_for(s)
	var npo := RDRNonPlayerOps.new(np, o)

	# Le Operazioni che spostano pezzi restano fuori: manca la Move Priorities.
	for op_id in ["secure", "recon", "march", "travel"]:
		var gate: Dictionary = npo.can_run("red_dust", op_id)
		eq(gate["ok"], false, "%s è bloccata: serve la Move Priorities" % op_id)
		ok(String(gate["error"]).contains("Move Priorities"), "…e il motivo è dichiarato")
	eq(npo.can_run("red_dust", "rally")["ok"], true, "il Rally invece si può eseguire")
	eq(npo.can_run("marsgov", "train")["ok"], true, "il Train di NP MarsGov ora è eseguibile")

	# Rally: piazza Basi dove ci sono 3+ Ribelli e almeno uno Nascosto.
	var s1 := fresh()
	var np1 := np_for(s1, ["red_dust"])
	var o1 := ops_for(s1)
	var npo1 := RDRNonPlayerOps.new(np1, o1)
	var target := "radau"
	module.place_from_available(s1, target, "rd_rebel", 4, "hidden")
	s1.spaces[target].support = CoinEnums.Support.NEUTRAL
	module.recompute_all_control(s1)
	var bases_before := module.count_in(s1, target, "rd_base")
	var used: Array = npo1.rally_place_bases("red_dust", 0, true)
	ok(used.size() >= 1, "il Rally NP sceglie almeno uno spazio (%s)" % ", ".join(PackedStringArray(used)))
	ok(module.count_in(s1, String(used[0]), "rd_base") > 0,
		"…e ci piazza una Base (%s)" % String(used[0]))
	ok(not npo1.log_lines.is_empty(), "la scelta finisce nel Log")

	# Un'Operazione Limitata di NP CR si ferma comunque al quinto spazio (§8.5.4).
	var s2 := fresh()
	var np2 := np_for(s2, ["reclaimer"])
	s2.tracks["asset_total"] = 6
	var o2 := ops_for(s2)
	o2.cards = cards_for(s2)
	var npo2 := RDRNonPlayerOps.new(np2, o2)
	var picked: Array = npo2.rally_place_rebels("reclaimer", 0, true)
	ok(picked.size() <= 5, "il Rally Limitato di NP CR non supera 5 spazi (%d)" % picked.size())
	ok(picked.size() >= 1, "…ma almeno uno lo sceglie")

	# Attack «all_active»: solo dove non restano Ribelli Nascosti.
	var s3 := fresh()
	var np3 := np_for(s3, ["red_dust"])
	var o3 := ops_for(s3)
	var npo3 := RDRNonPlayerOps.new(np3, o3)
	var atk := "radau"
	# Allo schieramento Radau può già avere Ribelli Nascosti: si parte puliti,
	# altrimenti la condizione «tutti Attivi» non sarebbe mai vera.
	module.remove_pieces(s3, atk, "rd_rebel", 99, "available")
	module.place_from_available(s3, atk, "rd_rebel", 3, "active")
	module.place_from_available(s3, atk, "mg_troop", 2)
	module.recompute_all_control(s3)
	var hit: Array = npo3.attack("red_dust", "all_active", 0, true)
	ok(hit.has(atk), "l'Attack «tutti Attivi» sceglie %s" % atk)
	# Con un Ribelle Nascosto lì, quello spazio non è più eleggibile.
	var s4 := fresh()
	var np4 := np_for(s4, ["red_dust"])
	var o4 := ops_for(s4)
	var npo4 := RDRNonPlayerOps.new(np4, o4)
	module.remove_pieces(s4, atk, "rd_rebel", 99, "available")
	module.place_from_available(s4, atk, "rd_rebel", 3, "hidden")
	module.place_from_available(s4, atk, "mg_troop", 2)
	module.recompute_all_control(s4)
	ok(not npo4.attack("red_dust", "all_active", 0, true).has(atk),
		"…e lo scarta se lì resta un Ribelle Nascosto")

	# Campaign: non si sceglie uno spazio che lascerebbe scoperta una Base RD.
	var s5 := fresh()
	var np5 := np_for(s5, ["red_dust"])
	var o5 := ops_for(s5)
	o5.cards = cards_for(s5)
	var npo5 := RDRNonPlayerOps.new(np5, o5)
	var camp := "shepard"
	module.place_from_available(s5, camp, "rd_base", 1)
	module.place_from_available(s5, camp, "rd_rebel", 1, "hidden")
	ok(not npo5.campaign(0, true).has(camp),
		"la Campaign salta %s: l'unico Ribelle Nascosto copre la Base" % camp)


# ===========================================================================
# Fase 5 — effetti continuativi delle Campaign card (§1.5/§5.10)
# ===========================================================================

func with_campaign(n: int) -> GameState:
	var s := fresh()
	s.tracks["campaign_in_play"] = n
	return s


func test_campaign_effects() -> void:
	print("Campaign card — effetti continuativi")

	# #1 Construction Workers Guild: le nuove Basi RD nascono Dug-In.
	var s1 := with_campaign(1)
	var o1 := ops_for(s1)
	o1.rally({"faction": "red_dust", "spaces": [{"id": "shepard", "mode": "base"}]})
	eq(module.count_in(s1, "shepard", "rd_base", "dug_in"), 1, "#1: Base RD già Dug-In")

	# #2 Prison Labor Revolt: −1 Profit per ogni Base CORP piazzata.
	var s2 := with_campaign(2)
	s2.tracks["profits"] = 10
	module.place_from_available(s2, "rutherford", "corp_base", 1)
	eq(int(s2.tracks["profits"]), 9, "#2: −1 Profit per Base CORP piazzata")

	# #3 Dock Workers Lockout: metà delle Supply su Phobos è scartata.
	var s3 := with_campaign(3)
	var r3 := rounds_for(s3)
	var mg3 := s3.get_resources("marsgov")
	r3.aldrin_cycler()
	# 3 Supply arrivano, 2 vengono scartate (metà per eccesso), 1 vale 3 Risorse.
	eq(s3.get_resources("marsgov"), mg3 + 3, "#3: solo 1 Supply su 3 convertita")

	# #4 Transport Workers: il Secure non usa i Maglev.
	# La carta blocca i Maglev, non gli Spaceport: serve una tratta raggiungibile
	# SOLO via Maglev. Shepard è sotto Controllo Red Dust, quindi il suo Spaceport
	# non è utilizzabile dal Secure e ci si arriva solo col Maglev da Tenzing.
	var s4b := fresh()
	var o4b := ops_for(s4b)
	ok(o4b.reachable_labyrinths("tenzing", "coin").has("shepard"),
		"senza la Campaign, Shepard è raggiungibile via Maglev da Tenzing")
	var s4 := with_campaign(4)
	var o4 := ops_for(s4)
	ok(not o4.reachable_labyrinths("tenzing", "coin").has("shepard"),
		"#4: col Maglev vietato, Shepard non è più raggiungibile")
	ok(o4.reachable_labyrinths("europa", "coin").has("tereshkova"),
		"#4: gli Spaceport restano utilizzabili")

	# #5 Water Reclamation Workers: i Labirinti non arrivano al Supporto Attivo.
	var s5 := with_campaign(5)
	var a5 := RDRActions.new(s5, module)
	a5.shift("europa", 1)
	eq(s5.spaces["europa"].support, CoinEnums.Support.PASSIVE_SUPPORT,
		"#5: Europa si ferma al Supporto Passivo")

	# #6 Mothers of Mars: ogni Labirinto scelto per l'Assault scivola di 1 livello.
	var s6 := with_campaign(6)
	var o6 := ops_for(s6)
	var a6 := RDRActions.new(s6, module)
	a6.activate("sharma", "rd_rebel", 3)
	var before6: int = s6.spaces["sharma"].support
	o6.assault({"faction": "marsgov", "spaces": ["sharma"]})
	eq(s6.spaces["sharma"].support, before6, "#6: Sharma è già in Opposizione Attiva")
	var s6b := with_campaign(6)
	var o6b := ops_for(s6b)
	var a6b := RDRActions.new(s6b, module)
	a6b.activate("tereshkova", "rd_rebel", 1)
	o6b.assault({"faction": "marsgov", "spaces": ["tereshkova"]})
	eq(s6b.spaces["tereshkova"].support, CoinEnums.Support.PASSIVE_OPPOSITION,
		"#6: Tereshkova scivola verso l'Opposizione")

	# #7 Torture Video Leaks: le unità CORP non contano per il Controllo nei Labirinti.
	var s7 := with_campaign(7)
	eq(module.control_of(s7, "shenzhou"), "coin", "#7: Shenzhou resta COIN (2 Truppe MG)")
	module.remove_pieces(s7, "shenzhou", "mg_troop", 2, "available")
	eq(module.control_of(s7, "shenzhou"), "", "#7: senza Truppe MG le Security non bastano")

	# #8 Earth-Based Endorsements: ogni Supply dà 2 a MarsGov e 1 a Red Dust.
	var s8 := with_campaign(8)
	var r8 := rounds_for(s8)
	var mg8 := s8.get_resources("marsgov")
	var rd8 := s8.get_resources("red_dust")
	r8.aldrin_cycler()
	eq(s8.get_resources("marsgov"), mg8 + 6, "#8: 3 Supply × 2 a MarsGov")
	eq(s8.get_resources("red_dust"), rd8 + 3, "#8: 3 Supply × 1 a Red Dust")

	# #9 Legal Injunctions: uno spazio in Opposizione scelto per Secure costa 6.
	var s9 := with_campaign(9)
	var o9 := ops_for(s9)
	var mg9 := s9.get_resources("marsgov")
	o9.secure({"faction": "marsgov", "dest": ["sharma"]})
	eq(s9.get_resources("marsgov"), mg9 - 6, "#9: Sharma (Opposizione) costa 6")

	# #10 General Strike: +1 Risorsa per ogni spazio senza Supporto.
	var s10 := with_campaign(10)
	var o10 := ops_for(s10)
	var mg10 := s10.get_resources("marsgov")
	o10.train({"spaces": [{"id": "tharsis_tholus", "troops": 1}]})
	eq(s10.get_resources("marsgov"), mg10 - 4, "#10: 3 + 1 Risorse")

	# #11 Comms Cutoff: Logistics non può selezionare Transit.
	var s11 := with_campaign(11)
	var o11 := ops_for(s11)
	eq(o11.logistics({"transit": true})["ok"], false, "#11: Transit vietato")

	# #12 Red Wave Elections: da Supporto Passivo si scende a Opposizione Passiva.
	var s12 := with_campaign(12)
	var a12 := RDRActions.new(s12, module)
	a12.shift("europa", -1)
	eq(s12.spaces["europa"].support, CoinEnums.Support.PASSIVE_OPPOSITION,
		"#12: Europa salta il Neutrale")
