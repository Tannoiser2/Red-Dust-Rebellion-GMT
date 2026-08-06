class_name MapAnimator
extends Control

## Effetti sulla mappa: i pezzi che cambiano posto volano da uno spazio all'altro
## con una scia luminosa, e gli spazi il cui stato è cambiato lampeggiano.
##
## Funziona per DIFFERENZA: confronta i conteggi con quelli dell'aggiornamento
## precedente, quindi non ha bisogno di sapere quali azioni siano state svolte —
## un turno del bot che risolve mezza carta si anima come un click del giocatore.
## Il layer è puramente decorativo e non intercetta il mouse: lo stato definitivo
## viene ridisegnato subito, i "fantasmi" volano sopra.
##
## Portato da Cuba Libre, con due differenze dovute alla plancia di Red Dust:
## le Forze Disponibili non hanno un box sulla mappa ma una traccia sul bordo,
## quindi i pezzi che entrano o escono dal gioco volano dall'alto; e Casualties,
## Displaced Population ed Earth sono spazi veri, così gli spostamenti da e verso
## di essi si animano da soli come tutti gli altri.

const PIECE_SIZE := 26.0    ## dimensione del pezzo animato
const DURATION := 0.9       ## durata del volo
const MAX_GHOSTS := 24      ## oltre questa soglia si salta (nuova partita, Dust Storm Round)
const ECHOES := 4           ## copie della scia (la prima è la "testa")

var _views: Dictionary = {}      ## space_id -> RegionView (per i centri degli spazi)
var _types: Array = []           ## tipi di pezzo, dal GameDef
var _prev_counts: Dictionary = {}
var _prev_fingerprint: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50


## Collega le viste degli spazi. I tipi di pezzo si leggono dal GameDef invece di
## elencarli a mano: se un giorno se ne aggiunge uno, l'animazione lo segue.
func setup(views: Dictionary, game_def: GameDef) -> void:
	_views = views
	_types.clear()
	for pt in game_def.piece_types:
		_types.append(String(pt.id))


## Dopo un caricamento, un annulla o una nuova partita: riparte dal nuovo stato
## senza animare le decine di differenze accumulate.
func reset() -> void:
	_prev_counts.clear()
	_prev_fingerprint.clear()


## Da chiamare a ogni aggiornamento, PRIMA che le RegionView si ridisegnino.
func update(state: GameState) -> void:
	_animate_moves(state)
	_flash_changes(state)


# ---------------------------------------------------------------------------
# Spostamenti
# ---------------------------------------------------------------------------

func _animate_moves(state: GameState) -> void:
	var counts: Dictionary = {}
	for sid in _views.keys():
		var st: SpaceState = state.space_state(String(sid))
		if st == null:
			continue
		for t in _types:
			# `SpaceState.count` vuole la Fazione: il tipo di pezzo la determina.
			var n := st.count(String(RDRModule.PIECE_OWNER.get(String(t), "")), String(t))
			if n > 0:
				counts["%s|%s" % [sid, t]] = n
	# Primo aggiornamento: memorizza soltanto.
	if _prev_counts.is_empty():
		_prev_counts = counts
		return
	var ghosts := _collect_ghosts(counts)
	_prev_counts = counts
	# Troppi movimenti insieme (Redeploy, Reset): saltare è meglio che intasare.
	if ghosts.size() > MAX_GHOSTS:
		return
	for g in ghosts:
		_spawn_ghost(String(g["t"]), g["from"], g["to"])


