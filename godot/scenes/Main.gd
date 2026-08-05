extends Control

## Schermata di gioco: mappa di Mars a sinistra (scalata mantenendo le proporzioni
## della tavola Vassal 5175x3775), pannello di stato a destra.

const BUILD_VERSION := "b001"

## Che cosa fa ciascuna Operazione, in una riga: il regolamento è di 40 pagine e
## nessuno se lo ricorda a memoria mentre gioca (§5.0).
const OPERATION_TIPS := {
	"train": "§5.1 Train — MarsGov: piazza Truppe negli spazi con Base MG o nei Labirinti sotto Controllo COIN; può Pacify in uno di essi.",
	"logistics": "§5.2 Logistics — Corporations: compra su Earth e potenzia le Basi nei Deserti scelti.",
	"secure": "§5.3 Secure — porta cubi COIN nei Labirinti (adiacenza, Maglev, Spaceport) e Attiva i Ribelli presenti.",
	"recon": "§5.4 Recon — come Secure ma verso i Deserti; vietato durante l'Haboob.",
	"assault": "§5.5 Assault — rimuove Ribelli Attivi negli spazi scelti; le Basi si tolgono solo quando non restano Ribelli a difenderle.",
	"rally": "§5.6 Rally — Ribelli: piazza Ribelli o costruisce una Base negli spazi Popolati senza Supporto (Reclaimer: spazi Neutrali).",
	"march": "§5.7 March — Red Dust: sposta Ribelli di uno spazio, più i salti Maglev e Spaceport fra Labirinti controllati.",
	"travel": "§5.8 Travel — Reclaimer: sposta Ribelli e Basi dagli spazi scelti, ignorando le tempeste.",
	"attack": "§5.9 Attack — tira due dadi: rimuove forze nemiche e può piazzare Danno. Con Ambush si scelgono i dadi.",
	"campaign": "§5.10 Campaign — Red Dust: sposta gli spazi verso l'Opposizione e mette in gioco una Campaign card.",
	"preach": "§5.11 Preach — Reclaimer: converte gli spazi Neutrali dove ha Ribelli Nascosti.",
}

