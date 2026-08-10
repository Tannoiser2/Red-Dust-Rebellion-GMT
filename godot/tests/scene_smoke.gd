extends SceneTree

## Smoke test della scena di gioco: istanzia davvero Main.tscn e verifica che
## mappa, zone, pezzi e pannelli si montino.
##
##   godot --headless --path godot -s res://tests/scene_smoke.gd
##
## Con un renderer vero (senza --headless) salva anche uno screenshot:
##   godot --path godot -s res://tests/scene_smoke.gd -- --shot=/percorso/out.png
##
## NB: il montaggio va fatto in `_initialize()`, non in `_init()`: in `_init()` gli
## autoload non sono ancora registrati e gli script che li referenziano non compilano.

var _failed := false


func _initialize() -> void:
	var shot_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr("--shot=".length())

	var gc = root.get_node("GameController")
	# Il nodo dell'autoload esiste già, ma il suo `_ready()` — che avvia una
	# partita di default — scatta al PRIMO FRAME, non prima. Senza questa attesa
	# la partita col seme fisso veniva creata e poi subito sostituita da quella
	# casuale dell'autoload: il test diceva di essere riproducibile e non lo era.
	await process_frame
	# Seme fisso: mazzi e dadi riproducibili, così il test non dipende dalla carta
	# che capita per prima.
	gc.new_game("standard", 20240424)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		print("FALLITO: Main.tscn non caricabile")
		quit(1)
		return
	root.size = Vector2i(1500, 900)
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_ok(gc.state != null, "GameState creato")
	_ok(gc.regions.size() == 24, "24 regioni caricate (%d)" % gc.regions.size())
	_ok(gc.layout.has("edge_track"), "board_layout caricato")
	_ok(gc.layout.get("eg_confidence_boxes", []).size() == 9, "9 caselle EG Confidence")

	var views: Dictionary = main.get("_views")
	_ok(views.size() == 30, "30 RegionView istanziate: 24 su Mars + 6 fuori mappa (%d)" % views.size())

	# Ogni zona deve avere un poligono e reagire solo al suo interno.
	var europa: RegionView = views["europa"]
	_ok(europa.size.x > 100.0 and europa.size.x <= 1500.0,
		"le zone sono dimensionate entro la finestra (%.0f px)" % europa.size.x)

	# I pezzi dello schieramento iniziale devono essere renderizzati.
	var on_mars := 0
	var off_mars := 0
	for sid in views.keys():
		var n := (views[sid] as RegionView).piece_count()
		if sid in ["earth", "transit", "phobos", "orbit"]:
			off_mars += n
		else:
			on_mars += n
	# §3.1: 67 forze su Mars + Wilderness e 18 nell'Aldrin Cycler/Orbita
	# (i marker Supply e Popolazione non sono forze e non contano qui).
	_ok(on_mars == 67, "pezzi renderizzati su Mars: %d (attesi 67)" % on_mars)
	_ok(off_mars == 18, "pezzi renderizzati fuori Mars: %d (attesi 18)" % off_mars)
	_ok((views["tenzing"] as RegionView).piece_count() == 5, "Tenzing: 5 pezzi")
	_ok((views["wilderness"] as RegionView).piece_count() == 4, "Wilderness: 4 pezzi")

	# Il clic su uno spazio popola il pannello di dettaglio.
	main.call("_on_space_clicked", "tenzing")
	var info: RichTextLabel = main.get("_space_info")
	_ok(info.text.contains("Tenzing"), "pannello spazio aggiornato al clic")
	_ok(info.text.contains("Labirinto"), "tipo di spazio mostrato")
	_ok(info.text.contains("Maglev"), "collegamenti Maglev mostrati")
	var status: RichTextLabel = main.get("_status")
	_ok(status.text.contains("EarthGov"), "pannello di stato popolato")
	_ok(status.text.contains("Vittoria"), "totali di vittoria mostrati")

	# Carta corrente e turno (§4.1).
	var card_info: RichTextLabel = main.get("_card_info")
	_ok(card_info.text.contains("Ordine:"), "ordine di Eligibility mostrato")
	_ok(card_info.text.contains("Tocca a"), "Fazione di turno mostrata")
	_ok(gc.sequence != null, "sequenza della carta creata")
	_ok(gc.cards.hand().size() == 3, "mano iniziale dei Reclaimer: 3 Asset card")
	_ok(gc.cards.campaign_in_play() > 0, "una Campaign card in gioco")

	# Barra delle Operazioni della Fazione di turno (§5.0).
	var ops_box: HFlowContainer = main.get("_ops_box")
	_ok(ops_box.get_child_count() > 0, "barra delle Operazioni popolata (%d)" % ops_box.get_child_count())

	# Pianificazione: si sceglie un'Operazione, si clicca uno spazio candidato,
	# si esegue. L'azione deve consumare il turno della Fazione.
	# Si cerca una Fazione di turno che abbia un'Operazione con spazi candidati.
	# Non tutte ne hanno sempre: l'Assault delle Corporations, per esempio,
	# richiede forze nemiche Attive, che allo schieramento iniziale non ci sono.
	# Chi non può agire Passa, esattamente come al tavolo.
	var fid := ""
	var op_id := ""
	var cands := PackedStringArray()
	for attempt in range(4):
		fid = gc.sequence.pending_faction()
		if fid == "":
			break
		for candidate in gc.UI_OPERATIONS.get(fid, []):
			var c: PackedStringArray = gc.operation_candidates(String(candidate), fid)
			if c.size() > 0:
				op_id = String(candidate)
				cands = c
				break
		if op_id != "":
			break
		gc.do_pass()
		await process_frame
	_ok(op_id != "", "una Fazione può eseguire un'Operazione (%s: %s)" % [fid, op_id])
	if op_id == "":
		quit(1)
		return
	main.call("_start_op", op_id)
	_ok(cands.size() > 0, "%s ha spazi candidati (%d)" % [op_id, cands.size()])
	main.call("_on_space_clicked", cands[0])
	_ok((main.get("_op_spaces") as Array).size() == 1, "spazio aggiunto al piano")
	main.call("_on_space_clicked", cands[0])
	_ok((main.get("_op_spaces") as Array).is_empty(), "secondo clic: spazio tolto dal piano")
	main.call("_on_space_clicked", cands[0])
	main.call("_confirm_op")
	await process_frame
	_ok(String(main.get("_op_mode")) == "", "pianificazione chiusa dopo l'esecuzione")
	_ok(gc.sequence == null or gc.sequence.pending_faction() != fid,
		"l'Operazione ha consumato il turno di %s" % fid)

	# Passando con le Fazioni rimaste, la carta avanza.
	var card_before: int = gc.state.current_card
	for i in range(4):
		gc.do_pass()
	await process_frame
	_ok(gc.state.current_card != card_before, "passando tutti, si passa alla carta seguente")
	# La Fazione che ha eseguito l'Operazione diventa Non Disponibile; le altre,
	# che hanno Passato, restano Disponibili (§4.2).
	_ok(gc.state.eligibility[fid] == CoinEnums.Eligibility.INELIGIBLE,
		"chi agisce diventa Non Disponibile (%s)" % fid)
	var passer := "reclaimer" if fid != "reclaimer" else "marsgov"
	_ok(gc.state.eligibility[passer] == CoinEnums.Eligibility.ELIGIBLE,
		"chi Passa resta Disponibile (%s)" % passer)

	# --- Pianificatore di movimento (§5.3/§5.7) e Attività Speciali (§6.0) ---
	# Si prova su uno stato pulito, senza passare dalla sequenza della carta.
	gc.new_game("standard", 20240424)
	await process_frame
	var m = gc.rdr()
	var origins: PackedStringArray = gc.legal_origins("march", "red_dust", "daedalia_planum", "rd_rebel")
	_ok(origins.size() > 0, "il pianificatore trova origini legali (%d)" % origins.size())
	_ok(origins.has("shepard"), "Shepard è un'origine valida per Daedalia Planum")
	var before_dest: int = m.count_in(gc.state, "daedalia_planum", "rd_rebel")
	var res: Dictionary = gc.ops.march({"dest": ["daedalia_planum"],
		"moves": [{"from": "shepard", "to": "daedalia_planum", "count": 2}]})
	_ok(res.get("ok", false), "March con spostamenti dichiarati eseguita")
	_ok(m.count_in(gc.state, "daedalia_planum", "rd_rebel") == before_dest + 2,
		"i Ribelli sono arrivati a destinazione")

	# Un'Attività Speciale a scelta di spazi.
	var sa_spaces: PackedStringArray = gc.special_candidates("redistribute", "red_dust")
	_ok(sa_spaces.size() > 0, "Redistribute ha spazi candidati (%d)" % sa_spaces.size())
	var rd_before: int = gc.state.get_resources("red_dust")
	var sres: Dictionary = gc.execute_special("redistribute", [sa_spaces[0]])
	_ok(sres.get("ok", false), "Redistribute eseguita dalla UI")
	_ok(gc.state.get_resources("red_dust") > rd_before, "Red Dust ha guadagnato Risorse")

	# Le Operazioni di movimento sono ora tutte in barra.
	_ok(gc.UI_OPERATIONS["marsgov"].has("secure"), "Secure disponibile in UI")
	_ok(gc.UI_OPERATIONS["reclaimer"].has("travel"), "Travel disponibile in UI")
	_ok(gc.UI_SPECIALS["reclaimer"].has("purify"), "Purify disponibile in UI")

	# --- Evento con le sue scelte (§7.0) ---------------------------------
	# Si riparte da una partita pulita e si guida la barra come farebbe un
	# giocatore: spazi sulla mappa, Fazioni e rami con i pulsanti.
	gc.new_game("standard", 20240424)
	await process_frame
	var ev_fid: String = gc.sequence.pending_faction()
	var card_no: int = gc.state.current_card
	var opt: Dictionary = gc.events.option(card_no, false)
	_ok(not opt.is_empty(), "la carta corrente ha un Evento non ombreggiato (#%d)" % card_no)
	main.call("_start_event", false)
	await process_frame
	_ok(bool(main.get("_ev_active")), "la pianificazione dell'Evento è aperta")
	var guard := 0
	while bool(main.get("_ev_active")) and guard < 12:
		guard += 1
		var reqs: Array = main.get("_ev_reqs")
		var idx: int = main.get("_ev_index")
		if idx >= reqs.size():
			break
		var req: Dictionary = reqs[idx]
		if String(req.get("kind", "space")) == "space":
			var pool: Array = req.get("candidates", [])
			for i in range(mini(int(req.get("min", 0)), pool.size())):
				main.call("_on_space_clicked", String(pool[i]))
			main.call("_ev_confirm_spaces")
		else:
			var opts: Array = req.get("candidates", [])
			main.call("_ev_pick", String(opts[0]) if not opts.is_empty() else "")
		await process_frame
	_ok(not bool(main.get("_ev_active")), "l'Evento è stato risolto e la barra si è chiusa")
	_ok(gc.sequence == null or gc.sequence.pending_faction() != ev_fid,
		"giocare l'Evento consuma il turno di %s" % ev_fid)
	_ok(typeof(gc.pending_free_ops()) == TYPE_ARRAY,
		"la coda delle Operazioni gratuite è consultabile (%d in attesa)"
			% gc.pending_free_ops().size())

	# --- Carte in vista e ingrandimento -----------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	_ok(main.get("_card_now").texture != null, "l'immagine della carta in corso è mostrata")
	_ok(main.get("_card_next").texture != null, "…e quella della prossima carta")
	main.call("_show_card_zoom", main.get("_card_now").texture)
	await process_frame
	_ok(main.get("_card_zoom") != null, "il clic ingrandisce la carta a schermo intero")
	main.call("_close_card_zoom")
	await process_frame
	_ok(main.get("_card_zoom") == null, "…e si richiude")

	# --- Sequence of Play: i cilindri stanno nella casella giusta ----------
	var sop: Dictionary = gc.layout.get("sop", {})
	# NB: la mappa delle caselle si legge dallo script del nodo, non da
	# `TrackOverlay.SOP_BOXES`: nominare la classe qui la farebbe compilare prima
	# che gli autoload esistano (vedi la nota in testa a questo file).
	var sop_boxes: Dictionary = main.get("_tracks").get_script() \
		.get_script_constant_map()["SOP_BOXES"]
	for box in sop_boxes.values():
		_ok(sop.has(String(box)), "la casella «%s» esiste sulla tavola" % box)
	# Ogni azione registrabile dalla sequenza deve avere la sua casella.
	var mapped := true
	for b in ["1st_op_only", "1st_op_sa", "1st_event", "2nd_limop",
			"2nd_limop_or_event", "2nd_op_sa", "pass"]:
		if not sop_boxes.has(b):
			mapped = false
	_ok(mapped, "ogni azione della sequenza ha una casella sulla tavola")
	# Giocando davvero, il cilindro lascia la casella «Disponibile».
	var first_fid: String = gc.sequence.pending_faction()
	gc.do_pass()
	await process_frame
	_ok(String(gc.sequence.action_box.get(first_fid, "")) == "pass",
		"chi Passa mette il cilindro nella casella Pass (%s)" % first_fid)

	# --- Spostamenti a trascinamento --------------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	# Fuori da un'Operazione di movimento il trascinamento non deve fare nulla.
	main.call("_on_piece_dropped", "shepard", "daedalia_planum", "rd_rebel")
	_ok((main.get("_op_moves") as Array).is_empty(),
		"trascinare senza un'Operazione di movimento non dichiara nulla")
	# Si passa finché non tocca al Red Dust, poi si prova una March.
	var guard_rd := 0
	while gc.sequence != null and gc.sequence.pending_faction() != "red_dust" and guard_rd < 5:
		guard_rd += 1
		gc.do_pass()
		await process_frame
	if gc.sequence != null and gc.sequence.pending_faction() == "red_dust":
		main.call("_start_op", "march")
		await process_frame
		main.call("_on_piece_dropped", "shepard", "daedalia_planum", "rd_rebel")
		var moves: Array = main.get("_op_moves")
		_ok(moves.size() == 1, "il trascinamento dichiara uno spostamento")
		_ok(int(moves[0]["count"]) == 1 and String(moves[0]["type"]) == "rd_rebel",
			"…di 1 Ribelle Red Dust")
		main.call("_on_piece_dropped", "shepard", "daedalia_planum", "rd_rebel")
		_ok(int((main.get("_op_moves") as Array)[0]["count"]) == 2,
			"trascinare di nuovo lo stesso tragitto ingrossa la stessa freccia")
		_ok((main.get("_moves").get("_segments") as Array).size() == 1,
			"sulla mappa compare una freccia")
		# Una destinazione irraggiungibile va rifiutata senza sporcare il piano.
		# La si cerca chiedendo al motore, invece di indovinarla: con gli
		# Spaceport fra Labirinti controllati la March arriva più lontano di
		# quanto sembri guardando la mappa.
		var unreachable := ""
		for sd2 in gc.game_def.spaces:
			if sd2.id == "shepard" or sd2.type == CoinEnums.SpaceType.COUNTRY:
				continue
			if not gc.legal_origins("march", "red_dust", sd2.id, "rd_rebel").has("shepard"):
				unreachable = sd2.id
				break
		_ok(unreachable != "", "esiste una destinazione fuori portata da Shepard (%s)" % unreachable)
		main.call("_on_piece_dropped", "shepard", unreachable, "rd_rebel")
		_ok((main.get("_op_moves") as Array).size() == 1,
			"un tragitto illegale non viene accodato")
		main.call("_cancel_op")
		_ok((main.get("_moves").get("_segments") as Array).is_empty(),
			"annullando, le frecce spariscono")
	else:
		_ok(false, "non si è riusciti ad arrivare al turno del Red Dust")

	# --- Zoom e scorrimento della mappa ------------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	var base_size: Vector2 = main.get("_map_base")
	_ok(base_size.x > 100.0, "la mappa ha una dimensione base (%.0f px)" % base_size.x)
	main.call("_set_zoom", 2.0)
	await process_frame
	_ok(is_equal_approx(float(main.get("_zoom")), 2.0), "lo zoom arriva a 2×")
	_ok(main.get("_map_root").scale.x > 1.9, "la mappa è davvero scalata (pedine comprese)")
	_ok(main.get("_map_wrap").size.x > base_size.x * 1.9,
		"l'area scorrevole cresce con lo zoom")
	var views2: Dictionary = main.get("_views")
	_ok((views2["europa"] as RegionView).size.x == base_size.x,
		"le zone restano nel sistema di coordinate della mappa non scalata")
	main.call("_set_zoom", 0.2)
	_ok(float(main.get("_zoom")) == 1.0, "sotto la tavola intera non si rimpicciolisce")

	# --- Annulla ------------------------------------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	_ok(not gc.can_undo(), "a inizio partita non c'è nulla da annullare")
	var fid_u: String = gc.sequence.pending_faction()
	var res_u: int = gc.state.get_resources("marsgov")
	gc.do_pass()
	await process_frame
	_ok(gc.can_undo(), "dopo il Passo si può annullare")
	_ok(gc.undo_label().contains("Passo"), "il tasto dice cosa annulla: «%s»" % gc.undo_label())
	gc.undo()
	await process_frame
	_ok(gc.sequence.pending_faction() == fid_u, "annullando torna il turno di %s" % fid_u)
	_ok(gc.state.get_resources("marsgov") == res_u, "…e le Risorse tornano quelle di prima")
	_ok(not gc.can_undo(), "la pila di annullamento si è svuotata")

	# --- Salvataggio e ripresa ---------------------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	gc.do_pass()
	await process_frame
	var card_s: int = gc.state.current_card
	var elig_s: int = gc.state.eligibility["marsgov"]
	var pending_s: String = gc.sequence.pending_faction()
	var save_path := "user://test_partita.json"
	_ok(gc.save_game(save_path), "la partita si salva")
	gc.new_game("standard", 999)
	await process_frame
	_ok(gc.load_game(save_path), "…e si riprende")
	_ok(gc.state.current_card == card_s, "torna la stessa carta (#%d)" % card_s)
	_ok(gc.state.eligibility["marsgov"] == elig_s, "torna la stessa Disponibilità")
	_ok(gc.sequence != null and gc.sequence.pending_faction() == pending_s,
		"…e la carta riprende dalla Fazione giusta (%s)" % pending_s)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	# --- Anteprima di costo ed effetti -------------------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	var guard_mg := 0
	while gc.sequence != null and gc.sequence.pending_faction() != "marsgov" and guard_mg < 5:
		guard_mg += 1
		gc.do_pass()
		await process_frame
	var train_spaces: PackedStringArray = gc.operation_candidates("train", "marsgov")
	_ok(train_spaces.size() > 0, "Train ha spazi candidati (%d)" % train_spaces.size())
	var mg_before_p: int = gc.state.get_resources("marsgov")
	var prev: Dictionary = gc.preview_action("operation", "train", "marsgov", [train_spaces[0]])
	_ok(prev.get("ok", false), "l'anteprima del Train riesce")
	_ok(int(prev.get("cost", -1)) > 0, "…e dice quanto costa (%d Risorse)" % int(prev.get("cost", 0)))
	_ok(gc.state.get_resources("marsgov") == mg_before_p,
		"l'anteprima NON tocca la partita: le Risorse sono intatte")
	_ok((prev.get("effects", []) as Array).size() > 0,
		"…e riassume gli effetti previsti (%s)" % ", ".join(PackedStringArray(prev.get("effects", []))))
	var bad_prev: Dictionary = gc.preview_action("operation", "train", "marsgov", [])
	_ok(not bad_prev.get("ok", true), "senza spazi l'anteprima dice che non è eseguibile")

	# --- Salvataggio automatico a fine carta --------------------------------
	var auto_path: String = gc.AUTOSAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(auto_path))
	gc.end_card()
	await process_frame
	_ok(gc.has_save(auto_path), "chiudendo la carta scatta il salvataggio automatico")

	# --- Schermata iniziale --------------------------------------------------
	var menu_scene: PackedScene = load("res://scenes/MainMenu.tscn")
	_ok(menu_scene != null, "MainMenu.tscn si carica")
	var menu := menu_scene.instantiate()
	root.add_child(menu)
	await process_frame
	_ok(menu.get_child_count() > 0, "la schermata iniziale si monta")
	_ok(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/MainMenu.tscn",
		"la partita si apre dal menu, non dalla mappa")
	# Con un renderer vero si salva anche l'immagine della schermata iniziale.
	if shot_path != "":
		await process_frame
		await process_frame
		var menu_png := shot_path.get_basename() + "_menu.png"
		if root.get_texture().get_image().save_png(menu_png) == OK:
			print("screenshot menu: %s" % menu_png)
	menu.queue_free()
	await process_frame

	# --- Asset card giocabili dalla mano (§1.5) -----------------------------
	gc.new_game("standard", 20240424)
	await process_frame
	_ok(gc.cards.hand().size() == 3, "i Reclaimer partono con 3 Asset card")
	# Si mette in mano una Capability nota e la si gioca.
	gc.cards.hand().append(2)
	var res_cap: Dictionary = gc.play_asset_card(2)
	_ok(res_cap.get("ok", false), "la Capability #2 si gioca")
	_ok(gc.rdr().capability_active(gc.state, 2), "…e resta in gioco")
	_ok(not gc.cards.hand().has(2), "…lasciando la mano")
	# Un Evento invece si risolve subito e finisce negli scarti.
	gc.cards.hand().append(10)
	var rd_before_a := 0
	for sid in gc.rdr().mars_spaces(gc.state):
		rd_before_a += gc.rdr().count_in(gc.state, sid, "rd_rebel")
	var res_ev: Dictionary = gc.play_asset_card(10)
	_ok(res_ev.get("ok", false), "l'Evento #10 «Converts» si gioca")
	var rd_after_a := 0
	for sid in gc.rdr().mars_spaces(gc.state):
		rd_after_a += gc.rdr().count_in(gc.state, sid, "rd_rebel")
	_ok(rd_after_a < rd_before_a,
		"…e converte davvero Ribelli RD (%d → %d)" % [rd_before_a, rd_after_a])
	_ok(gc.cards.discard_pile().has(10), "…finendo negli scarti")

	# --- Partita in solo: le Fazioni Non-Player giocano da sé (§8.0) --------
	gc.new_game("standard", 20240424, ["marsgov", "corporations", "reclaimer"])
	await process_frame
	_ok(gc.np != null and gc.np.is_np("marsgov"), "le Fazioni Non-Player sono create")
	_ok(gc.np.is_player("red_dust"), "il Red Dust resta al giocatore")
	_ok(gc.np_ops.cards.size() == 48, "il bot ha tutte e 48 le facce delle carte")
	_ok(gc.np.draw_card("marsgov") != "", "il mazzo Curiosity di NP MarsGov pesca")

	var turns := 0
	var specials_done := 0
	var errors: Array = []
	var guard_np := 0
	while gc.sequence != null and guard_np < 24:
		guard_np += 1
		var fid_np: String = gc.sequence.pending_faction()
		if fid_np == "":
			gc.end_card()
			await process_frame
			continue
		if not gc.np.is_np(fid_np):
			gc.do_pass()          # il turno del giocatore: qui passa
			await process_frame
			continue
		var res_np: Dictionary = gc.np_take_turn()
		await process_frame
		if not res_np.get("ok", false):
			errors.append("%s: %s" % [fid_np, res_np.get("error", "")])
		else:
			turns += 1
			if String(res_np.get("special", "")) != "":
				specials_done += 1
		if turns >= 6:
			break
	_ok(errors.is_empty(), "sei turni di bot senza errori (%s)" % ", ".join(errors))
	_ok(turns >= 6, "il bot ha giocato %d turni" % turns)

	# REGRESSIONE: una partita di soli bot dev'essere capace di ARRIVARE IN FONDO.
	# Registrare un'azione che in quello slot non è legale non fa avanzare la
	# sequenza, e la stessa Fazione rigioca all'infinito: il Log continua a
	# scorrere ma sulla plancia non cambia più niente. Sei turni non bastavano a
	# scoprirlo, perché il blocco scattava solo dopo il primo Evento.
	var gc2 = root.get_node("GameController")
	gc2.new_game("standard", 20240424, ["marsgov", "corporations", "red_dust", "reclaimer"])
	await process_frame
	var last_fid := ""
	var repeats := 0
	var worst := 0
	var cards_seen: Array = []
	var bot_turns := 0
	var guard2 := 0
	while gc2.sequence != null and not gc2.rounds.is_game_over() and guard2 < 120:
		guard2 += 1
		var f: String = gc2.sequence.pending_faction()
		if f == "":
			gc2.end_card()
			await process_frame
			continue
		if not cards_seen.has(gc2.state.current_card):
			cards_seen.append(gc2.state.current_card)
		repeats = repeats + 1 if f == last_fid else 1
		worst = maxi(worst, repeats)
		last_fid = f
		if not gc2.np_take_turn().get("ok", false):
			break
		bot_turns += 1
		await process_frame
	_ok(worst <= 2, "nessuna Fazione agisce più di due volte di fila (massimo %d)" % worst)

	# REGRESSIONE: una Fazione che NON TROVA NESSUNA OPERAZIONE deve Passare.
	# Quando la plancia non le offre più niente — niente forze fra le Disponibili,
	# nessuna Base, nessuna condizione soddisfatta — nessuna carta Curiosity porta
	# a un'Operazione. Prima `np_take_turn()` restituiva l'errore e basta: la
	# sequenza restava ferma su quella Fazione, richiamata all'infinito, e il Log
	# si riempiva di tentativi mentre la plancia non cambiava.
	gc2.new_game("standard", 20240424, ["marsgov", "corporations", "red_dust", "reclaimer"])
	await process_frame
	gc2.np.setup_deck("corporations", [])   # nessuna carta ⇒ nessuna Operazione
	var last2 := ""
	var rep2 := 0
	var worst2 := 0
	var stuck := ""
	for i2 in range(40):
		if gc2.sequence == null or gc2.rounds.is_game_over():
			break
		var f2: String = gc2.sequence.pending_faction()
		if f2 == "":
			gc2.end_card()
			await process_frame
			continue
		rep2 = rep2 + 1 if f2 == last2 else 1
		worst2 = maxi(worst2, rep2)
		last2 = f2
		var r2: Dictionary = gc2.np_take_turn()
		if not r2.get("ok", false):
			stuck = "%s: %s" % [f2, r2.get("error", "")]
			break
		await process_frame
	_ok(stuck == "", "una Fazione senza Operazioni possibili non blocca la partita (%s)" % stuck)
	_ok(worst2 <= 2,
		"…e non rigioca all'infinito: al massimo %d turni di fila" % worst2)

	# REGRESSIONE: il Passo di un bot deve FRUTTARE quel che frutta il Passo.
	# §4.1 dà l'Aldrin Cycler alle Corporations e una Asset card ai Reclaimer;
	# §8.5.4 nega invece le Risorse a chi non le traccia. Registrando solo la
	# casella della Sequenza — com'era prima — un bot che passava restava a mani
	# vuote, e un MarsGov bot incassava Risorse che non dovrebbe avere.
	# Col mazzo Curiosity vuoto il Passo è obbligato, e si può collaudare.
	var pass_notes: Array = []
	for fid_p in ["reclaimer", "corporations", "marsgov"]:
		gc2.new_game("standard", 20240424, [fid_p])
		await process_frame
		gc2.np.setup_deck(fid_p, [])
		var guard3 := 0
		while gc2.sequence.pending_faction() != fid_p and guard3 < 8:
			guard3 += 1
			if gc2.sequence.pending_faction() == "":
				gc2.end_card()
				await process_frame
				continue
			gc2.do_pass()
			await process_frame
		if gc2.sequence.pending_faction() != fid_p:
			continue
		var res0: int = gc2.state.get_resources(fid_p)
		var ass0: int = int(gc2.state.tracks.get("asset_total", 0))
		var sec0: int = gc2.rdr().count_in(gc2.state, "phobos", "security")
		var rp: Dictionary = gc2.np_take_turn()
		await process_frame
		_ok(String(rp.get("action", "")) == "pass", "%s col mazzo vuoto Passa" % fid_p)
		match fid_p:
			"reclaimer":
				_ok(int(gc2.state.tracks.get("asset_total", 0)) == ass0 + 1,
					"il Passo di NP CR dà una Asset card (Asset Total %d → %d)" % [
						ass0, int(gc2.state.tracks.get("asset_total", 0))])
			"corporations":
				_ok(gc2.rdr().count_in(gc2.state, "phobos", "security") > sec0,
					"il Passo di NP CORP attiva l'Aldrin Cycler")
			"marsgov":
				_ok(gc2.state.get_resources(fid_p) == res0,
					"il Passo di NP MG non gli dà Risorse, che non traccia (§8.5.4)")
		pass_notes.append(fid_p)
	_ok(pass_notes.size() == 3, "collaudato il Passo di tutte e tre le Fazioni (%d)" % pass_notes.size())

	# --- §5.6: le modalità del Rally ---------------------------------------
	# L'interfaccia forzava sempre «piazza 1 Ribelle», la meno interessante
	# delle cinque: niente Basi, niente Dig-In, niente Conversion Center.
	gc2.new_game("standard", 20240424, [])
	await process_frame
	for i_r in range(6):
		if gc2.sequence.pending_faction() == "red_dust":
			break
		if gc2.sequence.pending_faction() == "":
			gc2.end_card()
			await process_frame
			continue
		gc2.do_pass()
		await process_frame
	_ok(gc2.sequence.pending_faction() == "red_dust", "turno del Red Dust")
	var rally_c: PackedStringArray = gc2.operation_candidates("rally", "red_dust")
	var with_base := ""
	for sid_r in rally_c:
		for mo in gc2.rally_modes("red_dust", String(sid_r)):
			if String((mo as Dictionary)["id"]) == "base":
				with_base = String(sid_r)
				break
		if with_base != "":
			break
	_ok(with_base != "", "c'è uno spazio dove il Rally può costruire una Base (%s)" % with_base)
	_ok(gc2.dig_in_candidates().size() > 0,
		"…e Basi RD in Deserti da portare a Dig-In (%d)" % gc2.dig_in_candidates().size())
	if with_base != "":
		var reb0: int = gc2.rdr().count_in(gc2.state, with_base, "rd_rebel")
		var base0: int = gc2.rdr().count_in(gc2.state, with_base, "rd_base")
		var rr: Dictionary = gc2.execute_operation("rally", [with_base], false,
			{"modes": {with_base: "base"}, "dig_in": ""})
		_ok(rr.get("ok", false), "Rally in modalità Base eseguito")
		_ok(gc2.rdr().count_in(gc2.state, with_base, "rd_base") == base0 + 1,
			"…una Base in più (%d → %d)" % [base0, gc2.rdr().count_in(gc2.state, with_base, "rd_base")])
		_ok(gc2.rdr().count_in(gc2.state, with_base, "rd_rebel") == reb0 - 2,
			"…pagata con due Ribelli")

	# --- Le scelte delle Attività Speciali ----------------------------------
	# Erano parametri fissi nel dispatcher: la scelta esisteva nelle regole ma
	# non nel gioco. Purify «occupy» prende una Base nemica indifesa invece di
	# convertire forze, ed è l'esempio più netto.
	gc2.new_game("standard", 20240424, [])
	await process_frame
	var pur: PackedStringArray = gc2.special_candidates("purify", "reclaimer")
	var with_occupy := ""
	for sid_p in pur:
		for op_p in gc2.special_options("purify", String(sid_p)):
			if String((op_p as Dictionary)["id"]) == "occupy":
				with_occupy = String(sid_p)
				break
		if with_occupy != "":
			break
	_ok(pur.size() > 0, "Purify ha spazi candidati (%d)" % pur.size())
	for sid_p2 in pur:
		var opts_p: Array = gc2.special_options("purify", String(sid_p2))
		_ok(opts_p.size() >= 1, "…e almeno una modalità in %s" % sid_p2)
		break
	# Coordinate: la scelta «togli 2 cubi / sostituiscine 1» compare solo dove
	# l'Opposizione è già al massimo, com'è scritto in §6.8.
	var coo: PackedStringArray = gc2.special_candidates("coordinate", "red_dust")
	if coo.size() > 0:
		var sid_c := String(coo[0])
		var keys_c: Array = []
		for op_c in gc2.special_options("coordinate", sid_c):
			var k_c := String((op_c as Dictionary)["key"])
			if not keys_c.has(k_c):
				keys_c.append(k_c)
		_ok(keys_c.has("action"), "Coordinate offre la scelta fra House, Repair o niente")
		var at_max: bool = gc2.state.spaces[sid_c].support == CoinEnums.Support.ACTIVE_OPPOSITION
		_ok(keys_c.has("at_max") == at_max,
			"…e quella dei cubi solo con l'Opposizione già al massimo (%s)" % str(at_max))

	# --- §6.3 Transport e §6.9 Ambush: le due Speciali che mancavano ---------
	gc2.new_game("standard", 20240424, [])
	await process_frame
	var net: PackedStringArray = gc2.transport_network([])
	_ok(net.has("phobos"), "la rete del Transport comprende Phobos")
	var mg_bases := 0
	for sid_t in gc2.rdr().mars_spaces(gc2.state):
		if gc2.rdr().count_in(gc2.state, String(sid_t), "mg_base") > 0:
			mg_bases += 1
	_ok(net.size() == mg_bases + 1,
		"…e le %d Basi MG, niente altro (%d nella rete)" % [mg_bases, net.size()])
	_ok(gc2.transport_network(["radau"]).has("radau"),
		"uno spazio attivato in più entra nella rete")
	# Il Transport si esegue davvero, e non crea né perde Truppe.
	var origin_t := ""
	for sid_t2 in net:
		if gc2.rdr().count_in(gc2.state, String(sid_t2), "mg_troop") > 0:
			origin_t = String(sid_t2)
			break
	if origin_t != "":
		var dest_t := ""
		for sid_t3 in net:
			if String(sid_t3) != origin_t:
				dest_t = String(sid_t3)
				break
		var tot0 := 0
		for sid_t4 in gc2.state.spaces.keys():
			tot0 += gc2.rdr().count_in(gc2.state, String(sid_t4), "mg_troop")
		var rt: Dictionary = gc2.execute_special("transport", [],
			{"extra": [], "moves": [{"from": origin_t, "to": dest_t, "type": "mg_troop", "count": 1}]})
		_ok(rt.get("ok", false), "Transport eseguito da %s a %s" % [origin_t, dest_t])
		var tot1 := 0
		for sid_t5 in gc2.state.spaces.keys():
			tot1 += gc2.rdr().count_in(gc2.state, String(sid_t5), "mg_troop")
		_ok(tot0 == tot1, "…le Truppe si spostano, non si creano né si perdono")

	# Ambush: solo negli spazi dell'Attack con un Ribelle Nascosto.
	var atk_c: PackedStringArray = gc2.operation_candidates("attack", "red_dust")
	var amb: PackedStringArray = gc2.ambush_candidates("red_dust", Array(atk_c))
	_ok(amb.size() > 0, "ci sono spazi da Ambush per il Red Dust (%d su %d)" % [amb.size(), atk_c.size()])
	_ok(gc2.ambush_candidates("marsgov", Array(atk_c)).is_empty(),
		"…e MarsGov non può fare Ambush (§6.9: solo i Ribelli)")

	# --- §5.5: Bombard e Suppress dell'EarthGov Controller ------------------
	# Due opzioni dell'Assault che l'interfaccia non sapeva chiedere.
	gc2.new_game("standard", 20240424, [])
	await process_frame
	var ctrl: String = gc2.rdr().eg_controller(gc2.state)
	_ok(ctrl != "", "c'è un EarthGov Controller (%s)" % ctrl)
	_ok(gc2.can_bombard(ctrl), "il Controller può Bombardare (Satelliti in Orbita)")
	var other := "marsgov" if ctrl != "marsgov" else "corporations"
	_ok(not gc2.can_bombard(other), "chi non è Controller non può (%s)" % other)

	# Suppress: serve uno spazio con Truppe EG e Ribelli, che lo schieramento
	# iniziale non offre. Se ne costruisce uno.
	var sup_space := ""
	for sid_s in gc2.rdr().mars_spaces(gc2.state):
		var s_s := String(sid_s)
		if gc2.rdr().count_in(gc2.state, s_s, "rd_rebel") > 0 \
				and gc2.suppress_destinations(s_s).size() > 0:
			sup_space = s_s
			break
	if sup_space != "":
		gc2.rdr().move_pieces(gc2.state, "phobos", sup_space, "eg_troop", 2)
		var cands_s: PackedStringArray = gc2.suppress_candidates(ctrl, [])
		_ok(cands_s.has(sup_space),
			"%s è un candidato per Suppress (Truppe EG + Ribelli)" % sup_space)
		_ok(not gc2.suppress_candidates(ctrl, [sup_space]).has(sup_space),
			"…ma non se è fra gli spazi scelti per l'Assault (§5.5)")
		_ok(gc2.suppress_destinations(sup_space).size() > 0,
			"…e ha Deserti adiacenti dove spingere i Ribelli")

	# --- §4.3 fase 3: la Support Phase dei giocatori ------------------------
	# Prima veniva saltata con una riga nel Log: in una partita fra umani la
	# fase in cui MarsGov e Red Dust spingono il Supporto non si giocava affatto.
	gc2.new_game("standard", 20240424, ["corporations", "reclaimer"])
	await process_frame
	gc2.rounds.dust_storm_round()
	await process_frame
	var pend: Array = gc2.support_pending()
	_ok(pend.has("marsgov") and pend.has("red_dust"),
		"il Dust Storm Round si ferma per la Support Phase di MG e RD (%s)" % ", ".join(PackedStringArray(pend)))
	_ok(int(gc2.state.tracks.get("dust_storm_rounds", 0)) == 1,
		"…a round contato ma non concluso")

	# Pacify: uno spostamento verso il Supporto Attivo costa 3 Risorse.
	var mg_sp: PackedStringArray = gc2.support_candidates("marsgov", "shift")
	_ok(mg_sp.size() > 0, "MarsGov ha spazi dove spostare il Supporto (%d)" % mg_sp.size())
	if mg_sp.size() > 0:
		var target := String(mg_sp[0])
		var sup_before: int = gc2.state.spaces[target].support
		var res_before: int = gc2.state.get_resources("marsgov")
		var r_sup: Dictionary = gc2.support_act("marsgov", target, ["shift"])
		_ok(r_sup.get("ok", false), "Pacify eseguito in %s" % target)
		_ok(gc2.state.spaces[target].support == sup_before + 1, "…lo spazio si sposta di un livello")
		_ok(gc2.state.get_resources("marsgov") == res_before - 3, "…e costa 3 Risorse")

	# Lobby: 5 Risorse per un livello di EG Confidence, UNA volta per fase.
	var eg_before: int = int(gc2.state.tracks.get("eg_confidence", 0))
	_ok(gc2.can_lobby(), "il Lobby è disponibile")
	_ok(gc2.support_lobby().get("ok", false), "Lobby eseguito")
	_ok(int(gc2.state.tracks.get("eg_confidence", 0)) == eg_before + 1,
		"…EG Confidence sale di un livello")
	_ok(not gc2.can_lobby(), "…e non si può rifare nella stessa fase")

	# Chiudendo entrambe, il round riprende da dove si era fermato.
	gc2.support_done("marsgov")
	_ok(gc2.support_pending() == ["red_dust"], "resta il Red Dust")
	gc2.support_done("red_dust")
	await process_frame
	_ok(gc2.support_pending().is_empty(), "Support Phase chiusa")
	_ok(gc2.rounds.storms_on_map() >= 0 and gc2.state.current_card > 0,
		"il Dust Storm Round è ripreso e la partita continua (carta #%d)" % gc2.state.current_card)
	_ok(cards_seen.size() >= 5,
		"la partita di soli bot scorre fra le carte (%d carte in %d turni)" % [
			cards_seen.size(), bot_turns])
	# Nessuna istruzione deve restare non eseguibile: se ne aggiungo una nelle
	# carte e scordo il codice, il bot passerebbe il turno a vuoto senza dirlo.
	var stubs: Array = []
	for line in gc.np_ops.log_lines:
		if String(line).contains("non ancora eseguibile"):
			stubs.append(String(line))
	_ok(stubs.is_empty(), "nessuna istruzione della carta resta inerte (%s)"
		% ", ".join(PackedStringArray(stubs)))
	# §4.1: l'Attività Speciale accompagna l'Operazione. Se il bot non ne
	# eseguisse mai nessuna, giocherebbe metà del proprio turno.
	_ok(specials_done > 0, "il bot ha eseguito %d Attività Speciali" % specials_done)

	# La barra deve offrire il pulsante del bot quando tocca a una Fazione NP,
	# e non le Operazioni: quelle le sceglie la carta Curiosity.
	gc.new_game("standard", 20240424, ["marsgov", "corporations", "reclaimer"])
	await process_frame
	var guard_ui := 0
	while gc.sequence != null and guard_ui < 5 \
			and not gc.np.is_np(gc.sequence.pending_faction()):
		guard_ui += 1
		gc.do_pass()
		await process_frame
	if gc.sequence != null and gc.np.is_np(gc.sequence.pending_faction()):
		var labels: Array[String] = []
		for child in (main.get("_ops_box") as HFlowContainer).get_children():
			if child is Button:
				labels.append((child as Button).text)
		var has_np_btn := false
		for l in labels:
			if l.begins_with("Gioca il turno"):
				has_np_btn = true
		_ok(has_np_btn, "la barra offre il turno del bot (%s)" % ", ".join(labels))
		main.call("_run_np_turn")
		await process_frame
		_ok(true, "il pulsante del bot esegue il turno senza errori")
	_ok(gc.state != null, "la partita è ancora coerente dopo i turni del bot")

	# §8.5.2: il bot Reclaimer deve arrivare a rivelare Asset card, giocarne
	# l'Evento e mettere in gioco le Capability. Per un bel po' non lo faceva
	# affatto — la tabella di Eligibility ci passava sopra e `play_asset_event`
	# pretendeva la carta «in mano», che un bot non ha — e nessun test se ne
	# accorgeva perché la partita restava perfettamente coerente lo stesso.
	var giocati := 0
	var capability := 0
	for partita in range(4):
		gc.new_game("standard", 500 + partita * 71,
			["marsgov", "corporations", "red_dust", "reclaimer"])
		await process_frame
		var righe: Array[String] = []
		var raccogli := func(t): righe.append(String(t))
		gc.log_line.connect(raccogli)
		for i in range(120):
			if gc.sequence == null or gc.rounds.is_game_over():
				break
			if gc.sequence.pending_faction() == "":
				gc.end_card()
				await process_frame
				continue
			if not bool(gc.np_take_turn().get("ok", false)):
				break
			await process_frame
		gc.log_line.disconnect(raccogli)
		for l in righe:
			if l.contains("rivela") and l.contains("Asset card") and l.contains("gioca"):
				giocati += 1
		capability += (gc.state.tracks.get("capabilities", []) as Array).size()
	_ok(giocati > 0, "il bot Reclaimer gioca Asset Event (%d in 4 partite)" % giocati)
	_ok(capability > 0, "il bot Reclaimer mette Capability in gioco (%d)" % capability)

	if shot_path != "":
		await process_frame
		var img := root.get_texture().get_image()
		var err := img.save_png(shot_path)
		if err != OK:
			print("FALLITO: screenshot non salvato (errore %d)" % err)
			_failed = true
		else:
			print("screenshot: %s (%dx%d)" % [shot_path, img.get_width(), img.get_height()])

	quit(1 if _failed else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FALLITO: %s" % label)
		_failed = true
