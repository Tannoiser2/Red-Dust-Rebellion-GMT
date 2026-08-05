extends Control

## Schermata di gioco: mappa di Mars a sinistra (scalata mantenendo le proporzioni
## della tavola Vassal 5175x3775), pannello di stato a destra.

const BUILD_VERSION := "b001"

var _map_root: Control
var _map_tex: TextureRect
var _regions_layer: Control
var _tracks: TrackOverlay
var _side: VBoxContainer
var _status: RichTextLabel
var _space_info: RichTextLabel
var _card_info: RichTextLabel
var _btn_pass: Button
var _btn_end: Button
var _ops_box: HBoxContainer
var _op_mode := ""          ## Operazione in corso di pianificazione
var _op_spaces: Array[String] = []
var _op_candidates: PackedStringArray = PackedStringArray()
var _log: RichTextLabel
var _views: Dictionary = {}   ## space_id -> RegionView
var _selected := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	GameController.state_changed.connect(_on_state_changed)
	GameController.log_line.connect(_append_log)
	if GameController.state != null:
		_build_regions()
		_on_state_changed()


# ---------------------------------------------------------------------------
# Costruzione UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = -360
	add_child(split)

	# --- Mappa -------------------------------------------------------------
	var map_wrap := Control.new()
	map_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_wrap.clip_contents = true
	map_wrap.resized.connect(_relayout_map)
	split.add_child(map_wrap)

	_map_root = Control.new()
	_map_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_wrap.add_child(_map_root)

	_map_tex = TextureRect.new()
	_map_tex.texture = RDRAssets.tex("map.jpg")
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_map_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(_map_tex)

	_regions_layer = Control.new()
	_regions_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_regions_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(_regions_layer)

	_tracks = TrackOverlay.new()
	_tracks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(_tracks)

	# --- Pannello laterale --------------------------------------------------
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	split.add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 10)
	scroll.add_child(_side)

	_side.add_child(_title("Red Dust Rebellion  ·  %s" % BUILD_VERSION))
	_status = _rich(240)
	_side.add_child(_status)

	_side.add_child(_title("Carta e turno"))
	_card_info = _rich(120)
	_side.add_child(_card_info)

	var actions := HBoxContainer.new()
	_btn_pass = Button.new()
	_btn_pass.text = "Passa"
	_btn_pass.pressed.connect(func(): GameController.do_pass())
	actions.add_child(_btn_pass)
	_btn_end = Button.new()
	_btn_end.text = "Concludi carta"
	_btn_end.pressed.connect(func(): GameController.end_card())
	actions.add_child(_btn_end)
	_side.add_child(actions)

	_ops_box = HBoxContainer.new()
	_ops_box.add_theme_constant_override("separation", 4)
	_side.add_child(_ops_box)

	_side.add_child(_title("Spazio selezionato"))
	_space_info = _rich(150)
	_side.add_child(_space_info)

	var buttons := HBoxContainer.new()
	var b_new := Button.new()
	b_new.text = "Nuova partita"
	b_new.pressed.connect(func(): GameController.new_game())
	buttons.add_child(b_new)
	_side.add_child(buttons)

	_side.add_child(_title("Log"))
	_log = _rich(200)
	_side.add_child(_log)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("e0b070"))
	return l


