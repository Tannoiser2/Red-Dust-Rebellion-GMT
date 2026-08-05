class_name MovesOverlay
extends Control

## Frecce degli spostamenti dichiarati (§5.3/§5.4/§5.7/§5.8): dallo spazio di
## partenza a quello di arrivo. I pezzi si muovono davvero solo con «Esegui»,
## quindi qui si mostra l'intenzione, non lo stato finale.

var _segments: Array = []   ## [{from: Vector2, to: Vector2, count: int}]
var color := Color(0.25, 0.85, 1.0, 0.95)

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func set_segments(segs: Array) -> void:
	_segments = segs
	queue_redraw()


func _draw() -> void:
	for seg in _segments:
		_draw_arrow(seg["from"], seg["to"], int(seg.get("count", 1)))


func _draw_arrow(a: Vector2, b: Vector2, count: int) -> void:
	if a.distance_to(b) < 1.0:
		return
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# Estremità accorciate, per non coprire i pezzi sotto.
	var a2 := a + dir * 10.0
	var b2 := b - dir * 12.0
	# Bordo scuro + linea colorata: si legge sia sui Deserti chiari sia sui
	# Labirinti scuri della tavola.
	draw_line(a2, b2, Color(0, 0, 0, 0.5), 5.0)
	draw_line(a2, b2, color, 3.0)
	var head := 13.0
	var tip := b - dir * 4.0
	draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * head + perp * head * 0.55, tip - dir * head - perp * head * 0.55]), color)
	draw_circle(a, 4.5, Color(0, 0, 0, 0.5))
	draw_circle(a, 3.0, color)
	# Quante unità viaggiano su quella freccia.
	if count > 1 and _font != null:
		var mid := (a2 + b2) * 0.5 + perp * 9.0
		draw_string(_font, mid, "×%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.95))
