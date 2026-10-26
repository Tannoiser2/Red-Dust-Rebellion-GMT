class_name TopBar
extends PanelContainer

## Barra superiore comune ai giochi COIN: emblema e titolo, una tessera per Fazione
## (ordine sulla carta, ruolo Giocatore/Bot, stato, Risorse, Vittoria), i contatori
## della partita e i comandi (Annulla, Auto-Bot, Gioca Bot, Menu).
##
## Non conosce la logica di gioco: legge lo stato dal controller in `refresh()` e
## notifica le richieste con i segnali; la scena decide cosa farne.

signal undo_requested
signal auto_bot_toggled(on: bool)
signal bot_turn_requested
signal menu_id_pressed(id: int)

const HEIGHT := 72.0
const FACTIONS := ["marsgov", "corporations", "red_dust", "reclaimer"]
## Nome della metrica di vittoria di ogni Fazione (§2.0), per il suggerimento.
const VIC_LABEL := {
	"marsgov": "Supporto + EG Confidence", "corporations": "Profits",
	"red_dust": "Opposizione + Basi", "reclaimer": "Controllo CR + Basi (contro le Basi nemiche)",
}

## Voci del menu di partita (gli id arrivano alla scena con `menu_id_pressed`).
## I primi sette coincidono con quelli del vecchio menu «Partita…».
enum MenuId { NEW_GAME = 0, SAVE = 1, LOAD = 2, AUTOSAVE = 3, MAIN_MENU = 4,
	COPY_LOG = 5, SAVE_LOG = 6, BOTS_UNTIL_ME = 7 }

var _brand_text: Control
var _tiles: Dictionary = {}       ## fid -> {panel, order, name, sub, res, bar, vval}
var _cards_lbl: Label
var _fp_lbl: Label
var _eg_lbl: Label
var _storm_lbl: Label
var _status_box: Control
var _btn_undo: Button
var _btn_auto: Button
var _btn_bot: Button
var _menu: MenuButton
var _cmds: Array[Button] = []


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	var sb := RDRTheme.flat(RDRTheme.BAR)
	sb.border_width_bottom = 2
	sb.border_color = RDRTheme.MARS
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_build_brand())

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	var tiles_m := MarginContainer.new()
	for side in ["left", "right"]:
		tiles_m.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		tiles_m.add_theme_constant_override("margin_" + side, 7)
	tiles_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tiles_m.add_child(tiles)
	row.add_child(tiles_m)
	for fid in FACTIONS:
		tiles.add_child(_build_tile(fid))

	row.add_child(_vline())
	_status_box = _build_status()
	row.add_child(_status_box)

	row.add_child(_vline())
	_btn_undo = _cmd_button("Annulla", "Disfa l'ultima azione (Ctrl+Z)")
	_btn_undo.pressed.connect(func(): undo_requested.emit())
	row.add_child(_btn_undo)
	row.add_child(_vline())
	_btn_auto = _cmd_button("Auto-Bot", "Se acceso, le Fazioni Non-Player giocano da sole quando tocca a loro")
	_btn_auto.toggle_mode = true
	_btn_auto.toggled.connect(func(on): auto_bot_toggled.emit(on))
	row.add_child(_btn_auto)
	row.add_child(_vline())
	_btn_bot = _cmd_button("Gioca Bot", "Fai giocare il turno alla Fazione Non-Player di turno (carta Curiosity, §8.0)")
	_btn_bot.pressed.connect(func(): bot_turn_requested.emit())
	row.add_child(_btn_bot)
	row.add_child(_vline())
	_menu = TipMenuButton.new()
	_menu.text = "Menu"
	_menu.tooltip_text = "Salvataggi, Log, Bot, nuova partita"
	_style_cmd(_menu)
	var p := _menu.get_popup()
	p.add_item("Salva la partita", MenuId.SAVE)
	p.add_item("Riprendi l'ultima salvata", MenuId.LOAD)
	p.add_item("Riprendi il salvataggio automatico", MenuId.AUTOSAVE)
	p.add_separator("Log")
	p.add_item("Copia il Log negli appunti", MenuId.COPY_LOG)
	p.add_item("Salva il Log sulla Scrivania", MenuId.SAVE_LOG)
	p.add_separator("Bot")
	p.add_item("Gioca i Bot fino al mio turno", MenuId.BOTS_UNTIL_ME)
	p.add_separator()
	p.add_item("Nuova partita…", MenuId.NEW_GAME)
	p.add_item("Torna al menu iniziale…", MenuId.MAIN_MENU)
	p.id_pressed.connect(func(id): menu_id_pressed.emit(id))
	row.add_child(_menu)


