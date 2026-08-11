extends SceneTree

## Simulatore da riga di comando: gioca N partite di soli bot e sputa un JSON
## con tutto quello che è successo, una riga per partita.
##
##   godot --headless --path godot -s res://tests/simulate.gd -- --games=100 --out=/tmp/sim.json
##
## Serve a due cose: misurare l'equilibrio fra le Fazioni e accorgersi delle
## Operazioni o delle Attività Speciali che il bot non esegue mai — un conteggio
## a zero è quasi sempre una regola non collegata, non una scelta della tabella.

const MAX_TURNI := 400


func _initialize() -> void:
	var games := 100
	var out_path := ""
	var base_seed := 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.substr("--games=".length()))
		elif arg.begins_with("--out="):
			out_path = arg.substr("--out=".length())
		elif arg.begins_with("--seed="):
			base_seed = int(arg.substr("--seed=".length()))

	var gc = root.get_node("GameController")
	# L'autoload avvia una partita di default al PRIMO FRAME: senza questa attesa
	# la partita col seme scelto verrebbe subito sostituita da quella casuale.
	await process_frame

	var tutte: Array = []
	for g in range(games):
		tutte.append(await _una_partita(gc, base_seed + g * 37))
		if (g + 1) % 10 == 0:
			printerr("… %d/%d partite" % [g + 1, games])

	var testo := JSON.stringify(tutte)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(testo)
		f.close()
		printerr("scritto %s (%d partite)" % [out_path, tutte.size()])
	else:
		print(testo)
	quit()


func _una_partita(gc, seme: int) -> Dictionary:
	gc.new_game("standard", seme, ["marsgov", "corporations", "red_dust", "reclaimer"])
	await process_frame

	var rec := {
		"seed": seme,
		"azioni": {},        # fazione → {op_sa: n, pass: n, …}
		"operazioni": {},    # fazione → {rally: n, march: n, …}
		"speciali": {},      # fazione → {ransack: n, …}
		"eventi": 0,         # Eventi della carta in corso giocati
		"asset_event": 0,
		"curiosity": 0,      # carte Curiosity pescate
		"turni": 0,
		"carte": 0,          # carte Evento passate
		"dust_storm": 0,
		"fine": "",
		"pass_forzati": 0,   # il bot non aveva nessuna Operazione possibile
		"degradate": 0,      # decisioni prese senza sapere Critical/effective
		"motivo": "",
		"campaign_viste": [],   # le Campaign entrate in gioco, in ordine
	}
	var righe: Array[String] = []
	var raccogli := func(t): righe.append(String(t))
	gc.log_line.connect(raccogli)

	var guardia := 0
	while guardia < MAX_TURNI:
		guardia += 1
		if gc.sequence == null or gc.rounds.is_game_over():
			rec["fine"] = "vittoria"
			break
		if gc.sequence.pending_faction() == "":
			gc.end_card()
			await process_frame
			continue
		var fid: String = gc.sequence.pending_faction()
		var res: Dictionary = gc.np_take_turn()
		await process_frame
		if not bool(res.get("ok", false)):
			rec["fine"] = "errore: %s" % res.get("error", "?")
			break
		rec["turni"] += 1
		_conta(rec["azioni"], fid, String(res.get("action", "?")))
		if res.has("operation"):
			_conta(rec["operazioni"], fid, String(res["operation"]))
		if res.has("special"):
			_conta(rec["speciali"], fid, String(res["special"]))
		if res.has("card"):
			rec["curiosity"] += 1
		if res.has("asset_card"):
			rec["asset_event"] += 1
		if String(res.get("action", "")) == "event":
			rec["eventi"] += 1
		if bool(res.get("passed", false)):
			rec["pass_forzati"] += 1
		if bool(res.get("degraded", false)):
			rec["degradate"] += 1
		var camp := int(gc.state.tracks.get("campaign_in_play", -1))
		if camp >= 0 and not (rec["campaign_viste"] as Array).has(camp):
			(rec["campaign_viste"] as Array).append(camp)
	if rec["fine"] == "":
		rec["fine"] = "limite di %d turni" % MAX_TURNI
	gc.log_line.disconnect(raccogli)
	# Il conteggio delle carte non può passare da `end_card()`: la sequenza si
	# chiude da sé appena la seconda Fazione ha agito.
	rec["carte"] = (gc.state.played_deck as Array).size()
	for l in righe:
		if l.begins_with("Check di vittoria"):
			rec["motivo"] = "condizione raggiunta al Dust Storm Round"
		elif l.contains("mazzo Evento") or l.contains("ultima carta"):
			rec["motivo"] = "mazzo Evento esaurito"

	rec["dust_storm"] = int(gc.state.tracks.get("dust_storm_rounds", 0))
	rec["vincitore"] = String(gc.state.tracks.get("winner", ""))
	rec["capability"] = (gc.state.tracks.get("capabilities", []) as Array).size()
	rec["campaign"] = int(gc.state.tracks.get("campaign_in_play", -1))
	# Il quadro finale: valore raggiunto e soglia di ciascuna Fazione.
	var v: Dictionary = gc.rdr().victory_status(gc.state)
	var punteggi := {}
	for fid in v.keys():
		punteggi[fid] = {
			"valore": int(v[fid]["value"]),
			"soglia": int(v[fid]["threshold"]),
			"margine": int(v[fid]["margin"]),
		}
	rec["punteggi"] = punteggi
	# §8.5.4: le Risorse non si tracciano per NP MG e NP RD, e le Corporations
	# incassano Profits, non Risorse: in una partita di soli bot l'unico numero
	# economico che significhi qualcosa è il Profits, che è anche la condizione
	# di vittoria delle CORP.
	rec["profits"] = int(gc.state.tracks.get("profits", 0))
	rec["asset_total"] = int(gc.state.tracks.get("asset_total", 0))
	return rec


func _conta(dove: Dictionary, fid: String, chiave: String) -> void:
	if not dove.has(fid):
		dove[fid] = {}
	var d: Dictionary = dove[fid]
	d[chiave] = int(d.get(chiave, 0)) + 1
