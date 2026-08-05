class_name RDRTheme
extends RefCounted

## Aspetto dei comandi: unico posto dove vivono colori e riquadri dei tasti.
## Stessa impostazione di Cuba Libre e All Bridges Burning — senza, gli stessi
## StyleBox finirebbero ricostruiti a mano in mezza dozzina di funzioni diverse,
## col rischio che un ritocco ne raggiunga solo una parte.
##
## La tavolozza è quella marziana della tavola: ruggine sul fondo, ocra per le
## intestazioni, ciano per ciò su cui si sta lavorando.

const BG := Color("14100e")             ## sfondo della scena
const PANEL_BG := Color("1c1714")
const TEXT := Color("ece3da")
const TEXT_DIM := Color("9a8d82")
const ACCENT := Color("e0b070")         ## intestazioni
const FOCUS := Color("7fc4d8")          ## ciò che è in corso di pianificazione
const OK := Color("57c97e")
const ERR := Color("e05a4b")
const WARN := Color("e0b070")

const BTN_BG := Color("32271f")
const BTN_BORDER := Color("57453a")
const BTN_HOVER_BG := Color("453529")
const BTN_HOVER_BORDER := Color("8a6f5c")
const BTN_PRESSED_BG := Color("241c16")
const BTN_DISABLED_BG := Color("241f1b")
const BTN_DISABLED_BORDER := Color("352e28")
const BTN_DISABLED_TEXT := Color("6b6058")
const FONT_SIZE := 12


## Riquadro arrotondato con bordo, usato per tutti gli stati dei tasti.
static func box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	return s


## Tema dell'intera scena. Applicato al nodo radice vale anche per i comandi
## creati al volo (la barra delle azioni si ricostruisce a ogni turno), che con
## le override per singolo tasto resterebbero regolarmente scoperti.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", box(BTN_BG, BTN_BORDER))
	t.set_stylebox("hover", "Button", box(BTN_HOVER_BG, BTN_HOVER_BORDER))
	t.set_stylebox("pressed", "Button", box(BTN_PRESSED_BG, BTN_BORDER))
	t.set_stylebox("disabled", "Button", box(BTN_DISABLED_BG, BTN_DISABLED_BORDER))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", BTN_DISABLED_TEXT)
	t.set_font_size("font_size", "Button", FONT_SIZE)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(8.0)
	t.set_stylebox("panel", "PanelContainer", panel)

	for cls in ["OptionButton", "SpinBox"]:
		t.set_font_size("font_size", cls, FONT_SIZE)
	return t


## Veste standard di un tasto: riquadro, stati e colori del testo.
static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("hover", box(BTN_HOVER_BG, BTN_HOVER_BORDER))
	b.add_theme_stylebox_override("pressed", box(BTN_PRESSED_BG, BTN_BORDER))
	b.add_theme_stylebox_override("disabled", box(BTN_DISABLED_BG, BTN_DISABLED_BORDER))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", BTN_DISABLED_TEXT)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	# Niente focus persistente: altrimenti Invio e Spazio ri-attivano l'ultimo
	# tasto premuto invece di eseguire le scorciatoie di turno.
	b.focus_mode = Control.FOCUS_NONE


## Tasto in evidenza, con sfondo pieno (per «Esegui» e simili).
static func accent_button(b: Button, bg: Color, border: Color) -> void:
	b.add_theme_stylebox_override("normal", box(bg, border))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.12), border))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.18), border))
	b.add_theme_color_override("font_color", Color.WHITE)


## Testo su fondino del colore della Fazione (log e pannelli). Il nero delle
## Corporations richiede testo chiaro, il bianco di EarthGov testo scuro.
static func faction_chip(text: String, faction: String) -> String:
	if faction == "":
		return text
	var hex: String = (RDRAssets.FACTION_COLORS.get(faction, Color.GRAY) as Color).to_html(false)
	var fg := "000000" if faction == "earthgov" else "ffffff"
	return "[bgcolor=#%s] [color=#%s] %s [/color] [/bgcolor]" % [hex, fg, text]