var _board: ScrollContainer   ## area scorrevole della mappa
var _map_wrap: Control        ## definisce l'estensione scrollabile (base × zoom)
var _map_root: Control        ## la mappa vera, scalata dallo zoom
var _map_base := Vector2.ZERO ## dimensione della mappa a zoom 1 (adattata all'area)
var _zoom := 1.0
var _panning := false
var _map_tex: TextureRect
var _instr: RichTextLabel     ## riga che dice sempre cosa si può fare adesso
var _regions_layer: Control
var _tracks: TrackOverlay
var _moves: MovesOverlay    ## frecce degli spostamenti dichiarati
var _side: VBoxContainer
var _status: RichTextLabel
var _space_info: RichTextLabel
var _card_info: RichTextLabel
var _card_now: TextureRect          ## anteprima della carta in corso
var _card_next: TextureRect         ## anteprima della prossima carta
var _card_zoom: Control             ## ingrandimento a schermo intero
var _btn_pass: Button
var _btn_end: Button
var _btn_undo: Button
var _ops_box: HFlowContainer
var _op_mode := ""          ## Operazione in corso di pianificazione
var _op_spaces: Array[String] = []
var _op_candidates: PackedStringArray = PackedStringArray()
var _op_moves: Array = []              ## spostamenti dichiarati {from,to,type,count}
var _sa_mode := ""                     ## Attività Speciale in corso
## §7.0: Evento in corso di pianificazione — le sue scelte si raccolgono una
## alla volta (spazi sulla mappa, Fazioni e rami con i pulsanti della barra).
var _ev_active := false
var _ev_shaded := false
var _ev_choices: Dictionary = {}
var _ev_reqs: Array = []
var _ev_index := 0
var _move_box: VBoxContainer
var _preview: RichTextLabel   ## costo ed effetti previsti dell'azione in preparazione
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
	theme = RDRTheme.make_theme()
	var bg := ColorRect.new()
	bg.color = RDRTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = -360
	add_child(split)

	# --- Mappa -------------------------------------------------------------
	# ScrollContainer + wrapper: lo zoom è una SCALA sul nodo mappa, così mappa,
	# pedine e marcatori ingrandiscono insieme, e il wrapper (base × zoom) dice
	# allo scroll quanto c'è da scorrere.
	var map_col := VBoxContainer.new()
	map_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(map_col)

	var instr_panel := PanelContainer.new()
	_instr = RichTextLabel.new()
	_instr.bbcode_enabled = true
	_instr.fit_content = true
	_instr.custom_minimum_size = Vector2(0, 22)
	_instr.add_theme_font_size_override("normal_font_size", 13)
	instr_panel.add_child(_instr)
	map_col.add_child(instr_panel)

	_board = ScrollContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.resized.connect(_relayout_map)
	map_col.add_child(_board)

	_map_wrap = Control.new()
	_map_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_map_wrap)

	_map_root = Control.new()
	_map_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_wrap.add_child(_map_root)

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

	# Sopra a tutto: le frecce degli spostamenti ancora da eseguire.
	_moves = MovesOverlay.new()
	_moves.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(_moves)

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
	# Le due carte in vista, come sul tavolo: quella in corso e la prossima
	# (serve a decidere, il suo Flashpoint conta già). Un clic le ingrandisce.
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 6)
	_card_now = _add_card_slot(cards_row, "In corso", 1.0)
	_card_next = _add_card_slot(cards_row, "Prossima", 0.55)
	_side.add_child(cards_row)
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

	# HFlowContainer: i pulsanti vanno a capo invece di uscire dal pannello.
	_ops_box = HFlowContainer.new()
	_ops_box.add_theme_constant_override("h_separation", 4)
	_ops_box.add_theme_constant_override("v_separation", 4)
	_side.add_child(_ops_box)

	# Anteprima: costo ed effetti previsti PRIMA di premere «Esegui».
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.custom_minimum_size = Vector2(0, 18)
	_preview.add_theme_font_size_override("normal_font_size", 11)
	_side.add_child(_preview)

	_move_box = VBoxContainer.new()
	_move_box.add_theme_constant_override("separation", 2)
	_side.add_child(_move_box)

	_side.add_child(_title("Spazio selezionato"))
	_space_info = _rich(150)
	_side.add_child(_space_info)

	var buttons := HBoxContainer.new()
	# Partita: nuova, salva, riprendi. Il salvataggio sta in user://, cioè nella
	# cartella dati dell'app: non serve scegliere un percorso.
	var game_menu := MenuButton.new()
	game_menu.text = "Partita…"
	var pm := game_menu.get_popup()
	pm.add_item("Nuova partita", 0)
	pm.add_item("Salva", 1)
	pm.add_item("Riprendi l'ultima salvata", 2)
	pm.add_item("Riprendi il salvataggio automatico", 3)
	pm.add_separator()
	pm.add_item("Torna al menu", 4)
	pm.id_pressed.connect(_on_game_menu)
	buttons.add_child(game_menu)

	_btn_undo = Button.new()
	_btn_undo.text = "Annulla"
	_btn_undo.pressed.connect(func():
		GameController.undo()
		_cancel_op())
	buttons.add_child(_btn_undo)
	# Zoom: la tavola è 5175×3775, a schermo intero le pedine sono minuscole.
	var b_out := Button.new()
	b_out.text = "−"
	b_out.tooltip_text = "Rimpicciolisci (tasto −)"
	b_out.pressed.connect(func(): _zoom_at(1.0 / 1.25))
	buttons.add_child(b_out)
	var b_in := Button.new()
	b_in.text = "+"
	b_in.tooltip_text = "Ingrandisci (tasto +, rotellina, pinch)"
	b_in.pressed.connect(func(): _zoom_at(1.25))
	buttons.add_child(b_in)
	var b_fit := Button.new()
	b_fit.text = "Adatta"
	b_fit.tooltip_text = "Tavola intera (tasto 0). Col tasto destro si trascina la mappa."
	b_fit.pressed.connect(func(): _set_zoom(1.0))
	buttons.add_child(b_fit)
	_side.add_child(buttons)

	_side.add_child(_title("Log"))
	_log = _rich(200)
	_side.add_child(_log)


## Colonna con etichetta e anteprima cliccabile di una carta Evento.
## `alpha` distingue a colpo d'occhio la carta in corso da quella che verrà.
func _add_card_slot(row: HBoxContainer, label: String, alpha: float) -> TextureRect:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("9aa4ad"))
	col.add_child(l)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img.custom_minimum_size = Vector2(0, 150)
	img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img.modulate = Color(1, 1, 1, alpha)
	img.mouse_filter = Control.MOUSE_FILTER_STOP
	img.tooltip_text = "Clic per ingrandire"
	img.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_card_zoom(img.texture))
	col.add_child(img)
	row.add_child(col)
	return img


## Ingrandimento della carta a schermo intero: la scritta sulle carte Evento è
## illeggibile in miniatura, e serve leggerla per decidere.
func _show_card_zoom(tex: Texture2D) -> void:
	if tex == null:
		return
	if _card_zoom != null:
		_card_zoom.queue_free()
	_card_zoom = Control.new()
	_card_zoom.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_zoom.add_child(bg)
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.offset_left = 40
	img.offset_top = 40
	img.offset_right = -40
	img.offset_bottom = -40
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_zoom.add_child(img)
	var hint := Label.new()
	hint.text = "Clic o Esc per chiudere"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.position = Vector2(44, 14)
	_card_zoom.add_child(hint)
	_card_zoom.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_card_zoom())
	add_child(_card_zoom)