func _rich(min_h: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(0, min_h)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _build_regions() -> void:
	for c in _regions_layer.get_children():
		c.queue_free()
	_views.clear()
	# Spazi della mappa + spazi fuori Mars (Aldrin Cycler, Orbita, box di servizio),
	# così anche i 16 pezzi schierati su Earth/Transit/Phobos/Orbit sono visibili.
	var all_regions: Dictionary = {}
	for sid in GameController.off_map.keys():
		all_regions[sid] = GameController.off_map[sid]
	for sid in GameController.regions.keys():
		all_regions[sid] = GameController.regions[sid]

	# Ordine di disegno del Vassal: i Deserti sotto, i Labirinti (cerchi) sopra,
	# così nella zona di sovrapposizione il clic va al Labirinto.
	var ids: Array = all_regions.keys()
	ids.sort_custom(func(a, b):
		return int(all_regions[a].get("z", -1)) < int(all_regions[b].get("z", -1)))
	for sid in ids:
		var sd: SpaceDef = GameController.game_def.space(sid)
		if sd == null:
			continue
		var rv := RegionView.new()
		rv.set_anchors_preset(Control.PRESET_FULL_RECT)
		_regions_layer.add_child(rv)
		rv.setup(sd, all_regions[sid])
		rv.space_clicked.connect(_on_space_clicked)
		_views[sid] = rv
	_relayout_map()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _relayout_map() -> void:
	if _map_root == null or _map_root.get_parent() == null:
		return
	var avail: Vector2 = (_map_root.get_parent() as Control).size
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var board_w := 5175.0
	var board_h := 3775.0
	var scale: float = minf(avail.x / board_w, avail.y / board_h)
	var w := board_w * scale
	var h := board_h * scale
	_map_root.position = Vector2((avail.x - w) * 0.5, (avail.y - h) * 0.5)
	_map_root.size = Vector2(w, h)
	for sid in _views.keys():
		(_views[sid] as RegionView).relayout()
	_tracks.queue_redraw()


# ---------------------------------------------------------------------------
# Stato
# ---------------------------------------------------------------------------

func _on_state_changed() -> void:
	if _views.is_empty():
		_build_regions()
	var m: RDRModule = GameController.rdr()
	for sid in _views.keys():
		(_views[sid] as RegionView).refresh(GameController.state, m)
	_tracks.queue_redraw()
	_refresh_status()
	_refresh_card_info()
	_refresh_op_bar()
	if _selected != "":
		_refresh_space_info(_selected)


func _refresh_status() -> void:
	var gc := GameController
	var m: RDRModule = gc.rdr()
	var st := gc.state
	var v := m.victory_status(st)
	var eg_ctrl := m.eg_controller(st)
	var ctrl_name := "nessuno"
	if eg_ctrl != "":
		ctrl_name = gc.game_def.faction(eg_ctrl).short_name

	var lines: Array[String] = []
	lines.append("[b]EarthGov[/b]  Confidence %d  ·  Controller: %s  ·  %s" % [
		m.eg_confidence_value(st), ctrl_name,
		"EG+" if int(st.tracks.get("eg_side", -1)) > 0 else "EG-"])
	lines.append("Flashpoint %d/5  ·  Displaced Pop %d  ·  Dust Storm %d/3" % [
		int(st.tracks.get("flashpoint", 0)),
		int(st.tracks.get("displaced_population", 0)),
		int(st.tracks.get("dust_storm_rounds", 0))])
	lines.append("")
	lines.append("[b]Vittoria[/b]")
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		var f: FactionDef = gc.game_def.faction(fid)
		var d: Dictionary = v[fid]
		var col: String = RDRAssets.text_color(fid).to_html(false)
		var res := ""
		if fid in ["marsgov", "red_dust"]:
			res = "  ·  %d Ris." % st.get_resources(fid)
		lines.append("[color=#%s]%s[/color]  %d / %d  (%+d)%s" % [
			col, f.short_name, d["value"], d["threshold"], d["margin"], res])
	lines.append("")
	lines.append("[b]Controllo[/b]  COIN %d  ·  Red Dust %d  ·  Reclaimer %d  ·  libero %d" % [
		_count_control("coin"), _count_control("red_dust"),
		_count_control("reclaimer"), _count_control("")])
	lines.append("Supporto totale %d  ·  Opposizione totale %d" % [
		m.total_support(st), m.total_opposition(st)])
	_status.text = "\n".join(lines)


## Carta corrente, prossima carta, ordine di Eligibility e turno in corso (§4.1).
func _refresh_card_info() -> void:
	var gc := GameController
	var r: RDRRounds = gc.rounds
	if r == null:
		return
	var lines: Array[String] = []
	var cur: CardDef = gc.game_def.card(r.current_card())
	if cur != null:
		var m: RDRModule = gc.rdr()
		lines.append("[b]#%d %s[/b]  ⚡%d" % [
			cur.number, cur.title, int(m.card_flashpoint.get(cur.number, 0))])
		var order: Array[String] = []
		for fid in cur.faction_order:
			var mark := ""
			if gc.state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) \
					!= CoinEnums.Eligibility.ELIGIBLE:
				mark = "~"
			order.append("%s%s%s" % [mark, gc.game_def.faction(fid).short_name, mark])
		lines.append("Ordine: %s   [i](~non disponibile~)[/i]" % " › ".join(order))
	var nxt: CardDef = gc.game_def.card(r.next_card())
	if nxt != null:
		lines.append("Prossima: #%d %s" % [nxt.number, nxt.title])
	if r.haboob_active():
		lines.append("[color=#e0b070]Haboob: Recon e March vietati.[/color]")
	if r.is_game_over():
		lines.append("[b]Partita finita.[/b] Vincitore: %s" % String(gc.state.tracks.get("winner", "—")))
	elif gc.sequence != null:
		var pending := gc.sequence.pending_faction()
		if pending != "":
			lines.append("Tocca a [b]%s[/b] (%s Disponibile)" % [
				gc.game_def.faction(pending).short_name,
				"1ª" if gc.sequence.is_first_slot() else "2ª"])
		else:
			lines.append("Carta conclusa: premi «Concludi carta».")
	_card_info.text = "\n".join(lines)
	var can_act: bool = gc.sequence != null and gc.sequence.pending_faction() != ""
	_btn_pass.disabled = not can_act
	_btn_end.disabled = gc.rounds == null or gc.rounds.is_game_over()


