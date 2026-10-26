class_name TipButton
extends Button

## Tasto con tooltip OPACO e a CAPO (quello di default è trasparente e su una sola
## riga lunghissima, illeggibile).

func _make_custom_tooltip(for_text: String) -> Object:
	return RDRTheme.build_tip(for_text)
