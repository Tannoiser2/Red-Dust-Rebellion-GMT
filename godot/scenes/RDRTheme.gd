class_name RDRTheme
extends RefCounted

## Aspetto dell'interfaccia: tema «plancia di controllo di una colonia marziana, 2250».
##
## Unico posto dove vivono colori, caratteri, riquadri ed emblema. Lo schema della
## schermata (barra in alto, mappa, pannello azione a destra, registro in basso) è
## comune a tutti i giochi COIN; per un altro titolo della serie basta cambiare
## QUESTO file: palette, caratteri, titolo ed emblema.
##
## Due superfici, entrambe scure:
##  - il fondo (barra superiore, mappa, registro): spazio profondo;
##  - il vetro (pannello azione, finestre, riquadri informativi): pannello HUD
##    blu-ardesia con bordo ciano sottile e testo chiaro. È il ruolo che in Cuba
##    Libre aveva la «carta»: qui INK è il testo chiaro e PANEL la superficie.

# --- Titolo ed emblema ----------------------------------------------------------
const TITLE := "Red Dust Rebellion"
const SUBTITLE := "Ribellione marziana · 2250"

# --- Palette -----------------------------------------------------------------
const BG := Color("0b0f14")            ## spazio profondo: sfondo della scena
const BAR := Color("070a0e")           ## barra superiore
const BAR_LINE := Color("1d2833")      ## divisori nella barra
const PANEL := Color("141c24")         ## vetro scuro dei pannelli
const PANEL_DARK := Color("0f161d")    ## riquadri interni (istruzioni, mano)
const PANEL_HI := Color("1d2833")      ## vetro illuminato (hover)
const PANEL_EDGE := Color("2c3e4c")    ## bordo ciano-grigio dei pannelli
const PANEL_BG := PANEL                ## compatibilità con il vecchio tema

const TEXT := Color("e4ecf2")          ## testo chiaro
const TEXT_DIM := Color("93a6b6")      ## testo attenuato (etichette)
const TEXT_FAINT := Color("5a6b7a")    ## testo disattivato
## Sul vetro l'«inchiostro» è chiaro: i nomi restano quelli di Cuba Libre, i ruoli
## sono invertiti rispetto alla carta.
const INK := TEXT
const INK_DIM := TEXT_DIM
const INK_FAINT := TEXT_FAINT

const MARS := Color("e0602b")          ## arancio Marte: tasto principale, accenti
const MARS_DARK := Color("7a2e10")     ## «spessore» del tasto principale
const MARS_HI := Color("ff7a3d")
const CYAN := Color("4fd1d9")          ## spazi validi, scelta in corso, focus
const CYAN_DIM := Color("2a7d84")
const CHOSEN := Color("ffb347")        ## spazi già scelti sulla mappa
const ACCENT := CYAN                   ## compatibilità
const FOCUS := CYAN                    ## compatibilità

const OK := Color("5fd38d")
const ERR := Color("ff6b5b")
const WARN := Color("ffb454")
const LOG_BG := Color("0d1319")
const LOG_EDGE := Color("22303b")

# Tasti sul fondo (barra superiore, menu iniziale, finestre).
const BTN_BG := Color("141c24")
const BTN_BORDER := Color("2f4250")
const BTN_HOVER_BG := Color("1d2833")
const BTN_HOVER_BORDER := CYAN
const BTN_PRESSED_BG := Color("0b1117")
const BTN_DISABLED_BG := Color("0f151b")
const BTN_DISABLED_BORDER := Color("1c2731")
const BTN_DISABLED_TEXT := Color("4c5c6a")
const FONT_SIZE := 15