func _close_card_zoom() -> void:
	if _card_zoom != null:
		_card_zoom.queue_free()
		_card_zoom = null


## Scorciatoie da tastiera: Esc chiude l'ingrandimento o annulla la
## pianificazione in corso, +/− regolano lo zoom, 0 riporta la tavola intera.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or (event as InputEventKey).echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			if _card_zoom != null:
				_close_card_zoom()
			else:
				_cancel_op()
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			_zoom_at(1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(1.0 / 1.25)
		KEY_0, KEY_KP_0:
			_set_zoom(1.0)
		_:
			return
	get_viewport().set_input_as_handled()


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
		rv.piece_dropped.connect(_on_piece_dropped)
		_views[sid] = rv
	_relayout_map()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

## Zoom 1 = la tavola intera entra nell'area disponibile; da lì si ingrandisce.
func _relayout_map() -> void:
	if _board == null or _map_root == null:
		return
	var avail: Vector2 = _board.size
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var board_w := 5175.0
	var board_h := 3775.0
	var fit: float = minf(avail.x / board_w, avail.y / board_h)
	_map_base = Vector2(board_w * fit, board_h * fit)

	_map_root.position = Vector2.ZERO
	_map_root.custom_minimum_size = _map_base
	_map_root.size = _map_base
	_map_root.scale = Vector2(_zoom, _zoom)
	_map_wrap.custom_minimum_size = _map_base * _zoom
	_map_wrap.size = _map_base * _zoom

	# Le viste hanno anchor a tutto il riquadro, ma le dimensioniamo comunque a
	# mano: `relayout()` deve vedere la misura nuova subito, non al frame dopo.
	_map_tex.size = _map_base
	_regions_layer.size = _map_base
	for sid in _views.keys():
		var rv: RegionView = _views[sid]
		rv.position = Vector2.ZERO
		rv.size = _map_base
		rv.relayout()
	_tracks.size = _map_base
	_tracks.queue_redraw()
	_moves.size = _map_base
	_update_moves_overlay()


# ---------------------------------------------------------------------------
# Zoom e scorrimento della mappa
# ---------------------------------------------------------------------------

const ZOOM_MIN := 1.0
const ZOOM_MAX := 5.0


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_relayout_map()


## Zoom tenendo fermo il punto della mappa sotto il puntatore; senza puntatore
## si tiene fermo il centro di ciò che si sta guardando.
func _zoom_at(factor: float, screen_pos: Vector2 = Vector2(-1, -1)) -> void:
	if _board == null:
		return
	var local := screen_pos - _board.global_position
	if screen_pos.x < 0 or not Rect2(Vector2.ZERO, _board.size).has_point(local):
		local = _board.size * 0.5
	var old_zoom := _zoom
	var target: float = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(target, old_zoom):
		return
	var map_pt := (Vector2(_board.scroll_horizontal, _board.scroll_vertical) + local) / old_zoom
	_zoom = target
	_relayout_map()
	_board.scroll_horizontal = int(map_pt.x * _zoom - local.x)
	_board.scroll_vertical = int(map_pt.y * _zoom - local.y)


## Rotellina, gesto magnify del trackpad e trascinamento col tasto centrale o
## destro per scorrere la mappa ingrandita.
func _input(event: InputEvent) -> void:
	if _board == null or not is_inside_tree():
		return
	var over_board := Rect2(_board.global_position, _board.size)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and over_board.has_point(mb.position):
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at(1.15, mb.position)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at(1.0 / 1.15, mb.position)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
					_panning = true
					get_viewport().set_input_as_handled()
		elif not mb.pressed and mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = false
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		_board.scroll_horizontal -= int(mm.relative.x)
		_board.scroll_vertical -= int(mm.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if over_board.has_point(mg.position):
			_zoom_at(mg.factor, mg.position)
			get_viewport().set_input_as_handled()


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
	_refresh_instructions()
	_refresh_undo_btn()
	if _selected != "":
		_refresh_space_info(_selected)


## Il tasto Annulla dice anche COSA si sta per disfare: senza, non si sa se si
## sta togliendo l'ultima Operazione o la chiusura della carta.
func _refresh_undo_btn() -> void:
	if _btn_undo == null:
		return
	var gc := GameController
	_btn_undo.disabled = not gc.can_undo()
	_btn_undo.tooltip_text = "Annulla: %s" % gc.undo_label() if gc.can_undo() \
		else "Niente da annullare"


func _on_game_menu(id: int) -> void:
	match id:
		0:
			GameController.new_game()
			_cancel_op()
		1:
			GameController.save_game(GameController.SAVE_PATH)
		2:
			GameController.load_game(GameController.SAVE_PATH)
			_cancel_op()
		3:
			GameController.load_game(GameController.AUTOSAVE_PATH)
			_cancel_op()
		4:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## Riga sopra la mappa: dice sempre di chi è il turno e cosa si sta facendo.
## Senza, l'unico modo di capirlo è leggere il Log a posteriori.
func _refresh_instructions() -> void:
	if _instr == null:
		return
	var gc := GameController
	var txt := ""
	if gc.rounds != null and gc.rounds.is_game_over():
		txt = "[b]Partita finita.[/b] Vincitore: %s" % String(gc.state.tracks.get("winner", "—"))
	elif _ev_active and _ev_index < _ev_reqs.size():
		var req: Dictionary = _ev_reqs[_ev_index]
		txt = "[color=#%s]Evento (%d/%d): %s[/color]" % [
			RDRTheme.FOCUS.to_html(false), _ev_index + 1, _ev_reqs.size(),
			req.get("prompt", "scegli")]
	elif _op_mode != "":
		var extra := ""
		if gc.MOVEMENT_OPERATIONS.has(_op_mode):
			extra = " · trascina i pezzi da uno spazio all'altro"
		txt = "[color=#%s]%s: %d spazi scelti su %d candidati%s — poi «Esegui».[/color]" % [
			RDRTheme.FOCUS.to_html(false), gc.OPERATION_NAMES.get(_op_mode, _op_mode),
			_op_spaces.size(), _op_candidates.size(), extra]
	elif _sa_mode != "":
		txt = "[color=#%s]%s: scegli gli spazi (%d candidati), poi «Esegui».[/color]" % [
			RDRTheme.FOCUS.to_html(false), gc.SPECIAL_NAMES.get(_sa_mode, _sa_mode),
			_op_candidates.size()]
	elif gc.sequence != null and gc.sequence.pending_faction() != "":
		var fid := gc.sequence.pending_faction()
		txt = "Tocca a %s (%s Disponibile): scegli un'Operazione, l'Evento, oppure Passa." % [
			RDRTheme.faction_chip(gc.game_def.faction(fid).short_name, fid),
			"1ª" if gc.sequence.is_first_slot() else "2ª"]
	elif gc.sequence != null:
		txt = "Carta conclusa: premi «Concludi carta» per passare alla successiva."
	if not gc.pending_free_ops().is_empty():
		txt += "  [color=#%s]★ %d Operazione/i gratuita/e in sospeso.[/color]" % [
			RDRTheme.ACCENT.to_html(false), gc.pending_free_ops().size()]
	_instr.text = txt


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
	_card_now.texture = RDRAssets.card_tex(r.current_card())
	_card_next.texture = RDRAssets.card_tex(r.next_card())
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
	if _op_mode != "" or _sa_mode != "" or _ev_active:
		if not _op_candidates.has(space_id):
			_append_log("%s non è selezionabile per %s." % [
				GameController.game_def.space(space_id).name,
				"l'Evento" if _ev_active else GameController.OPERATION_NAMES.get(_op_mode,
					GameController.SPECIAL_NAMES.get(_sa_mode, "l'azione"))])
		elif _op_spaces.has(space_id) and not _ev_repeat_allowed():
			_op_spaces.erase(space_id)
		elif _ev_active and _op_spaces.size() >= _ev_max_spaces():
			_append_log("Questa scelta ammette al massimo %d spazi." % _ev_max_spaces())
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
	_sa_mode = ""
	_op_moves.clear()
	_op_mode = op_id
	_op_spaces.clear()
	_op_candidates = gc.operation_candidates(op_id, gc.sequence.pending_faction())
	if gc.MOVEMENT_OPERATIONS.has(op_id):
		_append_log("%s: %s. Trascina i pezzi da uno spazio all'altro per dichiarare gli spostamenti, poi «Esegui». (%d spazi disponibili)" % [
			gc.OPERATION_NAMES.get(op_id, op_id),
			"scegli le origini" if op_id == "travel" else "scegli le destinazioni",
			_op_candidates.size()])
	else:
		_append_log("%s: scegli gli spazi (%d disponibili), poi «Esegui»." % [
			gc.OPERATION_NAMES.get(op_id, op_id), _op_candidates.size()])
	_update_moves_overlay()
	_paint_op_highlight()
	_refresh_op_bar()


## §7.0: gioca l'Evento raccogliendo una alla volta le scelte che dichiara —
## gli spazi si indicano sulla mappa, Fazioni e rami con i pulsanti della barra.
func _start_event(shaded: bool) -> void:
	_cancel_op()
	_ev_active = true
	_ev_shaded = shaded
	_ev_choices = {}
	_ev_index = 0
	_ev_step()


## Prepara la scelta corrente; quando sono finite, esegue l'Evento.
func _ev_step() -> void:
	var gc := GameController
	_ev_reqs = gc.events.requirements(gc.state.current_card, _ev_shaded, _ev_choices)
	if _ev_index >= _ev_reqs.size():
		_ev_run()
		return
	var req: Dictionary = _ev_reqs[_ev_index]
	_op_spaces.clear()
	_op_candidates = PackedStringArray()
	if String(req.get("kind", "space")) == "space":
		_op_candidates = PackedStringArray(req.get("candidates", []))
		_append_log("Evento — %s (fino a %d, %d candidati)." % [
			req.get("prompt", "scegli gli spazi"), int(req.get("count", 0)),
			_op_candidates.size()])
		if _op_candidates.is_empty():
			_append_log("Nessuno spazio legale: la scelta resta vuota.")
	else:
		_append_log("Evento — %s." % req.get("prompt", "scegli"))
	_paint_op_highlight()
	_refresh_op_bar()


func _ev_confirm_spaces() -> void:
	var req: Dictionary = _ev_reqs[_ev_index]
	if _op_spaces.size() < int(req.get("min", 0)):
		_append_log("Questa scelta richiede almeno %d spazi." % int(req.get("min", 0)))
		return
	_ev_choices[String(req.get("id", ""))] = Array(_op_spaces)
	_ev_index += 1
	_ev_step()


func _ev_pick(value: String) -> void:
	var req: Dictionary = _ev_reqs[_ev_index]
	_ev_choices[String(req.get("id", ""))] = value
	_ev_index += 1
	_ev_step()


func _ev_run() -> void:
	var gc := GameController
	var res: Dictionary = gc.execute_event(_ev_shaded, _ev_choices)
	if not res.get("ok", false):
		_append_log("[color=#e05a4b]%s[/color]" % res.get("error", "Evento rifiutato"))
		_cancel_op()
		return
	if bool(res.get("manual", false)):
		_append_log("[color=#e0b070]Evento da completare a mano: %s[/color]" % res.get("residual", ""))
	for entry in res.get("free_ops", []):
		_append_log("[color=#7fc4d8]Operazione gratuita in sospeso: %s[/color]" %
			(entry as Dictionary).get("note", (entry as Dictionary).get("operation", "")))
	_cancel_op()


func _ev_max_spaces() -> int:
	if not _ev_active or _ev_index >= _ev_reqs.size():
		return 0
	return int((_ev_reqs[_ev_index] as Dictionary).get("count", 0))


func _ev_repeat_allowed() -> bool:
	if not _ev_active or _ev_index >= _ev_reqs.size():
		return false
	return bool((_ev_reqs[_ev_index] as Dictionary).get("repeat", false))


## Esegue una delle Operazioni gratuite concesse dagli Eventi (§7.0).
func _run_free_op(index: int) -> void:
	var res: Dictionary = GameController.execute_free_op(index)
	if not res.get("ok", false):
		_append_log("[color=#e05a4b]%s[/color]" % res.get("error", "Operazione gratuita rifiutata"))
		return
	_refresh_op_bar()


## Attività Speciale (§6.0): stessa pianificazione a scelta di spazi.
func _start_sa(sa_id: String) -> void:
	var gc := GameController
	_op_mode = ""
	_sa_mode = sa_id
	_op_spaces.clear()
	_op_moves.clear()
	_op_candidates = gc.special_candidates(sa_id, gc.sequence.pending_faction())
	_append_log("%s: scegli fino a %d spazi (%d disponibili)." % [
		gc.SPECIAL_NAMES.get(sa_id, sa_id),
		int(gc.UI_SPECIALS[gc.sequence.pending_faction()][sa_id]),
		_op_candidates.size()])
	_paint_op_highlight()
	_refresh_op_bar()


func _confirm_sa() -> void:
	var gc := GameController
	var res: Dictionary = gc.execute_special(_sa_mode, Array(_op_spaces))
	if not res.get("ok", false):
		_append_log("[color=#e05a4b]%s[/color]" % res.get("error", "attività rifiutata"))
		return
	_cancel_op()


func _cancel_op() -> void:
	_op_mode = ""
	_sa_mode = ""
	_ev_active = false
	_ev_reqs.clear()
	_ev_choices.clear()
	_ev_index = 0
	_op_moves.clear()
	_op_spaces.clear()
	_op_candidates = PackedStringArray()
	_update_moves_overlay()
	_paint_op_highlight()
	_refresh_op_bar()


func _confirm_op() -> void:
	if _op_mode == "" or _op_spaces.is_empty():
		return
	var extra := {"moves": _op_moves}
	if _op_mode == "logistics":
		# Piano minimo: si potenziano le Basi scelte, senza acquisti su Earth.
		extra = {}
	var touched := Array(_op_spaces)
	var res: Dictionary = GameController.execute_operation(_op_mode, Array(_op_spaces), false, extra)
	if not res.get("ok", false):
		_append_log("[color=#e05a4b]%s[/color]" % res.get("error", "azione rifiutata"))
		return
	for sid in touched:
		_flash(String(sid), Color(0.4, 1.0, 0.5))
	_cancel_op()


## Evidenzia in bianco gli spazi scelti; gli altri candidati restano cliccabili.
func _paint_op_highlight() -> void:
	for sid in _views.keys():
		(_views[sid] as RegionView).set_highlight(_op_spaces.has(sid))


## Ricostruisce la barra delle azioni: le Operazioni della Fazione di turno,
## oppure «Esegui / Annulla» mentre si stanno scegliendo gli spazi.
## Costo ed effetti previsti dell'azione in preparazione: si vedono PRIMA di
## eseguire, simulando l'azione su una copia dello stato.
func _refresh_preview() -> void:
	if _preview == null:
		return
	var gc := GameController
	var kind := ""
	var action_id := ""
	if _op_mode != "":
		kind = "operation"
		action_id = _op_mode
	elif _sa_mode != "":
		kind = "special"
		action_id = _sa_mode
	if action_id == "" or _op_spaces.is_empty() or gc.sequence == null \
			or gc.sequence.pending_faction() == "":
		_preview.text = ""
		_preview.tooltip_text = ""
		return
	var res: Dictionary = gc.preview_action(kind, action_id, gc.sequence.pending_faction(),
		Array(_op_spaces), {"moves": _op_moves})
	if not res.get("ok", false):
		# Errore atteso, mostrato prima di premere «Esegui».
		_preview.text = "[color=#%s]⚠ non eseguibile[/color]" % RDRTheme.WARN.to_html(false)
		_preview.tooltip_text = String(res.get("error", ""))
		return
	var cost := int(res.get("cost", 0))
	var effects: Array = res.get("effects", [])
	var cost_txt := "gratis" if cost == 0 else "costo %d / %d Ris." % [
		cost, int(res.get("resources", 0))]
	_preview.text = "[color=#%s]%s[/color]  %s" % [
		RDRTheme.OK.to_html(false), cost_txt,
		" · ".join(PackedStringArray(effects)) if not effects.is_empty() else "nessun effetto"]
	var tip := "Effetti previsti:\n- " + "\n- ".join(PackedStringArray(res.get("log", []))) \
		if not (res.get("log", []) as Array).is_empty() else "Nessun effetto previsto"
	if action_id == "attack":
		tip += "\n\n(L'Attack dipende dai dadi: anteprima indicativa.)"
	_preview.tooltip_text = tip


func _refresh_op_bar() -> void:
	for c in _ops_box.get_children():
		c.queue_free()
	_refresh_instructions()
	_refresh_preview()
	var gc := GameController
	if gc.sequence == null or gc.sequence.pending_faction() == "":
		return
	var fid := gc.sequence.pending_faction()
	if _ev_active:
		_build_event_bar()
		return
	if _op_mode == "" and _sa_mode == "":
		for op_id in gc.UI_OPERATIONS.get(fid, []):
			var b := Button.new()
			b.text = gc.OPERATION_NAMES.get(op_id, op_id)
			b.tooltip_text = String(OPERATION_TIPS.get(op_id, ""))
			b.pressed.connect(_start_op.bind(String(op_id)))
			_ops_box.add_child(b)
		# §7.0: l'Evento, nelle sue due opzioni, quando è consentito.
		if gc.sequence.is_legal(CoinEnums.ActionType.EVENT):
			var card: CardDef = gc.game_def.card(gc.state.current_card)
			if card != null:
				for shaded in [false, true]:
					var opt: Dictionary = gc.events.option(card.number, shaded)
					if opt.is_empty():
						continue
					var e := Button.new()
					e.text = "Ev. ombr." if shaded else "Evento"
					e.tooltip_text = String(opt.get("text", ""))
					e.pressed.connect(_start_event.bind(shaded))
					_ops_box.add_child(e)
		# §7.0: Operazioni gratuite concesse da un Evento e non ancora eseguite.
		var queue: Array = gc.pending_free_ops()
		for i in range(queue.size()):
			var entry: Dictionary = queue[i]
			var label := String(entry.get("operation", ""))
			if label == "":
				label = String(entry.get("special", ""))
			var fb := Button.new()
			fb.text = "★ %s gratis (%s)" % [
				gc.OPERATION_NAMES.get(label, gc.SPECIAL_NAMES.get(label, label)),
				gc.game_def.faction(String(entry.get("faction", ""))).short_name]
			fb.tooltip_text = String(entry.get("note", ""))
			fb.pressed.connect(_run_free_op.bind(i))
			_ops_box.add_child(fb)
		for sa_id in gc.UI_SPECIALS.get(fid, {}).keys():
			var sb := Button.new()
			sb.text = "· %s" % gc.SPECIAL_NAMES.get(sa_id, sa_id)
			sb.tooltip_text = "Attività Speciale (§6.0)"
			sb.pressed.connect(_start_sa.bind(String(sa_id)))
			_ops_box.add_child(sb)
		_refresh_move_box()
		return
	if _sa_mode != "":
		var run_sa := Button.new()
		run_sa.text = "Esegui %s (%d)" % [gc.SPECIAL_NAMES.get(_sa_mode, _sa_mode), _op_spaces.size()]
		run_sa.pressed.connect(_confirm_sa)
		_ops_box.add_child(run_sa)
		var cancel_sa := Button.new()
		cancel_sa.text = "Annulla"
		cancel_sa.pressed.connect(_cancel_op)
		_ops_box.add_child(cancel_sa)
		_refresh_move_box()
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
	_refresh_move_box()


## Barra della scelta in corso di un Evento: gli spazi si prendono dalla mappa,
## Fazioni e rami hanno un pulsante ciascuno.
func _build_event_bar() -> void:
	if _ev_index >= _ev_reqs.size():
		return
	var req: Dictionary = _ev_reqs[_ev_index]
	var label := Label.new()
	label.text = "Evento (%d/%d): %s" % [
		_ev_index + 1, _ev_reqs.size(), req.get("prompt", "scegli")]
	_ops_box.add_child(label)
	if String(req.get("kind", "space")) == "space":
		var next := Button.new()
		next.text = "Conferma (%d/%d)" % [_op_spaces.size(), int(req.get("count", 0))]
		next.pressed.connect(_ev_confirm_spaces)
		_ops_box.add_child(next)
		if not _op_spaces.is_empty():
			var clear := Button.new()
			clear.text = "Svuota"
			clear.pressed.connect(func():
				_op_spaces.clear()
				_paint_op_highlight()
				_refresh_op_bar())
			_ops_box.add_child(clear)
	else:
		for value in req.get("candidates", []):
			var b := Button.new()
			b.text = _choice_label(String(value))
			b.pressed.connect(_ev_pick.bind(String(value)))
			_ops_box.add_child(b)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.pressed.connect(_cancel_op)
	_ops_box.add_child(cancel)


func _choice_label(value: String) -> String:
	var f: FactionDef = GameController.game_def.faction(value)
	if f != null:
		return f.short_name
	var s: SpaceDef = GameController.game_def.space(value)
	if s != null:
		return s.name
	return value.capitalize()


## §5.3/§5.4/§5.7/§5.8: trascinare un pezzo da uno spazio all'altro dichiara uno
## spostamento dell'Operazione di movimento in corso. È il modo naturale di
## muovere sulla mappa; il modulo qui sotto resta per le quantità grandi.
func _on_piece_dropped(from_id: String, to_id: String, type_id: String) -> void:
	var gc := GameController
	if gc.sequence == null or gc.sequence.pending_faction() == "":
		return
	var fid := gc.sequence.pending_faction()
	if not gc.MOVEMENT_OPERATIONS.has(_op_mode):
		_append_log("Per spostare i pezzi scegli prima un'Operazione di movimento (%s)." %
			", ".join(PackedStringArray(gc.MOVEMENT_OPERATIONS).slice(0, 4)))
		return
	if not gc.movable_types(_op_mode, fid).has(type_id):
		_append_log("[color=#e05a4b]%s non muove unità di tipo «%s».[/color]" % [
			gc.OPERATION_NAMES.get(_op_mode, _op_mode), type_id])
		return
	if not gc.legal_origins(_op_mode, fid, to_id, type_id).has(from_id):
		_append_log("[color=#e05a4b]%s non è un'origine legale per %s con %s.[/color]" % [
			gc.game_def.space(from_id).name, gc.game_def.space(to_id).name,
			gc.OPERATION_NAMES.get(_op_mode, _op_mode)])
		return
	# §5.8: Travel sceglie le ORIGINI; le altre Operazioni le destinazioni.
	var key := from_id if _op_mode == "travel" else to_id
	if not _op_spaces.has(key):
		if not _op_candidates.has(key):
			_append_log("[color=#e05a4b]%s non è selezionabile per %s.[/color]" % [
				gc.game_def.space(key).name, gc.OPERATION_NAMES.get(_op_mode, _op_mode)])
			return
		_op_spaces.append(key)
	# Trascinare più volte lo stesso tragitto ingrossa la stessa freccia.
	for m in _op_moves:
		if String(m["from"]) == from_id and String(m["to"]) == to_id \
				and String(m["type"]) == type_id:
			m["count"] = int(m["count"]) + 1
			_after_moves_changed()
			return
	_op_moves.append({"from": from_id, "to": to_id, "type": type_id, "count": 1})
	_flash(from_id, Color(0.35, 0.6, 1.0))
	_flash(to_id, Color(0.4, 1.0, 0.5))
	_after_moves_changed()


## Accende per un attimo uno spazio: serve a vedere dove è finita l'azione.
func _flash(sid: String, color: Color) -> void:
	if _views.has(sid):
		(_views[sid] as RegionView).flash(color)


func _after_moves_changed() -> void:
	_update_moves_overlay()
	_paint_op_highlight()
	_refresh_op_bar()


## Ridisegna le frecce degli spostamenti ancora da eseguire.
func _update_moves_overlay() -> void:
	if _moves == null:
		return
	var segs: Array = []
	for m in _op_moves:
		var f := String(m["from"])
		var t := String(m["to"])
		if _views.has(f) and _views.has(t):
			segs.append({
				"from": (_views[f] as RegionView).center_point(),
				"to": (_views[t] as RegionView).center_point(),
				"count": int(m["count"]),
			})
	_moves.set_segments(segs)


## Pianificatore di movimento (§5.3/§5.4/§5.7/§5.8): per ogni spazio scelto come
## destinazione si dichiara da dove arrivano le unità, di che tipo e quante.
func _refresh_move_box() -> void:
	for c in _move_box.get_children():
		c.queue_free()
	var gc := GameController
	if not gc.MOVEMENT_OPERATIONS.has(_op_mode) or _op_spaces.is_empty():
		return
	var fid := gc.sequence.pending_faction()
	var types := gc.movable_types(_op_mode, fid)
	if types.is_empty():
		return

	var title := Label.new()
	title.text = "Spostamenti (%d dichiarati) — trascina i pezzi sulla mappa" % _op_moves.size()
	title.add_theme_font_size_override("font_size", 12)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_box.add_child(title)
	for i in range(_op_moves.size()):
		var m: Dictionary = _op_moves[i]
		var row_m := HBoxContainer.new()
		var l := Label.new()
		l.text = "%d× %s: %s → %s" % [int(m["count"]), String(m["type"]),
			gc.game_def.space(String(m["from"])).name, gc.game_def.space(String(m["to"])).name]
		l.add_theme_font_size_override("font_size", 11)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_m.add_child(l)
		var del := Button.new()
		del.text = "×"
		del.tooltip_text = "Togli questo spostamento"
		del.pressed.connect(func():
			_op_moves.remove_at(i)
			_after_moves_changed())
		row_m.add_child(del)
		_move_box.add_child(row_m)

	# Form: destinazione (fra quelle scelte) · tipo · origine · quantità.
	var dest_opt := OptionButton.new()
	for sid in _op_spaces:
		dest_opt.add_item(gc.game_def.space(sid).name)
		dest_opt.set_item_metadata(dest_opt.item_count - 1, sid)
	var type_opt := OptionButton.new()
	for t in types:
		type_opt.add_item(String(t))
		type_opt.set_item_metadata(type_opt.item_count - 1, String(t))
	var from_opt := OptionButton.new()
	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 12
	count_spin.value = 1

	var refill := func():
		from_opt.clear()
		if dest_opt.selected < 0 or type_opt.selected < 0:
			return
		var dest := String(dest_opt.get_item_metadata(dest_opt.selected))
		var t := String(type_opt.get_item_metadata(type_opt.selected))
		for o in gc.legal_origins(_op_mode, fid, dest, t):
			from_opt.add_item("%s (%d)" % [gc.game_def.space(String(o)).name,
				gc.rdr().count_in(gc.state, String(o), t)])
			from_opt.set_item_metadata(from_opt.item_count - 1, String(o))
	dest_opt.item_selected.connect(func(_i): refill.call())
	type_opt.item_selected.connect(func(_i): refill.call())
	refill.call()

	_move_box.add_child(dest_opt)
	_move_box.add_child(type_opt)
	_move_box.add_child(from_opt)
	var row := HBoxContainer.new()
	row.add_child(count_spin)
	var add := Button.new()
	add.text = "Aggiungi spostamento"
	add.pressed.connect(func():
		if from_opt.selected < 0 or dest_opt.selected < 0:
			_append_log("Nessuna origine valida per questa combinazione.")
			return
		_op_moves.append({
			"from": String(from_opt.get_item_metadata(from_opt.selected)),
			"to": String(dest_opt.get_item_metadata(dest_opt.selected)),
			"type": String(type_opt.get_item_metadata(type_opt.selected)),
			"count": int(count_spin.value),
		})
		_refresh_op_bar())
	row.add_child(add)
	_move_box.add_child(row)


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