func _build_brand() -> Control:
	var pc := PanelContainer.new()
	var bsb := RDRTheme.flat(Color("120c0a"), 0)
	bsb.border_width_right = 1
	bsb.border_color = RDRTheme.MARS_DARK
	pc.add_theme_stylebox_override("panel", bsb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 10)
	m.add_child(h)
	pc.add_child(m)
	var em := RDRTheme.Emblem.new()
	em.custom_minimum_size = Vector2(46, 52)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	var t := RDRTheme.label(RDRTheme.TITLE.to_upper(), Color.WHITE, 15, RDRTheme.display())
	v.add_child(t)
	v.add_child(RDRTheme.label(RDRTheme.SUBTITLE, RDRTheme.MARS_HI, 12, RDRTheme.mono()))
	h.add_child(v)
	_brand_text = v
	return pc


func _build_tile(fid: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(120, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	# Cilindro della Fazione con il numero d'ordine sulla carta.
	var tok_box := Control.new()
	tok_box.custom_minimum_size = Vector2(28, 40)
	tok_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tok := TextureRect.new()
	tok.texture = RDRAssets.pawn_tex(fid)
	tok.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tok.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tok.position = Vector2(0, 6)
	tok.size = Vector2(28, 32)
	tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tok_box.add_child(tok)
	var order := RDRTheme.label("", RDRTheme.BG, 11, RDRTheme.ui_heavy())
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ob := RDRTheme.box(RDRTheme.CYAN, RDRTheme.CYAN, 0, 8)
	ob.content_margin_left = 0
	ob.content_margin_right = 0
	ob.content_margin_top = 0
	ob.content_margin_bottom = 0
	order.add_theme_stylebox_override("normal", ob)
	order.position = Vector2(16, -3)
	order.size = Vector2(16, 16)
	tok_box.add_child(order)
	h.add_child(tok_box)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := RDRTheme.label(_short_name(fid), Color.WHITE, 17, RDRTheme.ui_heavy())
	name_l.clip_text = true
	v.add_child(name_l)
	var sub := RDRTheme.label("", RDRTheme.TEXT_DIM, 12)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	# Vittoria: barra con la tacca della soglia e valore/soglia accanto.
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 5)
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := MeterBar.new()
	bar.bar_height = 5
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(bar)
	var vval := RDRTheme.label("", RDRTheme.TEXT_DIM, 12, RDRTheme.mono())
	vrow.add_child(vval)
	v.add_child(vrow)
	h.add_child(v)
	var res := RDRTheme.label("", Color.WHITE, 26, RDRTheme.ui_heavy())
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(res)
	_tiles[fid] = {"panel": pc, "order": order, "sub": sub, "res": res, "name": name_l,
		"bar": bar, "vval": vval}
	return pc


## Contatori della partita: carte, Flashpoint, EarthGov Confidence, Dust Storm.
func _build_status() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 0)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_child(g)
	_fp_lbl = _stat(g, "FLASHPOINT", "Traccia Flashpoint (§4.0): a 5 scatta il Flashpoint Round")
	_cards_lbl = _stat(g, "CARTE", "Carte Evento rimaste nel mazzo")
	_eg_lbl = _stat(g, "EG", "EarthGov Confidence (§1.2): valore, lato del marcatore e Controller")
	_storm_lbl = _stat(g, "STORM", "Dust Storm Round giocati: la partita finisce al terzo (§4.3)")
	return m


func _stat(g: GridContainer, title: String, tip: String) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var t := RDRTheme.label(title, RDRTheme.TEXT_DIM, 10, RDRTheme.display_light())
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.tooltip_text = tip
	h.add_child(t)
	var v := RDRTheme.label("—", Color.WHITE, 15, RDRTheme.ui_heavy())
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.tooltip_text = tip
	h.add_child(v)
	g.add_child(h)
	return v


