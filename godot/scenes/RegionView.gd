class_name RegionView
extends Control

## Zona cliccabile di uno spazio, sagomata sul poligono estratto dal Vassal.
## Il Control copre l'intera mappa ma reagisce solo dentro il poligono
## (`_has_point`), così Labirinti e Deserti sovrapposti restano distinguibili:
## i Labirinti hanno `z` più alto e vengono aggiunti dopo, quindi ricevono
## il clic per primi nella zona di sovrapposizione.
##
## Sopra il poligono disegna la tinta del Controllo e il contorno di
## evidenziazione; i pezzi sono impilati a griglia sull'anchor e i marker
## Supporto/Danno sulla casella 'Neutral' della traccia Infrastruttura (`sbox`).

signal space_clicked(space_id: String)
## Un pezzo è stato trascinato da un altro spazio dentro questo (§5.3/§5.7).
signal piece_dropped(from_id: String, to_id: String, type_id: String)

const PIECE_PX := 26.0        ## lato del pezzo alla scala di riferimento
const REF_MAP_W := 1500.0     ## larghezza mappa per cui PIECE_PX è tarato
const MARKER_W_FRAC := 0.028  ## larghezza dei marker Supporto/Controllo (frazione mappa)

var space_id: String
var space_def: SpaceDef

var _poly: PackedVector2Array = PackedVector2Array()
var _anchor := Vector2(0.5, 0.5)
var _sbox := Vector2(-1, -1)
var _control := ""
var _support: int = 0
var _hover := false
## Lampeggio dopo un'azione: dice quali spazi sono stati toccati, che nel
## groviglio di pedine della tavola non è affatto ovvio.
var _flash_color := Color.WHITE
var _flash_a := 0.0
## Stato nella scelta in corso, e la fase del pulsare dei candidati.
var _pick_state: int = 0
var _pulse := 0.0
var _pieces: Array = []       ## un elemento per pezzo: {tex, type}
var _tokens: Array[TextureRect] = []
var _sup_marker: TextureRect
var _ctrl_marker: TextureRect
var _badge: Label


func setup(sd: SpaceDef, reg: Dictionary) -> void:
	space_id = sd.id
	space_def = sd
	tooltip_text = sd.name
	mouse_filter = Control.MOUSE_FILTER_STOP
	for p in reg.get("polygon", []):
		_poly.append(Vector2(p[0], p[1]))
	var a: Array = reg.get("anchor", [0.5, 0.5])
	_anchor = Vector2(a[0], a[1])
	if reg.has("sbox"):
		var s: Array = reg["sbox"]
		_sbox = Vector2(s[0], s[1])

	set_process(false)
	_sup_marker = _make_marker()
	_ctrl_marker = _make_marker()
	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 11)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_badge.add_theme_constant_override("shadow_offset_x", 1)
	_badge.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_badge)


func _make_marker() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.visible = false
	add_child(tr)
	return tr


