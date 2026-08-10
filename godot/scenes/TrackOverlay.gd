class_name TrackOverlay
extends Control

## Disegna sopra la mappa i marcatori dei tracciati stampati, alle coordinate
## esatte estratte dal Vassal (board_layout.json):
##   * Edge Track 0-50: Risorse MG/RD, Profits e i marcatori di vittoria;
##   * traccia EarthGov Confidence (9 caselle, marcatore bifacciale EG+/EG-);
##   * traccia Flashpoint 0-4 + innesco;
##   * cilindri della Sequence of Play, nella casella dove sono davvero.
##
## I marcatori stanno DENTRO la casella: quando più marcatori condividono lo
## stesso valore si dispongono a griglia, come le pedine sul tavolo. I numeri
## esatti si leggono nel pannello laterale, non da qui.
##
## Le pedine sono quelle ORIGINALI del gioco, importate dal modulo Vassal: il
## marcatore Profits col logo delle Corporations, il Flashpoint col fulmine, il
## bifacciale EG+/EG−, i cilindri delle quattro Fazioni. Se una texture manca si
## ricade sul disco colorato di prima, così non resta mai una casella vuota.

## Raggio del marcatore in frazione del passo fra due caselle dell'Edge Track.
const EDGE_R_FRAC := 0.34
## Sotto questo raggio la sigla non si legge più: meglio lasciare la pedina muta
## (il valore esatto si legge comunque nel pannello laterale).
const MIN_LABEL_R := 6.5

## Marcatori sull'Edge Track: chiave di stato -> (etichetta, colore di ripiego).
const EDGE_MARKERS := [
	{"key": "marsgov_resources", "label": "MG", "color": Color("2f6fb5")},
	{"key": "red_dust_resources", "label": "RD", "color": Color("c0392b")},
	{"key": "profits", "label": "$", "color": Color("2b2b2b")},
	{"key": "support_plus_eg", "label": "S+", "color": Color("5b9bd5")},
	{"key": "oppose_plus_bases", "label": "O+", "color": Color("e05a4b")},
	{"key": "cr_control_plus_bases", "label": "CR", "color": Color("e67e22")},
	{"key": "enemy_bases", "label": "EB", "color": Color("7f8c8d")},
]

## Casella della Sequence of Play per ogni azione registrata da SequenceOfPlay.
## NB: nel Vassal la terza casella della colonna "2ª Fazione" si chiama "2nd
## Faction Event", ma è la riga in cui la 1ª ha giocato l'Evento: è lì che va il
## cilindro della 2ª quando svolge la sua Operazione.
const SOP_BOXES := {
	"1st_op_only": "op1_op",
	"1st_op_sa": "op1_op_sa",
	"1st_event": "op1_event",
	"2nd_limop": "op2_limop",
	"2nd_limop_or_event": "op2_limop_or_event",
	"2nd_op_sa": "op2_event",
	"pass": "pass",
}

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
	_draw_cards_in_play(gc)


func _edge_value(gc, key: String) -> int:
	match key:
		"marsgov_resources": return gc.state.get_resources("marsgov")
		"red_dust_resources": return gc.state.get_resources("red_dust")
		_: return int(gc.state.tracks.get(key, 0))


## Passo fra due caselle contigue dell'Edge Track, in pixel: dà la misura della
## casella, e quindi quanto può essere grande un marcatore che ci sta dentro.
func _edge_pitch(track: Dictionary) -> float:
	var steps: Array[float] = []
	for v in range(1, 50):
		if track.has(str(v)) and track.has(str(v + 1)):
			steps.append(_norm_to_px(track[str(v)]).distance_to(_norm_to_px(track[str(v + 1)])))
	if steps.is_empty():
		return 24.0
	steps.sort()
	return steps[steps.size() / 2]