## Colori delle Fazioni come superficie (tessere, intestazione, tasto scelto).
## Il nero delle Corporations sul fondo scuro sparirebbe: diventa acciaio.
const FACTION := {
	"marsgov": Color("2f6fb5"), "corporations": Color("4a535e"),
	"red_dust": Color("c0392b"), "reclaimer": Color("c8661c"),
	"earthgov": Color("dfe6ec"),
}
## Colori per il TESTO sul fondo scuro (registro, pannelli informativi).
const FACTION_TEXT := {
	"marsgov": Color("6aa8e8"), "corporations": Color("b8c2cc"),
	"red_dust": Color("ff7a6b"), "reclaimer": Color("f5a35a"),
	"earthgov": Color("ecf0f1"),
}
## Colori stampati sul gioco: tinta del Controllo sulla mappa.
const FACTION_BOARD := {
	"marsgov": Color("2f6fb5"), "corporations": Color("1c1c1c"),
	"red_dust": Color("c0392b"), "reclaimer": Color("e67e22"),
	"earthgov": Color("ecf0f1"), "coin": Color("2f6fb5"),
}

# --- Caratteri (OFL, in res://assets/fonts) ------------------------------------
const FONT_DIR := "res://assets/fonts/"
static var _fonts: Dictionary = {}


static func _font(file: String) -> Font:
	if not _fonts.has(file):
		var path := FONT_DIR + file
		var f: Font = load(path) if ResourceLoader.exists(path) else null
		if f == null:
			f = ThemeDB.fallback_font
		else:
			# Rajdhani e Orbitron non hanno «ª», frecce e simboli (★, ⚠): li
			# prende il carattere incorporato di Godot invece di un quadratino.
			var fb: Array[Font] = [ThemeDB.fallback_font]
			f.fallbacks = fb
		_fonts[file] = f
	return _fonts[file]


## Orbitron (variabile) con il peso scelto: titoli, numeri grandi, tasto principale.
static func _orbitron(weight: int) -> Font:
	var key := "orbitron_%d" % weight
	if not _fonts.has(key):
		var base := _font("Orbitron[wght].ttf")
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		var fb: Array[Font] = [ThemeDB.fallback_font]
		fv.fallbacks = fb
		_fonts[key] = fv
	return _fonts[key]


static func display() -> Font: return _orbitron(700)
static func display_light() -> Font: return _orbitron(500)
## Share Tech Mono: registro, istruzioni, descrizioni (il «terminale» della colonia).
static func mono() -> Font: return _font("ShareTechMono-Regular.ttf")
## Stesso ruolo che in Cuba Libre aveva la macchina da scrivere.
static func typewriter() -> Font: return mono()
## Rajdhani: testo dell'interfaccia.
static func ui() -> Font: return _font("Rajdhani-Medium.ttf")
static func ui_bold() -> Font: return _font("Rajdhani-SemiBold.ttf")
static func ui_heavy() -> Font: return _font("Rajdhani-Bold.ttf")


static func faction(fid: String) -> Color:
	return FACTION.get(fid, PANEL_EDGE)


## Colore del testo di una Fazione, leggibile sul fondo scuro.
static func faction_text(fid: String) -> Color:
	return FACTION_TEXT.get(fid, TEXT)


## Compatibilità con Cuba Libre: sul vetro scuro l'«inchiostro» della Fazione è il
## suo colore di testo.
static func faction_ink(fid: String) -> Color:
	return faction_text(fid)


## Testo sopra una superficie del colore della Fazione.
static func faction_on(fid: String) -> Color:
	return Color("0b0f14") if fid == "earthgov" else Color.WHITE


# --- Riquadri -------------------------------------------------------------------