func _scaled_poly() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _poly:
		out.append(Vector2(p.x * size.x, p.y * size.y))
	return out


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _scaled_poly())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("space_clicked", space_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		queue_redraw()


# ---------------------------------------------------------------------------

## Aggiorna il contenuto dallo stato di gioco e ridisegna.
func refresh(state: GameState, module: RDRModule) -> void:
	var st: SpaceState = state.space_state(space_id)
	_control = st.control
	_support = st.support

	# Un token per pezzo (i conteggi vengono espansi), Basi per prime così
	# restano in alto a sinistra nella griglia come sul tavolo.
	_pieces.clear()
	var bases: Array = []
	var units: Array = []
	for fid in st.pieces.keys():
		for type_id in st.pieces[fid].keys():
			var pt: PieceTypeDef = state.game_def.piece_type(type_id)
			var bucket: Array = bases if (pt != null and pt.is_base) else units
			for piece_state in st.pieces[fid][type_id].keys():
				var tex := RDRAssets.piece_tex(String(type_id), String(piece_state))
				var is_base := pt != null and pt.is_base
				for i in range(int(st.pieces[fid][type_id][piece_state])):
					bucket.append({"tex": tex, "type": String(type_id),
						"state": String(piece_state), "is_base": is_base})
	_pieces = bases + units

	_sup_marker.texture = RDRAssets.support_tex(_support)
	_sup_marker.visible = _sup_marker.texture != null
	_ctrl_marker.texture = RDRAssets.control_tex(_control)
	_ctrl_marker.visible = _ctrl_marker.texture != null

	# Badge solo dove serve: gli spazi sempre Spopolati (Wilderness, Phobos, box
	# fuori mappa) non hanno traccia Infrastruttura da annotare.
	var bits: Array[String] = []
	var pop := module.population(state, space_id)
	if pop > 0:
		bits.append("Pop %d" % pop)
	var dmg := int(st.markers.get("damage", 0))
	if dmg > 0:
		bits.append("⚠%d" % dmg)
	_badge.text = "  ".join(bits)

	relayout()
	queue_redraw()


func relayout() -> void:
	if size.x <= 0.0:
		return
	var scale := size.x / REF_MAP_W
	var psz: float = maxf(10.0, PIECE_PX * scale)
	var mw: float = maxf(12.0, MARKER_W_FRAC * size.x)

	# Pezzi a griglia centrata sull'anchor, con passo stretto quando sono tanti.
	var a := Vector2(_anchor.x * size.x, _anchor.y * size.y)
	while _tokens.size() < _pieces.size():
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_tokens.append(tr)
	for i in range(_tokens.size()):
		_tokens[i].visible = i < _pieces.size()
	var n := _pieces.size()
	if n > 0:
		_layout_pieces(a, psz, n)

	# Marker Supporto sulla casella 'Neutral' stampata; Controllo appena sopra.
	var sb := _sbox if _sbox.x >= 0.0 else _anchor
	var sp := Vector2(sb.x * size.x, sb.y * size.y)
	_sup_marker.size = Vector2(mw, mw * 0.62)
	_sup_marker.position = sp - _sup_marker.size * 0.5
	_ctrl_marker.size = Vector2(mw, mw * 0.62)
	_ctrl_marker.position = sp - Vector2(_ctrl_marker.size.x * 0.5, _ctrl_marker.size.y * 1.6)
	_badge.position = sp + Vector2(-mw * 0.5, mw * 0.4)


## Dispone i pezzi attorno all'anchor.
##
## Il criterio è quello del tavolo vero: i pezzi della stessa Fazione stanno
## insieme, in righe separate, e le Basi in cima. Le righe sono sfalsate di mezzo
## passo, così due file di cubi identici non si allineano in una colonna
## indistinguibile. Finché c'è posto le pedine NON si sovrappongono; quando sono
## troppe si rimpiccioliscono, che è sempre più leggibile che accavallarle.
func _layout_pieces(a: Vector2, psz: float, n: int) -> void:
	# Righe: una per gruppo (Basi, poi ogni Fazione). Un gruppo che non ci sta in
	# una riga sola viene spezzato.
	var groups: Array = []
	var last_key := "—"   # sentinella: nessun gruppo aperto
	for i in range(n):
		var p: Dictionary = _pieces[i]
		var key := "base" if bool(p.get("is_base", false)) \
			else String(RDRModule.PIECE_OWNER.get(String(p["type"]), "?"))
		if key != last_key:
			groups.append([])
			last_key = key
		(groups[groups.size() - 1] as Array).append(i)

	# Larghezza disponibile: il lato più stretto fra quanto la zona è larga e un
	# tetto ragionevole, così nei Deserti larghi le pedine non si sparpagliano.
	var max_per_row := 5
	var rows: Array = []
	for g in groups:
		var group: Array = g
		var start := 0
		while start < group.size():
			rows.append(group.slice(start, mini(start + max_per_row, group.size())))
			start += max_per_row

	# Se le righe sono tante si stringe tutto invece di allargarsi a dismisura.
	var scale_down: float = 1.0 if rows.size() <= 3 else 3.0 / float(rows.size())
	var sz: float = maxf(8.0, psz * minf(1.0, sqrt(scale_down)))
	var step_x := sz * 1.06        # niente sovrapposizione orizzontale
	var step_y := sz * 0.88        # verticale un filo più stretto: le pedine sono tozze
	var total_h := step_y * float(rows.size() - 1)

	var idx := 0
	for r in range(rows.size()):
		var row: Array = rows[r]
		# Sfasatura: le righe dispari scivolano di mezza pedina.
		var offset: float = 0.0 if r % 2 == 0 else step_x * 0.5
		var w := step_x * float(row.size() - 1)
		for c in range(row.size()):
			var tr: TextureRect = _tokens[idx]
			tr.texture = _pieces[row[c]]["tex"]
			tr.size = Vector2(sz, sz)
			var pos := a + Vector2(
				float(c) * step_x - w * 0.5 + offset,
				float(r) * step_y - total_h - sz * 0.55)
			tr.position = pos - tr.size * 0.5
			idx += 1
	# I token in eccesso (creati per un conteggio precedente) restano nascosti.
	for j in range(idx, _tokens.size()):
		_tokens[j].visible = false


## Accende lo spazio per un attimo (verde per chi riceve, blu per chi cede).
func flash(color: Color) -> void:
	_flash_color = color
	_flash_a = 0.7
	set_process(true)


func _process(delta: float) -> void:
	var busy := false
	if _flash_a > 0.0:
		_flash_a = maxf(0.0, _flash_a - delta * 1.2)
		busy = true
	# I candidati respirano piano: attira l'occhio senza distrarre.
	if _pick_state == PickState.CANDIDATE:
		_pulse += delta
		busy = true
	if not busy:
		set_process(false)
		return
	queue_redraw()


func _draw() -> void:
	if _poly.size() < 3:
		return
	var poly := _scaled_poly()
	if _control != "":
		var c := RDRAssets.control_color(_control)
		c.a = 0.22
		draw_colored_polygon(poly, c)
	if _flash_a > 0.0:
		var fc := _flash_color
		fc.a = _flash_a * 0.45
		draw_colored_polygon(poly, fc)
		fc.a = _flash_a
		draw_polyline(poly + PackedVector2Array([poly[0]]), fc, 3.0)
	# Mentre si pianifica un'azione la mappa deve dire da sé dove si può
	# cliccare: prima l'unico segno era il contorno degli spazi GIÀ scelti, e i
	# candidati non si distinguevano in alcun modo dagli altri.
	match _pick_state:
		PickState.CANDIDATE:
			var glow := Color(1.0, 0.94, 0.55)
			glow.a = 0.16 + 0.06 * sin(_pulse * 3.2)
			draw_colored_polygon(poly, glow)
			glow.a = 0.85
			draw_polyline(poly + PackedVector2Array([poly[0]]), glow, 2.5)
		PickState.CHOSEN:
			var pick := Color(0.42, 1.0, 0.58)
			pick.a = 0.30
			draw_colored_polygon(poly, pick)
			pick.a = 1.0
			draw_polyline(poly + PackedVector2Array([poly[0]]), pick, 4.0)
		PickState.DIMMED:
			# Spenti gli spazi che in questo momento non si possono scegliere:
			# togliere è più leggibile che aggiungere un altro colore.
			draw_colored_polygon(poly, Color(0.02, 0.02, 0.04, 0.45))
	if _hover:
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(1, 1, 1, 0.9), 3.0)


