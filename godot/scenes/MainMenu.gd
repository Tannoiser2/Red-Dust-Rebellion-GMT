extends Control

## Schermata iniziale: si sceglie se cominciare una partita nuova (eventualmente
## con un seme, per poterla rigiocare identica) o riprendere l'ultima. È la scena
## principale del progetto: la partita vera si apre da qui.

const GAME_SCENE := "res://scenes/Main.tscn"

var _seed_edit: LineEdit
var _status: Label
## §8.0: chi è gestito dal sistema Non-Player. In solitario si tiene una Fazione
## e si lasciano le altre al bot.
var _roles := {"marsgov": "player", "corporations": "bot",
	"red_dust": "bot", "reclaimer": "bot"}
var _role_btns := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = RDRTheme.make_theme()
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = RDRTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(420, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "RED DUST REBELLION"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("c0392b"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Edizione digitale non ufficiale · Serie COIN vol. XII (GMT)\nMars, 2250"
	sub.add_theme_color_override("font_color", RDRTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(HSeparator.new())

	col.add_child(_btn("Nuova partita", _on_new))

	# Il seme rende la partita ripetibile: stesso mazzo, stessi tiri.
	var seed_row := HBoxContainer.new()
	var seed_lbl := Label.new()
	seed_lbl.text = "Seme (facoltativo)"
	seed_lbl.add_theme_color_override("font_color", RDRTheme.TEXT_DIM)
	seed_row.add_child(seed_lbl)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "0 = casuale"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	col.add_child(seed_row)

	col.add_child(HSeparator.new())

	var lbl := Label.new()
	lbl.text = "Chi gioca"
	lbl.add_theme_color_override("font_color", RDRTheme.ACCENT)
	col.add_child(lbl)
	for fid in ["marsgov", "corporations", "red_dust", "reclaimer"]:
		var row := HBoxContainer.new()
		var name := Label.new()
		name.text = _faction_name(String(fid))
		name.custom_minimum_size = Vector2(190, 0)
		name.add_theme_color_override("font_color", RDRAssets.text_color(String(fid)))
		row.add_child(name)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_toggle_role.bind(String(fid)))
		_role_btns[fid] = b
		row.add_child(b)
		col.add_child(row)
	_refresh_roles()

	col.add_child(HSeparator.new())

	var b_resume := _btn("Riprendi la partita salvata", _on_resume_saved)
	b_resume.disabled = not GameController.has_save(GameController.SAVE_PATH)
	col.add_child(b_resume)

	var b_auto := _btn("Riprendi l'ultimo salvataggio automatico", _on_resume_auto)
	b_auto.disabled = not GameController.has_save(GameController.AUTOSAVE_PATH)
	col.add_child(b_auto)

	col.add_child(HSeparator.new())
	col.add_child(_btn("Esci", func(): get_tree().quit()))

	_status = Label.new()
	_status.add_theme_color_override("font_color", RDRTheme.ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	var legal := Label.new()
	legal.text = "Red Dust Rebellion © 2024 GMT Games. Progetto amatoriale."
	legal.add_theme_font_size_override("font_size", 10)
	legal.add_theme_color_override("font_color", RDRTheme.TEXT_DIM)
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(legal)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
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
		var is_bot: bool = _roles[fid] == "bot"
		(_role_btns[fid] as Button).text = "Non-Player" if is_bot else "Giocatore"
		if is_bot:
			bots += 1
	if _status != null:
		_status.text = "" if bots < 4 else "Con quattro bot non resta niente da giocare."


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
