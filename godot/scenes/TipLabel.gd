class_name TipLabel
extends Label

## Etichetta con tooltip opaco e a capo (come TipButton): serve per l'anteprima
## dell'azione, il cui elenco di effetti è lungo più righe.

func _make_custom_tooltip(for_text: String) -> Object:
	return RDRTheme.build_tip(for_text)