## Riquadro con bordo, usato per tutti gli stati dei tasti.
static func box(bg: Color, border: Color, border_w: int = 1, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


## Vetro del pannello HUD: ardesia, bordo ciano-grigio, ombra.
static func glass_box(margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.set_corner_radius_all(4)
	s.border_color = PANEL_EDGE
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin - 2.0
	s.content_margin_bottom = margin - 2.0
	return s


## Nome che aveva in Cuba Libre (foglio di carta): qui è il vetro.
static func paper_box(margin: float = 12.0) -> StyleBoxFlat:
	return glass_box(margin)


## Riquadro scuro semitrasparente (comandi sopra la mappa, registro).
static func dark_box(bg: Color = Color(0.03, 0.05, 0.07, 0.86), border: Color = BTN_BORDER) -> StyleBoxFlat:
	var s := box(bg, border)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func flat(bg: Color, margin: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


# --- Temi ----------------------------------------------------------------------

static var _dark_theme: Theme
static var _panel_theme: Theme


## Compatibilità: il vecchio nome del tema di scena.
static func make_theme() -> Theme:
	return dark_theme()


## Tema del fondo scuro: si applica alla radice della scena e alla finestra, così
## anche menu a tendina e finestre di dialogo prendono caratteri e colori.
static func dark_theme() -> Theme:
	if _dark_theme != null:
		return _dark_theme
	var t := Theme.new()
	t.default_font = ui()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)
	for type in ["Button", "MenuButton", "OptionButton"]:
		_button_styles(t, type, BTN_BG, BTN_BORDER, BTN_HOVER_BG, BTN_HOVER_BORDER, BTN_PRESSED_BG,
			BTN_DISABLED_BG, BTN_DISABLED_BORDER, TEXT, Color.WHITE, BTN_DISABLED_TEXT, 1)
		t.set_font("font", type, ui_bold())
	_common_controls(t)
	# Menu a tendina: vetro scuro con la voce evidenziata in ciano.
	var pm := box(Color("10171e"), PANEL_EDGE)
	pm.content_margin_top = 6.0
	pm.content_margin_bottom = 6.0
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color("173039"), CYAN))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", BTN_DISABLED_TEXT)
	t.set_color("font_separator_color", "PopupMenu", CYAN)
	t.set_font("font", "PopupMenu", ui_bold())
	t.set_font("font_separator", "PopupMenu", ui_bold())
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	t.set_font_size("font_separator_size", "PopupMenu", 13)
	# Finestre di dialogo: vetro del pannello.
	t.set_stylebox("panel", "AcceptDialog", glass_box(18.0))
	t.set_color("font_color", "AcceptDialog", TEXT)
	var wb := box(PANEL, PANEL_EDGE)
	wb.expand_margin_top = 30
	wb.border_width_top = 2
	wb.border_color = MARS
	t.set_stylebox("embedded_border", "Window", wb)
	t.set_stylebox("embedded_unfocused_border", "Window", wb)
	t.set_color("title_color", "Window", TEXT)
	t.set_font("title_font", "Window", display())
	t.set_font_size("title_font_size", "Window", 16)
	_dark_theme = t
	return t


## Tema del pannello HUD (vetro): tasti a contorno, testo chiaro.
static func panel_theme() -> Theme:
	if _panel_theme != null:
		return _panel_theme
	var t := Theme.new()
	t.default_font = ui()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)
	for type in ["Button", "MenuButton", "OptionButton"]:
		_button_styles(t, type, Color(0, 0, 0, 0), BTN_BORDER, PANEL_HI, CYAN, CYAN_DIM,
			Color(0, 0, 0, 0), Color("1f2b35"), TEXT, Color.WHITE, TEXT_FAINT, 1)
		t.set_font("font", type, ui_bold())
	_common_controls(t)
	var pm := box(Color("10171e"), PANEL_EDGE)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color("173039"), CYAN))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	t.set_font("font", "PopupMenu", ui_bold())
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	_panel_theme = t
	return t