## Accoppia le diminuzioni con gli aumenti, tipo per tipo: ciò che resta
## scompensato entra in gioco dal bordo superiore (dov'è la traccia delle Forze
## Disponibili) o vi ritorna.
func _collect_ghosts(counts: Dictionary) -> Array:
	var ghosts: Array = []
	for t in _types:
		var sources: Array = []   # [sid, quantità]
		var dests: Array = []
		for sid in _views.keys():
			var key := "%s|%s" % [sid, t]
			var d: int = int(counts.get(key, 0)) - int(_prev_counts.get(key, 0))
			if d < 0:
				sources.append([String(sid), -d])
			elif d > 0:
				dests.append([String(sid), d])
		var si := 0
		var left := 0 if sources.is_empty() else int(sources[0][1])
		for de in dests:
			var dc := _center(String(de[0]))
			for _k in range(int(de[1])):
				var from_pos := _off_map_point(dc)
				if si < sources.size():
					from_pos = _center(String(sources[si][0]))
					left -= 1
					if left <= 0:
						si += 1
						left = 0 if si >= sources.size() else int(sources[si][1])
				ghosts.append({"t": t, "from": from_pos, "to": dc})
		while si < sources.size():
			var sc := _center(String(sources[si][0]))
			for _k2 in range(left):
				ghosts.append({"t": t, "from": sc, "to": _off_map_point(sc)})
			si += 1
			left = 0 if si >= sources.size() else int(sources[si][1])
	return ghosts


## Centro di uno spazio, nelle coordinate di questo layer.
func _center(sid: String) -> Vector2:
	var rv: RegionView = _views.get(sid, null)
	if rv == null:
		return size * 0.5
	return rv.position + rv.center_point()


## Da dove arriva (e dove torna) un pezzo che entra o esce dal gioco: appena
## sopra il bordo, all'altezza dello spazio interessato.
func _off_map_point(near: Vector2) -> Vector2:
	return Vector2(near.x, -PIECE_SIZE)


## Un pezzo che vola con effetto cometa: una testa brillante più alcune copie
## sfalsate che la inseguono attenuandosi.
func _spawn_ghost(type_id: String, from_pos: Vector2, to_pos: Vector2) -> void:
	var tex := RDRAssets.piece_tex(type_id, "")
	if tex == null:
		return
	var half := Vector2(PIECE_SIZE, PIECE_SIZE) * 0.5
	for e in range(ECHOES):
		var g := TextureRect.new()
		g.texture = tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size = Vector2(PIECE_SIZE, PIECE_SIZE)
		g.pivot_offset = half
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.position = from_pos - half
		var head := e == 0
		g.modulate = Color(1.5, 1.5, 1.2, 1.0) if head \
			else Color(1.2, 1.2, 1.1, 0.5 - 0.1 * float(e))
		g.scale = Vector2(1.45, 1.45) if head else Vector2(1.2, 1.2)
		add_child(g)
		var lead := float(e) * 0.08   # ritardo crescente: la copia resta indietro
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if lead > 0.0:
			tw.tween_interval(lead)
		tw.tween_property(g, "position", to_pos - half, DURATION)
		tw.parallel().tween_property(g, "scale", Vector2(1, 1), DURATION)
		tw.parallel().tween_property(g, "modulate:a", 0.0, DURATION * 0.45) \
			.set_delay(DURATION * 0.55)
		tw.tween_callback(g.queue_free)


# ---------------------------------------------------------------------------
# Lampeggio degli spazi cambiati
# ---------------------------------------------------------------------------

const FLASH_COLOR := Color(1.0, 0.85, 0.25)


func _flash_changes(state: GameState) -> void:
	var first := _prev_fingerprint.is_empty()
	for sid in _views.keys():
		var fp := fingerprint(state, String(sid))
		if not first and String(_prev_fingerprint.get(sid, "")) != fp:
			(_views[sid] as RegionView).flash(FLASH_COLOR)
		_prev_fingerprint[sid] = fp


## Firma dello stato di uno spazio: cambia se cambia qualcosa di visibile —
## Controllo, Supporto, i marcatori della traccia Infrastruttura, la tempesta, e
## i conteggi di ogni tipo di pezzo.
static func fingerprint(state: GameState, sid: String) -> String:
	var st: SpaceState = state.space_state(sid)
	if st == null:
		return ""
	var out := "%s,%d,%d,%d,%d,%d" % [st.control, st.support,
		st.marker("damage"), st.marker("storm"), st.marker("pop_markers"),
		st.marker("supply")]
	for fid in st.pieces.keys():
		for t in st.pieces[fid].keys():
			for ps in st.pieces[fid][t].keys():
				out += ",%s:%s:%s=%d" % [fid, t, ps, int(st.pieces[fid][t][ps])]
	return out
