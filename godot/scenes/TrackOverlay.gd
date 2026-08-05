class_name TrackOverlay
extends Control

## Disegna sopra la mappa i marcatori dei tracciati stampati, alle coordinate
## esatte estratte dal Vassal (board_layout.json):
##   * Edge Track 0-50: Risorse MG/RD, Profits e i marcatori di vittoria;
##   * traccia EarthGov Confidence (9 caselle, marcatore bifacciale EG+/EG-);
##   * traccia Flashpoint 0-4 + innesco;
##   * cilindri Eligibility nella Sequence of Play.

const DOT_R := 9.0

## Marcatori sull'Edge Track: chiave di stato -> (etichetta, colore).
const EDGE_MARKERS := [
	{"key": "marsgov_resources", "label": "MG", "color": Color("2f6fb5"), "row": 0},
	{"key": "red_dust_resources", "label": "RD", "color": Color("c0392b"), "row": 1},
	{"key": "profits", "label": "$", "color": Color("2b2b2b"), "row": 2},
	{"key": "support_plus_eg", "label": "S+", "color": Color("5b9bd5"), "row": 3},
	{"key": "oppose_plus_bases", "label": "O+", "color": Color("e05a4b"), "row": 4},
	{"key": "cr_control_plus_bases", "label": "CR", "color": Color("e67e22"), "row": 5},
	{"key": "enemy_bases", "label": "EB", "color": Color("7f8c8d"), "row": 6},
]

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _norm_to_px(p) -> Vector2:
	return Vector2(float(p[0]) * size.x, float(p[1]) * size.y)


func _draw() -> void:
	var gc := GameController
	if gc.state == null or gc.layout.is_empty():
		return
	_draw_edge_track(gc)
	_draw_eg_confidence(gc)
	_draw_flashpoint(gc)
	_draw_sop(gc)


func _edge_value(gc, key: String) -> int:
	match key:
		"marsgov_resources": return gc.state.get_resources("marsgov")
		"red_dust_resources": return gc.state.get_resources("red_dust")
		_: return int(gc.state.tracks.get(key, 0))


func _draw_edge_track(gc) -> void:
	var track: Dictionary = gc.layout.get("edge_track", {})
	if track.is_empty():
		return
	var r: float = maxf(5.0, DOT_R * size.x / 1500.0)
	for m in EDGE_MARKERS:
		var v: int = clampi(_edge_value(gc, String(m["key"])), 0, 50)
		if not track.has(str(v)):
			continue
		# I sette marcatori sono impilati in colonna sotto la casella: sul tavolo
		# starebbero tutti nella stessa casella e si coprirebbero a vicenda.
		var p := _norm_to_px(track[str(v)]) + Vector2(0, r * 1.9 * (int(m["row"]) + 1))
		draw_circle(p, r * 0.85, m["color"] as Color)
		draw_circle(p, r * 0.85, Color(1, 1, 1, 0.85), false, 1.2)
		draw_string(_font, p + Vector2(r * 1.1, r * 0.45), "%s%d" % [m["label"], v],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.35), Color(1, 1, 1, 0.92))


func _draw_eg_confidence(gc) -> void:
	var boxes: Array = gc.layout.get("eg_confidence_boxes", [])
	if boxes.size() != 9:
		return
	var idx: int = clampi(int(gc.state.tracks.get("eg_confidence", 0)), 0, 8)
	var p := _norm_to_px(boxes[idx])
	var r: float = maxf(6.0, 11.0 * size.x / 1500.0)
	var side := int(gc.state.tracks.get("eg_side", -1))
	var col := Color("27ae60") if side > 0 else Color("c0392b")
	draw_circle(p, r, col)
	draw_circle(p, r, Color(1, 1, 1, 0.9), false, 2.0)
	var m: RDRModule = gc.rdr()
	var txt := "%s  %d" % ["EG+" if side > 0 else "EG-", m.eg_confidence_value(gc.state)]
	draw_string(_font, p + Vector2(-r * 5.4, r * 0.4), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.5), Color(1, 1, 1, 0.95))


func _draw_flashpoint(gc) -> void:
	var fp: Dictionary = gc.layout.get("flashpoint_track", {})
	var v: int = clampi(int(gc.state.tracks.get("flashpoint", 0)), 0, 5)
	var key := "trigger" if v >= 5 else str(v)
	if not fp.has(key):
		return
	var p := _norm_to_px(fp[key])
	var r: float = maxf(6.0, 11.0 * size.x / 1500.0)
	draw_circle(p, r, Color("f1c40f"))
	draw_circle(p, r, Color(0, 0, 0, 0.8), false, 2.0)


func _draw_sop(gc) -> void:
	var sop: Dictionary = gc.layout.get("sop", {})
	if sop.is_empty():
		return
	var r: float = maxf(5.0, 9.0 * size.x / 1500.0)
	var i := 0
	for f in gc.game_def.factions:
		if f.id == "earthgov":
			continue
		var box := "eligible" if gc.state.eligibility.get(f.id, CoinEnums.Eligibility.ELIGIBLE) \
			== CoinEnums.Eligibility.ELIGIBLE else "ineligible"
		if not sop.has(box):
			continue
		# I quattro cilindri sono affiancati dentro la casella.
		var p := _norm_to_px(sop[box]) + Vector2((i - 1.5) * r * 2.4, 0)
		draw_circle(p, r, RDRAssets.FACTION_COLORS.get(f.id, Color.WHITE) as Color)
		draw_circle(p, r, Color(1, 1, 1, 0.9), false, 1.5)
		i += 1