func _vline() -> Control:
	var c := ColorRect.new()
	c.color = RDRTheme.BAR_LINE
	c.custom_minimum_size = Vector2(1, 0)
	return c


func _cmd_button(text: String, tip: String) -> Button:
	var b := TipButton.new()
	b.text = text
	b.tooltip_text = tip
	_style_cmd(b)
	return b


## Comandi della barra: piatti, alti quanto la barra, ciano al passaggio.
func _style_cmd(b: Button) -> void:
	RDRTheme.style_button(b)
	b.custom_minimum_size = Vector2(74, 0)
	var n := RDRTheme.flat(Color(0, 0, 0, 0), 8)
	var hv := RDRTheme.flat(Color("121a22"), 8)
	var on := RDRTheme.flat(Color("10262b"), 8)
	on.border_width_bottom = 3
	on.border_color = RDRTheme.CYAN
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_color_override("font_color", RDRTheme.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", RDRTheme.CYAN)
	b.add_theme_color_override("font_hover_pressed_color", RDRTheme.CYAN)
	b.add_theme_color_override("font_disabled_color", RDRTheme.BTN_DISABLED_TEXT)
	b.add_theme_font_override("font", RDRTheme.ui_bold())
	b.add_theme_font_size_override("font_size", 16)
	_cmds.append(b)


## Schermi stretti (1180 px): il titolo lascia il posto all'emblema e i comandi si
## stringono, così le tessere delle Fazioni restano leggibili.
func set_compact(on: bool) -> void:
	_brand_text.visible = not on
	for b in _cmds:
		b.custom_minimum_size = Vector2(60 if on else 74, 0)
		b.add_theme_font_size_override("font_size", 14 if on else 16)


func set_auto_bot(on: bool) -> void:
	_btn_auto.set_pressed_no_signal(on)
	_btn_auto.text = "Auto-Bot ON" if on else "Auto-Bot"


func set_bot_enabled(on: bool) -> void:
	_btn_bot.disabled = not on


## Abilita/disabilita «Annulla» e ne aggiorna il suggerimento: dice COSA si disfa.
func set_undo(can: bool, label: String) -> void:
	_btn_undo.disabled = not can
	_btn_undo.tooltip_text = "Annulla: %s (Ctrl+Z)" % label if can else "Niente da annullare"


func _short_name(fid: String) -> String:
	var gd: GameDef = GameController.game_def
	var f: FactionDef = gd.faction(fid) if gd != null else null
	return f.short_name if f != null else fid


## Aggiorna tessere e contatori dallo stato della partita.
func refresh() -> void:
	var gc := GameController
	var s: GameState = gc.state
	if s == null:
		return
	var m: RDRModule = gc.rdr()
	var card: CardDef = gc.game_def.card(s.current_card) if s.current_card > 0 else null
	var pending := gc.sequence.pending_faction() if gc.sequence != null else ""
	var support: Array = gc.support_pending()
	if not support.is_empty():
		pending = String(support[0])
	var actors: PackedStringArray = gc.sequence.actors() if gc.sequence != null else PackedStringArray()
	var passers: PackedStringArray = gc.sequence.passers() if gc.sequence != null else PackedStringArray()
	var vs: Dictionary = m.victory_status(s)

	# Contatori.
	_cards_lbl.text = str(s.draw_deck.size())
	_fp_lbl.text = "%d/5" % int(s.tracks.get("flashpoint", 0))
	_fp_lbl.add_theme_color_override("font_color",
		RDRTheme.WARN if int(s.tracks.get("flashpoint", 0)) >= 3 else Color.WHITE)
	var ctrl := m.eg_controller(s)
	var ctrl_name := "—"
	if ctrl != "":
		ctrl_name = gc.game_def.faction(ctrl).short_name
	_eg_lbl.text = "%d %s %s" % [m.eg_confidence_value(s),
		"EG+" if int(s.tracks.get("eg_side", -1)) > 0 else "EG−", ctrl_name]
	var haboob: bool = gc.rounds != null and gc.rounds.haboob_active()
	_storm_lbl.text = "%d/3%s" % [int(s.tracks.get("dust_storm_rounds", 0)), "  HABOOB" if haboob else ""]
	_storm_lbl.add_theme_color_override("font_color", RDRTheme.WARN if haboob else Color.WHITE)

	for fid in FACTIONS:
		var t: Dictionary = _tiles[fid]
		var col := RDRTheme.faction(fid)
		var active: bool = fid == pending
		var idx := card.faction_order.find(fid) if card != null else -1
		(t["order"] as Label).visible = idx >= 0
		(t["order"] as Label).text = str(idx + 1)
		var is_np: bool = gc.np != null and gc.np.is_np(fid)
		var status := "disponibile"
		if not support.is_empty() and active:
			status = "Support Phase"
		elif active:
			status = "di turno"
		elif passers.has(fid):
			status = "ha passato"
		elif actors.has(fid):
			status = "ha agito"
		elif s.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) != CoinEnums.Eligibility.ELIGIBLE:
			status = "non disponibile"
		# «Umano» e non «Giocatore»: nella tessera lo spazio è poco e «disponibile»
		# deve restare leggibile per intero.
		(t["sub"] as Label).text = "%s · %s" % ["Bot" if is_np else "Umano", status]
		var res_txt := "—"
		var res_tip := ""
		match fid:
			"marsgov", "red_dust":
				if is_np:
					res_txt = str(m.supply_total(s) if fid == "marsgov" else m.agitate_total(s))
					res_tip = "Supply Total (Non-Player, §8.5.4)" if fid == "marsgov" \
						else "Agitate Total (Non-Player, §8.5.4)"
				else:
					res_txt = str(s.get_resources(fid))
					res_tip = "Risorse"
			"corporations":
				res_txt = str(int(s.tracks.get("profits", 0)))
				res_tip = "Profits: le Corporations pagano tutto in Profits (§1.4)"
			"reclaimer":
				if is_np:
					res_txt = str(m.asset_total(s))
					res_tip = "Asset Total (Non-Player, §8.2)"
				elif gc.cards != null:
					res_txt = str(gc.cards.hand().size())
					res_tip = "Asset card in mano: pagano le Operazioni (§1.5)"
		(t["res"] as Label).text = res_txt
		(t["res"] as Label).tooltip_text = res_tip
		var d: Dictionary = vs.get(fid, {})
		var val := int(d.get("value", 0))
		var thr := int(d.get("threshold", 0))
		var bar: MeterBar = t["bar"]
		bar.max_value = maxf(thr * 1.45, val + 2.0)
		bar.set_values(val, thr)
		bar.color = Color.WHITE if active else RDRTheme.faction_text(fid)
		bar.track_color = col.darkened(0.45) if active else Color("1d2833")
		bar.tick_color = RDRTheme.CYAN if not active else Color.WHITE
		(t["vval"] as Label).text = "%d/%d" % [val, thr]
		(t["vval"] as Label).add_theme_color_override("font_color", Color.WHITE if active else RDRTheme.TEXT_DIM)
		(t["panel"] as Control).tooltip_text = "%s · %s\nVittoria — %s: %d (soglia %d, margine %+d)" % [
			gc.game_def.faction(fid).name, "Non-Player" if is_np else "Giocatore",
			VIC_LABEL.get(fid, ""), val, thr, int(d.get("margin", 0))]
		var sb := RDRTheme.box(col if active else Color("10171e"), col, 1)
		sb.border_width_left = 4
		if active:
			sb.border_color = Color.WHITE
			sb.border_width_left = 4
		else:
			sb.border_width_top = 0
			sb.border_width_right = 0
			sb.border_width_bottom = 0
		sb.content_margin_left = 5
		sb.content_margin_right = 7
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		(t["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var dim: bool = not active and status in ["non disponibile", "ha agito", "ha passato"]
		(t["panel"] as PanelContainer).modulate = Color(1, 1, 1, 0.55 if dim else 1.0)
		(t["sub"] as Label).add_theme_color_override("font_color",
			Color(1, 1, 1, 0.85) if active else RDRTheme.TEXT_DIM)
