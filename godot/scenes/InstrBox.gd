class_name InstrBox
extends PanelContainer

## Riquadro delle istruzioni di turno: altezza contenuta (righe limitate) ma testo
## completo sempre leggibile — al passaggio del mouse compare un tooltip opaco con
## l'intero messaggio.

func _make_custom_tooltip(for_text: String) -> Object:
	return RDRTheme.build_tip(for_text)