func _draw_edge_track(gc) -> void:
	var track: Dictionary = gc.layout.get("edge_track", {})
	if track.is_empty():
		return
	var r: float = maxf(5.0, _edge_pitch(track) * EDGE_R_FRAC)
	# Prima si raggruppano i marcatori per casella: quelli sullo stesso valore
	# vanno impilati, non sparsi.
	var by_box: Dictionary = {}
	for m in EDGE_MARKERS:
		var v: int = clampi(_edge_value(gc, String(m["key"])), 0, 50)
		if not track.has(str(v)):
			continue
		if not by_box.has(v):
			by_box[v] = []
		by_box[v].append(m)
	var pitch: float = _edge_pitch(track)
	for v in by_box.keys():
		var stack: Array = by_box[v]
		var base := _norm_to_px(track[str(v)])
		# Più marcatori sulla stessa casella si dispongono a griglia DENTRO la
		# casella, rimpicciolendosi quanto basta: impilarli li renderebbe
		# illeggibili, spargerli fuori li porterebbe sulle caselle vicine.
		var cols: int = ceili(sqrt(float(stack.size())))
		var rows: int = ceili(float(stack.size()) / float(cols))
		var cell: float = pitch / float(maxi(cols, rows))
		var rr: float = minf(r, cell * 0.46)
		for i in range(stack.size()):
			var p := base + Vector2(
				(i % cols - (cols - 1) * 0.5) * cell,
				(i / cols - (rows - 1) * 0.5) * cell)
			_chip(p, rr, stack[i]["color"] as Color,
				String(stack[i]["label"]) if rr >= MIN_LABEL_R else "")


## Marcatore di un tracciato. Con `key` si usa la pedina originale del gioco;
## senza (o se la texture manca) si ricade sul disco colorato con la sigla.
func _chip(p: Vector2, r: float, col: Color, label: String, key: String = "") -> void:
	if key != "":
		var tex := RDRAssets.track_tex(key)
		if tex != null:
			_stamp(tex, p, r * 2.15)
			return
	draw_circle(p + Vector2(0, r * 0.12), r, Color(0, 0, 0, 0.45))
	draw_circle(p, r, col)
	draw_circle(p, r, Color(1, 1, 1, 0.9), false, maxf(1.0, r * 0.14))
	if label == "":
		return
	var fs: int = maxi(8, int(r * 1.05))
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, p + Vector2(-w * 0.5, fs * 0.36), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.97))


## Disegna una texture centrata in `p`, alta `side` pixel, con un'ombra sotto
## che la stacca dalla plancia stampata.
func _stamp(tex: Texture2D, p: Vector2, side: float) -> void:
	var sz := Vector2(side, side * float(tex.get_height()) / float(tex.get_width()))
	var r := Rect2(p - sz * 0.5, sz)
	draw_texture_rect(tex, Rect2(r.position + Vector2(0, sz.y * 0.08), r.size),
		false, Color(0, 0, 0, 0.4))
	draw_texture_rect(tex, r, false)


func _draw_eg_confidence(gc) -> void:
	var boxes: Array = gc.layout.get("eg_confidence_boxes", [])
	if boxes.size() != 9:
		return
	var idx: int = clampi(int(gc.state.tracks.get("eg_confidence", 0)), 0, 8)
	var r: float = maxf(6.0, 11.0 * size.x / 1500.0)
	var side := int(gc.state.tracks.get("eg_side", -1))
	# Il marcatore è bifacciale: verde EG+, rosso EG−. Il valore della casella si
	# legge nel pannello laterale.
	_chip(_norm_to_px(boxes[idx]), r,
		Color("27ae60") if side > 0 else Color("c0392b"), "+" if side > 0 else "−",
		"eg_plus" if side > 0 else "eg_minus")


func _draw_flashpoint(gc) -> void:
	var fp: Dictionary = gc.layout.get("flashpoint_track", {})
	var v: int = clampi(int(gc.state.tracks.get("flashpoint", 0)), 0, 5)
	var key := "trigger" if v >= 5 else str(v)
	if not fp.has(key):
		return
	var r: float = maxf(6.0, 11.0 * size.x / 1500.0)
	_chip(_norm_to_px(fp[key]), r, Color("f1c40f"), "", "flashpoint")


## §4.1: ogni Fazione ha un cilindro, e sta nella casella che racconta cosa ha
## fatto in questa carta — Disponibile, Passa, oppure la casella dell'azione.
func _sop_box_for(gc, fid: String) -> String:
	if gc.sequence != null:
		var box := String(gc.sequence.action_box.get(fid, ""))
		if box != "" and SOP_BOXES.has(box):
			return String(SOP_BOXES[box])
	if gc.state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) \
			== CoinEnums.Eligibility.ELIGIBLE:
		return "eligible"
	return "ineligible"


