class_name BottomStrip
extends PanelContainer

## Striscia sotto la mappa: il Log della partita, con l'interruttore «Dettagli».
## Il contenuto (righe colorate per Fazione, dettagli nascosti, salvataggio) lo
## gestisce la scena: qui c'è solo il contenitore, così la mappa guadagna altezza
## e il Log resta sempre leggibile.

const HEIGHT := 150.0
const HEIGHT_SMALL := 118.0

var log_view: RichTextLabel     ## esposto: la scena ci scrive le righe
var details: CheckButton        ## «Dettagli»: tiri di dado e passaggi intermedi


func _init() -> void:
	add_theme_stylebox_override("panel", RDRTheme.dark_box(RDRTheme.LOG_BG, RDRTheme.LOG_EDGE))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(RDRTheme.section_title("Registro", RDRTheme.MARS_HI, 12))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	details = CheckButton.new()
	details.text = "Dettagli"
	details.tooltip_text = "Mostra tiri di dado, righe delle tabelle e passaggi intermedi."
	details.focus_mode = Control.FOCUS_NONE
	details.add_theme_font_size_override("font_size", 13)
	head.add_child(details)
	v.add_child(head)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 50)
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		log_view.add_theme_font_size_override(fs, 13)
	# Il Log è il «terminale» della colonia: carattere a spaziatura fissa.
	log_view.add_theme_font_override("normal_font", RDRTheme.mono())
	log_view.add_theme_font_override("italics_font", RDRTheme.mono())
	log_view.add_theme_font_override("bold_font", RDRTheme.ui_heavy())
	log_view.add_theme_color_override("default_color", Color("c9d6e0"))
	log_view.add_theme_constant_override("line_separation", 1)
	v.add_child(log_view)
