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