func _draw_sop(gc) -> void:
	var sop: Dictionary = gc.layout.get("sop", {})
	if sop.is_empty():
		return
	var r: float = maxf(5.0, 9.0 * size.x / 1500.0)
	# Più cilindri nella stessa casella si affiancano invece di sovrapporsi.
	var by_box: Dictionary = {}
	for f in gc.game_def.factions:
		if f.id == "earthgov":
			continue  # EarthGov non ha cilindro: la controlla MarsGov o CORP (§1.2)
		var box := _sop_box_for(gc, f.id)
		if not sop.has(box):
			continue
		if not by_box.has(box):
			by_box[box] = []
		by_box[box].append(f.id)
	for box in by_box.keys():
		var here: Array = by_box[box]
		var center := _norm_to_px(sop[box])
		for i in range(here.size()):
			var p := center + Vector2((i - (here.size() - 1) * 0.5) * r * 2.3, 0)
			_cylinder(p, r, RDRAssets.FACTION_COLORS.get(String(here[i]), Color.WHITE) as Color,
				String(here[i]))


## §1.5: la plancia ha in fondo i riquadri stampati per la Campaign card in
## gioco e per le Asset card dei Reclaimer che restano in tavola (le
## Capability). Erano vuoti, e quella fascia sembrava spazio sprecato: sono
## invece il posto dove il gioco vero tiene le carte che continuano a valere.
func _draw_cards_in_play(gc) -> void:
	var slots: Dictionary = gc.layout.get("card_slots", {})
	if slots.is_empty() or gc.cards == null:
		return
	# Larghezza di una carta: i tre riquadri Campaign sono equidistanti, e la
	# distanza fra due è la misura giusta da cui ricavarla.
	var w: float = 90.0 * size.x / 1500.0
	if slots.has("campaign_1") and slots.has("campaign_2"):
		w = _norm_to_px(slots["campaign_1"]).distance_to(_norm_to_px(slots["campaign_2"])) * 0.92
	var camp: int = gc.cards.campaign_in_play()
	if camp > 0 and slots.has("campaign_1"):
		_card_at(RDRAssets.campaign_tex(camp), _norm_to_px(slots["campaign_1"]), w)
	# Le Capability restano in gioco per sempre e col tempo diventano tante: si
	# dispongono a ventaglio verso sinistra a partire dal loro riquadro, con un
	# passo che si stringe quando aumentano, così non invadono i riquadri delle
	# Campaign accanto. La più recente resta sopra e leggibile per intero.
	var caps: Array = gc.state.tracks.get("capabilities", [])
	if not caps.is_empty() and slots.has("assets_in_play"):
		var base := _norm_to_px(slots["assets_in_play"])
		var span := w * 1.6                       # spazio che il ventaglio può occupare
		var step: float = minf(w * 0.5, span / float(maxi(1, caps.size())))
		for i in range(caps.size() - 1, -1, -1):
			_card_at(RDRAssets.asset_tex(int(caps[i])),
				base - Vector2(float(i) * step, 0.0), w)


## Una carta disegnata centrata in `p`, larga `w`, con l'ombra che la stacca.
func _card_at(tex: Texture2D, p: Vector2, w: float) -> void:
	if tex == null:
		return
	var h := w * float(tex.get_height()) / float(tex.get_width())
	var r := Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(0, h * 0.02), r.size), Color(0, 0, 0, 0.5))
	draw_texture_rect(tex, r, false)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


## Il cilindro dell'Eligibility, nella pedina originale della Fazione. Senza
## texture si ricade su un rettangolo alto, che almeno non si confonde con i
## marcatori rotondi dei tracciati.
func _cylinder(p: Vector2, r: float, col: Color, fid: String = "") -> void:
	var tex := RDRAssets.pawn_tex(fid)
	if tex != null:
		_stamp(tex, p, r * 2.4)
		return
	var w := r * 1.25
	var h := r * 1.9
	var rect := Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(Rect2(rect.position + Vector2(0, r * 0.12), rect.size), Color(0, 0, 0, 0.45))
	draw_rect(rect, col)
	draw_rect(rect, Color(1, 1, 1, 0.9), false, maxf(1.0, r * 0.16))