## Conta gli spazi della mappa di Mars (23 + Wilderness). Phobos è escluso:
## è sempre sotto Controllo COIN per regola e falserebbe il totale.
func _count_control(control: String) -> int:
	var n := 0
	for sid in _views.keys():
		var sd: SpaceDef = GameController.game_def.space(sid)
		if sd.type == CoinEnums.SpaceType.COUNTRY or sid == "phobos":
			continue
		if GameController.state.space_state(sid).control == control:
			n += 1
	return n


func _on_space_clicked(space_id: String) -> void:
	if _op_mode != "":
		if not _op_candidates.has(space_id):
			_append_log("%s non è selezionabile per %s." % [
				GameController.game_def.space(space_id).name,
				GameController.OPERATION_NAMES.get(_op_mode, _op_mode)])
		elif _op_spaces.has(space_id):
			_op_spaces.erase(space_id)
		else:
			_op_spaces.append(space_id)
		_refresh_op_bar()
		_paint_op_highlight()
		_refresh_space_info(space_id)
		_selected = space_id
		return
	_selected = space_id
	for sid in _views.keys():
		(_views[sid] as RegionView).set_highlight(sid == space_id)
	_refresh_space_info(space_id)


# ---------------------------------------------------------------------------
# Operazioni (§5.0)
# ---------------------------------------------------------------------------

func _start_op(op_id: String) -> void:
	var gc := GameController
	_op_mode = op_id
	_op_spaces.clear()
	_op_candidates = gc.operation_candidates(op_id, gc.sequence.pending_faction())
	_append_log("%s: scegli gli spazi (%d disponibili), poi «Esegui»." % [
		gc.OPERATION_NAMES.get(op_id, op_id), _op_candidates.size()])
	_paint_op_highlight()
	_refresh_op_bar()


func _cancel_op() -> void:
	_op_mode = ""
	_op_spaces.clear()
	_op_candidates = PackedStringArray()
	_paint_op_highlight()
	_refresh_op_bar()


