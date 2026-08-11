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
	# La Fazione giocata «da un umano»: resta un giocatore per il motore delle
	# regole, ma le sue mosse le sceglie la politica Curiosity. "" = tutti bot.
	var human := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.substr("--games=".length()))
		elif arg.begins_with("--out="):
			out_path = arg.substr("--out=".length())
		elif arg.begins_with("--seed="):
			base_seed = int(arg.substr("--seed=".length()))
		elif arg.begins_with("--human="):
			human = arg.substr("--human=".length())

	var gc = root.get_node("GameController")
	# L'autoload avvia una partita di default al PRIMO FRAME: senza questa attesa
	# la partita col seme scelto verrebbe subito sostituita da quella casuale.
	await process_frame

	var tutte: Array = []
	for g in range(games):
		tutte.append(await _una_partita(gc, base_seed + g * 37, human))
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


func _una_partita(gc, seme: int, human: String = "") -> Dictionary:
	var bot: Array = []
	for f in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		if String(f) != human:
			bot.append(f)
	gc.new_game("standard", seme, bot)
	# Il mazzo Curiosity della Fazione «umana» lo prepara la simulazione: in una
	# partita vera non esiste, e crearlo lì sposterebbe la sequenza casuale di
	# tutte le altre — i test col seme fisso se ne accorgono.
	if human != "":
		gc.np.setup_deck(human, RDRNonPlayerOps.DECKS.get(human, []))
	await process_frame

	var rec := {
		"seed": seme,
		"human": human,
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
		# La Support Phase di una Fazione di un giocatore ferma il Dust Storm
		# Round finché qualcuno non la risolve: il surrogato la gioca con l'API
		# vera del giocatore (Pacify/Agitate coi loro costi), scegliendo gli
		# spazi con la colonna della scheda NP.
		if not gc.support_pending().is_empty():
			for f in gc.support_pending().duplicate():
				rec["support_umano"] = int(rec.get("support_umano", 0)) \
					+ _gioca_support(gc, String(f))
			await process_frame
			continue
		if gc.sequence.pending_faction() == "":
			gc.end_card()
			await process_frame
			continue
		var fid: String = gc.sequence.pending_faction()
		var res: Dictionary = gc.np_take_turn(fid == human)
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
	rec["support"] = int(gc.rdr().total_support(gc.state))
	rec["opposition"] = int(gc.rdr().total_opposition(gc.state))
	rec["eg"] = int(gc.rdr().eg_confidence_value(gc.state))
	rec["displaced"] = int(gc.state.tracks.get("displaced_population", 0))
	rec["asset_total"] = int(gc.state.tracks.get("asset_total", 0))
	return rec


## Risolve la Support Phase di una Fazione di un giocatore. Restituisce quante
## azioni è riuscita a fare. L'ordine è quello stampato sulla carta: ① House
## ② Repair ③ Shift; lo Shift è l'unico che muove il totale di vittoria, quindi
## si insiste finché ci sono spazi e la Fazione può pagarlo.
func _gioca_support(gc, fid: String) -> int:
	var fatte := 0
	var colonna := "shift_toward_active_support" if fid == "marsgov" else "shift_active_opposition"
	for giro in range(12):
		var mosso := false
		for azione in ["house", "repair", "shift"]:
			var cands: Array = Array(gc.support_candidates(fid, azione))
			if cands.is_empty():
				continue
			var sid := String(gc.np.select_space(fid, colonna, cands).get("space", ""))
			if sid == "":
				continue
			if bool(gc.support_act(fid, sid, [azione]).get("ok", false)):
				fatte += 1
				mosso = true
				break
		if not mosso:
			break
	gc.support_done(fid)
	return fatte


func _conta(dove: Dictionary, fid: String, chiave: String) -> void:
	if not dove.has(fid):
		dove[fid] = {}
	var d: Dictionary = dove[fid]
	d[chiave] = int(d.get(chiave, 0)) + 1
