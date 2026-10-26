extends SceneTree

## Cattura uno screenshot dell'interfaccia (serve un display: xvfb-run).
##
##   xvfb-run -a -s "-screen 0 1600x950x24" godot47 --path godot \
##     --rendering-method gl_compatibility --resolution 1500x900 \
##     -s res://tools/screenshot.gd -- out.png [modo]
##
## Modi:
##   (nessuno)  turno del Red Dust (giocatore), pannello a riposo;
##   rally      Rally del Red Dust con due spazi scelti (pannello con le modalità);
##   rally-eseguito  Rally eseguito, poi Coordinate in preparazione;
##   evento     opzione dell'Evento scelta, con le sue scelte;
##   bot        turno di una Fazione Non-Player;
##   reclaimer  turno dei Reclaimer giocatore (mano di Asset card nel pannello);
##   menu       schermata iniziale.
##
## Un terzo argomento «piccolo» prova il canvas logico da 1180×650 (iPad).

const SEED := 20240424


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var mode := args[1] if args.size() > 1 else ""
	# «piccolo» come terzo argomento: canvas logico 1180×650, come su iPad.
	if args.size() > 2 and args[2] == "piccolo":
		root.content_scale_size = Vector2i(1180, 650)
	var gc = root.get_node("GameController")
	await process_frame
	if mode == "menu":
		root.add_child(load("res://scenes/MainMenu.tscn").instantiate())
		await _shoot(out)
		return
	var human := "reclaimer" if mode == "reclaimer" else "red_dust"
	var bots: Array = []
	for f in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		if f != human:
			bots.append(f)
	# Si cerca un seme in cui la Fazione umana è 1ª Disponibile sulla prima carta
	# (o il bot di turno, per il modo «bot»).
	for s in range(SEED, SEED + 200):
		gc.new_game("standard", s, bots)
		await process_frame
		var p: String = gc.sequence.pending_faction() if gc.sequence != null else ""
		if (mode == "bot" and p != human and p != "") or (mode != "bot" and p == human) \
				or mode == "reclaimer":
			break
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(8):
		await process_frame
	match mode:
		"rally", "rally-eseguito":
			main._start_op("rally")
			await process_frame
			var c: PackedStringArray = gc.operation_candidates("rally", human)
			var with_base := ""
			for sid in c:
				for mo in gc.rally_modes(human, String(sid)):
					if String(mo["id"]) == "base":
						with_base = String(sid)
			if with_base != "":
				main._on_space_clicked(with_base)
			for sid in c:
				if (main._op_spaces as Array).size() >= 2:
					break
				if not (main._op_spaces as Array).has(String(sid)):
					main._on_space_clicked(String(sid))
			if mode == "rally-eseguito":
				main._on_execute()
				await process_frame
				main._on_sa_button("coordinate")
		"evento":
			main._start_event(false)
		"reclaimer":
			# I Reclaimer sono stampati ultimi su ogni carta: si fanno giocare
			# i bot finché tocca a loro.
			for i in range(12):
				var p: String = gc.sequence.pending_faction() if gc.sequence != null else ""
				if p == human:
					break
				if p == "":
					gc.end_card()
				else:
					gc.np_take_turn()
				await process_frame
	await _shoot(out)


func _shoot(out: String) -> void:
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("salvato ", out, " ", img.get_size())
	quit(0)