## Come lo spazio partecipa alla scelta in corso.
enum PickState { NONE, CANDIDATE, CHOSEN, DIMMED }


func set_pick_state(st: int) -> void:
	if _pick_state == st:
		return
	_pick_state = st
	set_process(true)
	queue_redraw()


## Evidenzia il contorno (retrocompatibile: true = scelto).
func set_highlight(on: bool) -> void:
	set_pick_state(PickState.CHOSEN if on else PickState.NONE)


## Punto attorno a cui sono impilati i pezzi: da qui partono e qui arrivano le
## frecce degli spostamenti.
func center_point() -> Vector2:
	return Vector2(_anchor.x * size.x, _anchor.y * size.y)


# ---------------------------------------------------------------------------
# Trascinamento dei pezzi (§5.3/§5.4/§5.7/§5.8)
# ---------------------------------------------------------------------------

## Indice del pezzo impilato sotto il puntatore, -1 se lì non c'è nessun pezzo.
func _piece_at(point: Vector2) -> int:
	for i in range(mini(_tokens.size(), _pieces.size())):
		var tr: TextureRect = _tokens[i]
		if tr.visible and Rect2(tr.position, tr.size).has_point(point):
			return i
	return -1


## Trascinare un pezzo avvia lo spostamento di UNA unità: la destinazione la
## decide il rilascio, la legalità la controlla la scena.
func _get_drag_data(at_position: Vector2) -> Variant:
	var idx := _piece_at(at_position)
	if idx < 0:
		return null
	var piece: Dictionary = _pieces[idx]
	var preview := TextureRect.new()
	preview.texture = piece["tex"]
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(PIECE_PX, PIECE_PX)
	set_drag_preview(preview)
	return {"kind": "piece", "from": space_id, "type": String(piece["type"]),
		"state": String(piece["state"])}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "piece" \
		and String(data.get("from", "")) != space_id


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	emit_signal("piece_dropped", String(data["from"]), space_id, String(data["type"]))


## Conteggio dei pezzi impilati (per il pannello laterale).
func piece_count() -> int:
	return _pieces.size()
