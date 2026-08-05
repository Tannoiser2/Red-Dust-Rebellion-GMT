class_name RDRDeck
extends RefCounted

## Costruzione del mazzo Eventi (§3.3).
##
## Si tolgono le 3 carte Dust Storm, si mescolano le 48 restanti e si distribuiscono
## 3 pile da 12; le ultime 12 escono dal gioco senza essere viste. In ciascuna pila
## si mescola una Dust Storm nelle 6 carte in fondo, poi si impilano le tre pile:
## il mazzo finale è di 39 carte.

const EVENT_CARDS := 48
const DUST_STORM_CARDS := [49, 50, 51]
const PILES := 3
const PILE_SIZE := 12
const BOTTOM := 6   ## carte in fondo a ciascuna pila fra cui mescolare la Dust Storm


## Restituisce il mazzo pronto per `GameState.draw_deck` (convenzione del motore:
## la CIMA del mazzo è l'ULTIMO elemento dell'array).
static func build(rng: RandomNumberGenerator) -> Array[int]:
	var events: Array[int] = []
	for n in range(1, EVENT_CARDS + 1):
		events.append(n)
	_shuffle(events, rng)

	var storms: Array[int] = []
	for n in DUST_STORM_CARDS:
		storms.append(int(n))
	_shuffle(storms, rng)

	# Dall'alto verso il basso: pila 1, pila 2, pila 3.
	# NB: Array.slice() restituisce un Array non tipizzato, quindi le pile si
	# costruiscono a mano per restare Array[int].
	var top_down: Array[int] = []
	for p in range(PILES):
		var base := p * PILE_SIZE
		var bottom: Array[int] = []
		for i in range(PILE_SIZE):
			if i < PILE_SIZE - BOTTOM:
				top_down.append(events[base + i])
			else:
				bottom.append(events[base + i])
		bottom.append(storms[p])
		_shuffle(bottom, rng)
		top_down.append_array(bottom)
	# Le 12 carte rimanenti (events[36..47]) escono dal gioco senza essere viste.

	var deck: Array[int] = []
	for i in range(top_down.size() - 1, -1, -1):
		deck.append(top_down[i])
	return deck


## Numeri delle carte escluse dal gioco durante la preparazione, ricavabili per
## differenza: utile ai test e alla UI ("carte rimaste nel mazzo" è informazione
## aperta, §4.0).
static func removed_from_play(deck: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for n in range(1, EVENT_CARDS + 1):
		if not deck.has(n):
			out.append(n)
	return out


static func is_dust_storm(number: int) -> bool:
	return DUST_STORM_CARDS.has(number)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
