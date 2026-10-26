extends Control

## Schermata iniziale: si sceglie chi gioca e chi è gestito dal sistema
## Non-Player, si può fissare un seme (per rigiocare la stessa partita) oppure
## riprendere l'ultima. È la scena principale del progetto: la partita vera si
## apre da qui.

const GAME_SCENE := "res://scenes/Main.tscn"
const FACTIONS := ["marsgov", "corporations", "red_dust", "reclaimer"]

var _seed_edit: LineEdit
var _status: Label
var _play: Button
## §8.0: chi è gestito dal sistema Non-Player. In solitario si tiene una Fazione
## e si lasciano le altre al bot.
var _roles := {"marsgov": "player", "corporations": "bot",
	"red_dust": "bot", "reclaimer": "bot"}
var _role_btns := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = RDRTheme.dark_theme()
	get_window().theme = RDRTheme.dark_theme()
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = RDRTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# La tavola di Mars come sfondo, molto attenuata: dà identità senza disturbare.
	var art := TextureRect.new()
	art.texture = RDRAssets.tex("map.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.55, 0.6, 0.7, 0.22)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Il menu è un pannello della plancia di controllo: vetro scuro, testata arancio.
	var panel := PanelContainer.new()
	panel.theme = RDRTheme.panel_theme()
	var pstyle := RDRTheme.glass_box(30.0)
	pstyle.content_margin_top = 0.0
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(400, 0)
	panel.add_child(vb)

	# --- Testata: emblema e titolo ---
	var head := PanelContainer.new()
	var hsb := RDRTheme.flat(Color("120c0a"), 0)
	hsb.content_margin_top = 16
	hsb.content_margin_bottom = 14
	hsb.expand_margin_left = 30
	hsb.expand_margin_right = 30
	hsb.corner_radius_top_left = 4
	hsb.corner_radius_top_right = 4
	hsb.border_width_bottom = 2
	hsb.border_color = RDRTheme.MARS
	head.add_theme_stylebox_override("panel", hsb)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	head.add_child(hv)
	var em := RDRTheme.Emblem.new()
	em.custom_minimum_size = Vector2(0, 74)
	hv.add_child(em)
	var title := RDRTheme.label(RDRTheme.TITLE.to_upper(), Color.WHITE, 27, RDRTheme.display())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(title)
	var sub := RDRTheme.label(RDRTheme.SUBTITLE, RDRTheme.MARS_HI, 14, RDRTheme.mono())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(sub)
	var sub2 := RDRTheme.label("Edizione digitale non ufficiale · Serie COIN, Vol. XII", RDRTheme.TEXT_DIM, 13)
	sub2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(sub2)
	vb.add_child(head)

	# --- Ruoli ---
	vb.add_child(_section("Chi gioca cosa"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for fid in FACTIONS:
		var rb := _mk_btn("", _toggle_role.bind(String(fid)))
		rb.custom_minimum_size = Vector2(196, 34)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.tooltip_text = "Clicca per alternare fra Giocatore e Non-Player (sistema Curiosity, §8.0)."
		_role_btns[fid] = rb
		grid.add_child(rb)
	vb.add_child(grid)

	# --- Seme: rende la partita ripetibile (stesso mazzo, stessi tiri) ---
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var seed_lbl := RDRTheme.label("Seme (facoltativo)", RDRTheme.TEXT_DIM, 15)
	seed_row.add_child(seed_lbl)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "0 = casuale"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.tooltip_text = "Lo stesso seme ridà lo stesso mazzo e gli stessi tiri di dado."
	seed_row.add_child(_seed_edit)
	vb.add_child(seed_row)

	# --- Avvio ---
	_play = _mk_btn("Nuova partita", _on_new)
	RDRTheme.primary_button(_play, 19)
	_play.custom_minimum_size = Vector2(0, 52)
	vb.add_child(_play)

	var b_resume := _mk_btn("Riprendi la partita salvata", _on_resume_saved)
	b_resume.disabled = not GameController.has_save(GameController.SAVE_PATH)
	b_resume.custom_minimum_size = Vector2(0, 34)
	vb.add_child(b_resume)

	var b_auto := _mk_btn("Riprendi l'ultimo salvataggio automatico", _on_resume_auto)
	b_auto.disabled = not GameController.has_save(GameController.AUTOSAVE_PATH)
	b_auto.custom_minimum_size = Vector2(0, 34)
	vb.add_child(b_auto)

	if OS.get_name() != "Web":
		var ex := _mk_btn("Esci", func(): get_tree().quit())
		ex.custom_minimum_size = Vector2(0, 34)
		vb.add_child(ex)

	_status = RDRTheme.label("", RDRTheme.TEXT_DIM, 13, RDRTheme.mono())
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 20)
	vb.add_child(_status)

	var legal := RDRTheme.label("Red Dust Rebellion © 2024 GMT Games. Progetto amatoriale.", RDRTheme.TEXT_FAINT, 12)
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(legal)
	_refresh_roles()


func _section(text: String) -> Label:
	var l := RDRTheme.section_title(text, RDRTheme.TEXT_DIM, 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := TipButton.new()
	b.text = text
	b.pressed.connect(cb)
	RDRTheme.style_button(b)
	return b


func _faction_name(fid: String) -> String:
	match fid:
		"marsgov": return "MarsGov"
		"corporations": return "Corporations"
		"red_dust": return "Red Dust"
	return "Reclaimer"


func _toggle_role(fid: String) -> void:
	_roles[fid] = "bot" if _roles[fid] == "player" else "player"
	_refresh_roles()


func _refresh_roles() -> void:
	var bots := 0
	for fid in _role_btns.keys():
		var b: Button = _role_btns[fid]
		var is_bot: bool = _roles[fid] == "bot"
		b.text = "%s: %s" % [_faction_name(String(fid)), "Non-Player" if is_bot else "Giocatore"]
		if is_bot:
			bots += 1
			RDRTheme.style_button(b)
			b.add_theme_color_override("font_color", RDRTheme.TEXT_DIM)
		else:
			var col := RDRTheme.faction(String(fid))
			RDRTheme.accent_button(b, col.darkened(0.35), col.lightened(0.2))
	if _status != null:
		_status.text = "Con quattro bot non resta niente da giocare." if bots >= 4 \
			else "Clicca una Fazione per affidarla al bot o riprenderla."
		_status.add_theme_color_override("font_color", RDRTheme.WARN if bots >= 4 else RDRTheme.TEXT_DIM)


func _on_new() -> void:
	var seed_value := int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 0
	var np: Array = []
	for fid in _roles.keys():
		if _roles[fid] == "bot":
			np.append(String(fid))
	GameController.new_game("standard", seed_value, np)
	_open_game()


func _on_resume_saved() -> void:
	_resume(GameController.SAVE_PATH)


func _on_resume_auto() -> void:
	_resume(GameController.AUTOSAVE_PATH)


func _resume(path: String) -> void:
	if not GameController.load_game(path):
		_status.text = "Salvataggio non leggibile."
		return
	_open_game()


func _open_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
