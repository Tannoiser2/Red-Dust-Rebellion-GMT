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
				for i in range(int(st.pieces[fid][type_id][piece_state])):
					bucket.append({"tex": tex, "type": String(type_id)})
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
		var cols: int = ceili(sqrt(float(n)))
		var rows: int = ceili(float(n) / float(cols))
		var step := psz * 0.92
		for i in range(n):
			var col := i % cols
			var row := i / cols
			var pos := a + Vector2(
				(col - (cols - 1) * 0.5) * step,
				(row - (rows - 1) * 0.5) * step - psz * 0.2)
			var tr: TextureRect = _tokens[i]
			tr.texture = _pieces[i]["tex"]
			tr.size = Vector2(psz, psz)
			tr.position = pos - tr.size * 0.5

	# Marker Supporto sulla casella 'Neutral' stampata; Controllo appena sopra.
	var sb := _sbox if _sbox.x >= 0.0 else _anchor
	var sp := Vector2(sb.x * size.x, sb.y * size.y)
	_sup_marker.size = Vector2(mw, mw * 0.62)
	_sup_marker.position = sp - _sup_marker.size * 0.5
	_ctrl_marker.size = Vector2(mw, mw * 0.62)
	_ctrl_marker.position = sp - Vector2(_ctrl_marker.size.x * 0.5, _ctrl_marker.size.y * 1.6)
	_badge.position = sp + Vector2(-mw * 0.5, mw * 0.4)


func _draw() -> void:
	if _poly.size() < 3:
		return
	var poly := _scaled_poly()
	if _control != "":
		var c := RDRAssets.control_color(_control)
		c.a = 0.22
		draw_colored_polygon(poly, c)
	if _hover:
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(1, 1, 1, 0.9), 3.0)


## Evidenzia il contorno (usato per gli spazi candidati di un'Operazione).
func set_highlight(on: bool) -> void:
	_hover = on
	queue_redraw()


## Conteggio dei pezzi impilati (per il pannello laterale).
func piece_count() -> int:
	return _pieces.size()
