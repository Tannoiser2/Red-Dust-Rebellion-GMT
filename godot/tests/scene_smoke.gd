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