## Comandi comuni alle due superfici: testi, schede, caselle, barre di scorrimento.
static func _common_controls(t: Theme) -> void:
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", ui())
	t.set_font("bold_font", "RichTextLabel", ui_heavy())
	t.set_font("mono_font", "RichTextLabel", mono())
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	t.set_font_size("bold_font_size", "RichTextLabel", 14)
	t.set_stylebox("panel", "TooltipPanel", box(BAR, CYAN))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", ui())
	# Caselle di spunta e interruttori (Bombard, Ambush, «Dettagli»).
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, flat(Color(0, 0, 0, 0), 2))
		t.set_stylebox("hover", type, flat(Color(1, 1, 1, 0.05), 2))
		t.set_stylebox("pressed", type, flat(Color(0, 0, 0, 0), 2))
		t.set_stylebox("hover_pressed", type, flat(Color(1, 1, 1, 0.05), 2))
		t.set_stylebox("disabled", type, flat(Color(0, 0, 0, 0), 2))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, CYAN)
		t.set_color("font_hover_pressed_color", type, CYAN)
		t.set_color("font_disabled_color", type, TEXT_FAINT)
		t.set_font("font", type, ui_bold())
		t.set_font_size("font_size", type, 14)
	# Campi di testo e numeri (seme, dadi dell'Ambush, quantità).
	var le := box(PANEL_DARK, BTN_BORDER)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(PANEL_DARK, CYAN))
	t.set_stylebox("read_only", "LineEdit", box(PANEL_DARK, BTN_DISABLED_BORDER))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_color("selection_color", "LineEdit", CYAN_DIM)
	t.set_font_size("font_size", "LineEdit", FONT_SIZE)
	t.set_font_size("font_size", "SpinBox", FONT_SIZE)
	# Schede (Stato / Carta / Spazio).
	var tab_sel := flat(PANEL, 0)
	tab_sel.content_margin_left = 10
	tab_sel.content_margin_right = 10
	tab_sel.content_margin_top = 3
	tab_sel.content_margin_bottom = 3
	tab_sel.border_width_top = 2
	tab_sel.border_color = CYAN
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_color = Color(0, 0, 0, 0)
	var tab_hov := tab_un.duplicate() as StyleBoxFlat
	tab_hov.bg_color = PANEL_HI
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_stylebox("tab_disabled", "TabContainer", tab_un)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	var tpanel := flat(PANEL, 6)
	tpanel.border_width_top = 1
	tpanel.border_color = PANEL_EDGE
	t.set_stylebox("panel", "TabContainer", tpanel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", ui_bold())
	t.set_font_size("font_size", "TabContainer", 14)
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 6))
	t.set_color("separator", "HSeparator", PANEL_EDGE)
	var sep := StyleBoxLine.new()
	sep.color = PANEL_EDGE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	# Barre di scorrimento sottili, color ciano.
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", sb_type, box(Color("2c3e4c"), Color("2c3e4c"), 0, 4))
		t.set_stylebox("grabber_highlight", sb_type, box(CYAN_DIM, CYAN_DIM, 0, 4))
		t.set_stylebox("grabber_pressed", sb_type, box(CYAN, CYAN, 0, 4))
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.0)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		t.set_stylebox("scroll", sb_type, track)


static func _button_styles(t: Theme, type: String, bg: Color, border: Color, hover_bg: Color,
		hover_border: Color, pressed_bg: Color, dis_bg: Color, dis_border: Color,
		fg: Color, hover_fg: Color, dis_fg: Color, bw: int) -> void:
	t.set_stylebox("normal", type, box(bg, border, bw))
	t.set_stylebox("hover", type, box(hover_bg, hover_border, bw))
	t.set_stylebox("pressed", type, box(pressed_bg, hover_border, bw))
	t.set_stylebox("hover_pressed", type, box(pressed_bg, hover_border, bw))
	t.set_stylebox("disabled", type, box(dis_bg, dis_border, bw))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, hover_fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_pressed_color", type, hover_fg)
	t.set_color("font_hover_pressed_color", type, hover_fg)
	t.set_color("font_disabled_color", type, dis_fg)


# --- Tasti ---------------------------------------------------------------------

## Veste standard di un tasto: colori e riquadri arrivano dal tema della superficie
## su cui si trova; qui resta solo ciò che vale ovunque.
static func style_button(b: Button) -> void:
	# Niente focus persistente: altrimenti Invio/Spazio ri-attivano l'ultimo tasto
	# premuto invece di eseguire le scorciatoie di turno.
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.remove_theme_stylebox_override(st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.remove_theme_color_override(c)


## Tasto sul fondo con veste esplicita (dove il tema della scena non arriva).
static func style_dark_button(b: Button) -> void:
	style_button(b)
	b.add_theme_stylebox_override("normal", box(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("hover", box(BTN_HOVER_BG, BTN_HOVER_BORDER))
	b.add_theme_stylebox_override("pressed", box(BTN_PRESSED_BG, BTN_BORDER))
	b.add_theme_stylebox_override("disabled", box(BTN_DISABLED_BG, BTN_DISABLED_BORDER))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", BTN_DISABLED_TEXT)
	b.add_theme_font_override("font", ui_bold())
	b.add_theme_font_size_override("font_size", FONT_SIZE)


## Tasto in evidenza, con sfondo pieno (scelta attiva, Auto-Bot acceso…).
static func accent_button(b: Button, bg: Color, border: Color, fg: Color = Color.WHITE) -> void:
	b.add_theme_stylebox_override("normal", box(bg, border, 1))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.12), border.lightened(0.2), 1))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.18), border, 1))
	b.add_theme_stylebox_override("hover_pressed", box(bg.darkened(0.18), border, 1))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fg)


