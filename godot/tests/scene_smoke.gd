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
	var ops_box: HBoxContainer = main.get("_ops_box")
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
