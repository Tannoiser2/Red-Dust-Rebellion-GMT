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
	if gc.state == null:
		gc.new_game()

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

	# Se tutte le Fazioni Passano, la carta avanza e restano tutte Disponibili.
	var card_before: int = gc.state.current_card
	for i in range(4):
		gc.do_pass()
	await process_frame
	_ok(gc.state.current_card != card_before, "passando tutti, si passa alla carta seguente")
	_ok(gc.state.eligibility["marsgov"] == CoinEnums.Eligibility.ELIGIBLE,
		"chi Passa resta Disponibile")

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