## Tasto «a contrasto»: chiaro sul vetro scuro (es. «Concludi turno»).
static func inverse_button(b: Button) -> void:
	accent_button(b, Color("d6e1ea"), Color("d6e1ea"), BG)
	b.add_theme_stylebox_override("disabled", box(Color(0, 0, 0, 0), Color("1f2b35"), 1))


## Tasto principale del pannello: arancio Marte pieno con «spessore» sotto.
static func primary_button(b: Button, size: int = 17) -> void:
	style_button(b)
	var n := box(MARS, MARS, 0)
	n.border_width_bottom = 4
	n.border_color = MARS_DARK
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = MARS_HI
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = MARS.darkened(0.15)
	p.border_width_bottom = 1
	var d := box(Color("1b242d"), Color("26323d"), 1)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_font_override("font", display())
	b.add_theme_font_size_override("font_size", size)


## Tasto di una Fazione (Support Phase): bordo del suo colore.
static func faction_button(b: Button, fid: String) -> void:
	style_button(b)
	var col := faction(fid)
	b.add_theme_stylebox_override("normal", box(col.darkened(0.7), col, 1))
	b.add_theme_stylebox_override("hover", box(col.darkened(0.5), col.lightened(0.3), 1))
	b.add_theme_stylebox_override("pressed", box(col, col, 1))
	b.add_theme_color_override("font_color", faction_text(fid).lightened(0.3))
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# --- Etichette -----------------------------------------------------------------

## Titolo di sezione in Orbitron (es. «OPERAZIONE»).
static func section_title(text: String, color: Color = TEXT_DIM, size: int = 12) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", display())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Etichetta generica con carattere/colore/dimensione.
static func label(text: String, color: Color, size: int = FONT_SIZE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Testo su fondino del colore della Fazione (registro e pannelli).
static func faction_chip(text: String, fid: String) -> String:
	if fid == "":
		return text
	var hex := faction(fid).to_html(false)
	var fg := faction_on(fid).to_html(false)
	return "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" % [hex, fg, text]


## Tooltip opaco e a capo (quello di default è trasparente e su una riga sola).
static func build_tip(for_text: String) -> Control:
	var pc := PanelContainer.new()
	var sb := box(BAR, CYAN_DIM, 1, 3)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = for_text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_font_override("font", ui())
	l.add_theme_font_size_override("font_size", 15)
	pc.add_child(l)
	return pc


## Emblema disegnato: il disco di Marte con un anello d'orbita e Phobos.
class Emblem:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.34
		# Alone e disco del pianeta, con una calotta in ombra.
		draw_circle(c, r * 1.25, Color(RDRTheme.MARS, 0.12))
		draw_circle(c, r, Color("b8461c"))
		draw_circle(c + Vector2(r * 0.22, r * 0.18), r * 0.78, Color("d4582a"))
		draw_circle(c + Vector2(-r * 0.35, -r * 0.3), r * 0.22, Color("e98a52"))
		draw_circle(c + Vector2(r * 0.25, r * 0.38), r * 0.14, Color("9c3714"))
		# Anello d'orbita inclinato: metà dietro il pianeta, metà davanti.
		var pts := PackedVector2Array()
		for i in range(65):
			var a := TAU * i / 64.0
			var p := Vector2(cos(a) * r * 1.75, sin(a) * r * 0.55).rotated(-0.42)
			pts.append(c + p)
		draw_polyline(pts, Color(RDRTheme.CYAN, 0.9), 1.6, true)
		# Phobos sull'orbita.
		var ph := c + Vector2(cos(0.5) * r * 1.75, sin(0.5) * r * 0.55).rotated(-0.42)
		draw_circle(ph, maxf(2.0, r * 0.17), Color("cfd8df"))