func _confirm_op() -> void:
	if _op_mode == "" or _op_spaces.is_empty():
		return
	var res: Dictionary = GameController.execute_operation(_op_mode, Array(_op_spaces))
	if not res.get("ok", false):
		_append_log("[color=#e05a4b]%s[/color]" % res.get("error", "azione rifiutata"))
		return
	_cancel_op()


## Evidenzia in bianco gli spazi scelti; gli altri candidati restano cliccabili.
func _paint_op_highlight() -> void:
	for sid in _views.keys():
		(_views[sid] as RegionView).set_highlight(_op_spaces.has(sid))


## Ricostruisce la barra delle azioni: le Operazioni della Fazione di turno,
## oppure «Esegui / Annulla» mentre si stanno scegliendo gli spazi.
func _refresh_op_bar() -> void:
	for c in _ops_box.get_children():
		c.queue_free()
	var gc := GameController
	if gc.sequence == null or gc.sequence.pending_faction() == "":
		return
	var fid := gc.sequence.pending_faction()
	if _op_mode == "":
		for op_id in gc.UI_OPERATIONS.get(fid, []):
			var b := Button.new()
			b.text = gc.OPERATION_NAMES.get(op_id, op_id)
			b.pressed.connect(_start_op.bind(String(op_id)))
			_ops_box.add_child(b)
		return
	var run := Button.new()
	run.text = "Esegui (%d)" % _op_spaces.size()
	run.disabled = _op_spaces.is_empty()
	run.pressed.connect(_confirm_op)
	_ops_box.add_child(run)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.pressed.connect(_cancel_op)
	_ops_box.add_child(cancel)


func _refresh_space_info(space_id: String) -> void:
	var gc := GameController
	var m: RDRModule = gc.rdr()
	var sd: SpaceDef = gc.game_def.space(space_id)
	var st: SpaceState = gc.state.space_state(space_id)

	var kind := "Labirinto" if sd.terrain == "labyrinth" else "Deserto"
	var ctrl := st.control if st.control != "" else "incontrollato"
	var lines: Array[String] = []
	lines.append("[b]%s[/b]  (%s)" % [sd.name, kind])
	lines.append("Popolazione %d  ·  Danno %d  ·  Controllo: %s" % [
		m.population(gc.state, space_id), int(st.markers.get("damage", 0)), ctrl])
	lines.append("Allineamento: %s" % _support_name(st.support))
	var adj: Array[String] = []
	for a in sd.adjacent:
		adj.append(gc.game_def.space(a).name)
	lines.append("Adiacenze: %s" % (", ".join(adj) if adj.size() > 0 else "—"))
	var mag := m.maglev_links(gc.state, space_id)
	if mag.size() > 0:
		var names: Array[String] = []
		for x in mag:
			names.append(gc.game_def.space(x).name)
		lines.append("Maglev: %s" % ", ".join(names))
	lines.append("")
	var any := false
	for fid in st.pieces.keys():
		for type_id in st.pieces[fid].keys():
			for piece_state in st.pieces[fid][type_id].keys():
				var n := int(st.pieces[fid][type_id][piece_state])
				if n <= 0:
					continue
				any = true
				var pt: PieceTypeDef = gc.game_def.piece_type(type_id)
				var suffix := "" if piece_state == "" else " (%s)" % piece_state
				lines.append("[color=#%s]%d× %s%s[/color]" % [
					RDRAssets.text_color(fid).to_html(false), n, pt.name, suffix])
	if not any:
		lines.append("[i]nessuna forza[/i]")
	_space_info.text = "\n".join(lines)


func _support_name(level: int) -> String:
	match level:
		CoinEnums.Support.ACTIVE_SUPPORT: return "Supporto Attivo"
		CoinEnums.Support.PASSIVE_SUPPORT: return "Supporto Passivo"
		CoinEnums.Support.PASSIVE_OPPOSITION: return "Opposizione Passiva"
		CoinEnums.Support.ACTIVE_OPPOSITION: return "Opposizione Attiva"
		_: return "Neutrale"


func _append_log(text: String) -> void:
	_log.text += ("\n" if _log.text != "" else "") + text
