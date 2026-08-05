"""Ricava gli effetti eseguibili automaticamente dalle carte Evento.

SUPERATO — tenuto solo come traccia di come è nata la libreria degli Eventi.

Questo script riconosceva dai testi appena 6 opzioni su 93 e marcava `manual`
tutte le altre. `data/event_effects.json` oggi è scritto a mano, carta per
carta, con le scelte dei giocatori dichiarate esplicitamente (vedi
`rules/Events.gd`): rigenerarlo da qui butterebbe via quel lavoro.

Per questo l'output va in `event_effects_auto.json`, che il gioco NON legge.

Uso (dalla root del repo):
    python3 sources/rules/estrai_effetti_eventi.py
"""

import json
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(REPO, "godot", "games", "red_dust_rebellion", "data")

# Ogni clausola: (regex, funzione che produce la lista di effetti atomici).
def space_ids():
    """Nome stampato -> id, per le clausole che nominano uno spazio preciso."""
    spaces = json.load(open(os.path.join(DATA, "spaces.json"), encoding="utf-8"))["spaces"]
    out = {}
    for s in spaces:
        out[s["name"]] = s["id"]
        # il Playbook scrive "New Córdoba" ma anche "New Cordoba"
        out[s["name"].replace("ó", "o")] = s["id"]
    return out


SPACES = space_ids()
NAMES = "|".join(sorted((re.escape(n) for n in SPACES), key=len, reverse=True))


def shift_named(names, levels, direction):
    return [{"op": "shift_space", "space": SPACES[n], "levels": levels, "direction": direction}
            for n in names]


CLAUSES = [
    (r"^(?:Increase|increase) Profits by (\d+)$",
     lambda m: [{"op": "profits", "delta": int(m.group(1))}]),
    (r"^(?:Reduce|reduce) Profits by (\d+)$",
     lambda m: [{"op": "profits", "delta": -int(m.group(1))}]),
    (r"^(?:Increase|increase) MG Resources by (\d+)$",
     lambda m: [{"op": "resources", "faction": "marsgov", "delta": int(m.group(1))}]),
    (r"^(?:Reduce|reduce) MG Resources by (\d+)$",
     lambda m: [{"op": "resources", "faction": "marsgov", "delta": -int(m.group(1))}]),
    (r"^(?:Increase|increase) RD Resources by (\d+)$",
     lambda m: [{"op": "resources", "faction": "red_dust", "delta": int(m.group(1))}]),
    (r"^(?:Reduce|reduce) RD Resources by (\d+)$",
     lambda m: [{"op": "resources", "faction": "red_dust", "delta": -int(m.group(1))}]),
    # forme composte: "Reduce Profits by 5 and MG Resources by 9"
    (r"^(?:Reduce|reduce) Profits by (\d+) and MG Resources by (\d+)$",
     lambda m: [{"op": "profits", "delta": -int(m.group(1))},
                {"op": "resources", "faction": "marsgov", "delta": -int(m.group(2))}]),
    (r"^(?:Place|place) (\d+) Supply markers? on Earth$",
     lambda m: [{"op": "supply_earth", "delta": int(m.group(1))}]),
    (r"^(?:Place|place) (\d+) Population markers? on Earth$",
     lambda m: [{"op": "population_earth", "delta": int(m.group(1))}]),
    (r"^(?:Shift|shift) any (\d+) spaces? 1 level each towards Active (Support|Opposition)$",
     lambda m: [{"op": "shift_spaces", "count": int(m.group(1)),
                 "direction": 1 if m.group(2) == "Support" else -1}]),
    (r"^(?:Activate|activate) all RD Rebels$",
     lambda m: [{"op": "activate_all", "faction": "red_dust"}]),
    (r"^(?:Activate|activate) all CR Rebels$",
     lambda m: [{"op": "activate_all", "faction": "reclaimer"}]),
    (r"^(?:Activate|activate) all Rebels$",
     lambda m: [{"op": "activate_all", "faction": "both"}]),
    # Clausole su spazi NOMINATI: nessuna scelta da fare, quindi automatiche.
    (r"^(?:Shift|shift) (" + NAMES + r") (\d+) levels? towards Active (Support|Opposition)$",
     lambda m: shift_named([m.group(1)], int(m.group(2)),
                           1 if m.group(3) == "Support" else -1)),
    (r"^(?:Shift|shift) (" + NAMES + r") and (" + NAMES + r") (\d+) levels? each towards Active (Support|Opposition)$",
     lambda m: shift_named([m.group(1), m.group(2)], int(m.group(3)),
                           1 if m.group(4) == "Support" else -1)),
    (r"^(?:Set|set) (" + NAMES + r") to Neutral$",
     lambda m: [{"op": "set_neutral", "space": SPACES[m.group(1)]}]),
    (r"^(?:Remove|remove) all Supply markers from (Earth|Transit)$",
     lambda m: [{"op": "clear_supply", "space": m.group(1).lower()}]),
]


def split_sentences(text):
    """Spezza il testo in frasi, tenendo insieme i numeri con la virgola."""
    parts = re.split(r"(?<=[.;])\s+", text.strip())
    out = []
    for p in parts:
        p = p.strip().rstrip(".;").strip()
        if p:
            out.append(p)
    return out


def parse_option(text, eg_side):
    """Restituisce (effetti, residuo_non_interpretato)."""
    effects = []
    if eg_side:
        effects.append({"op": "eg_side", "side": eg_side})
    residual = []
    for sentence in split_sentences(text):
        matched = None
        for pattern, build in CLAUSES:
            m = re.match(pattern + "$", sentence)
            if m:
                matched = build(m)
                break
        if matched is None:
            residual.append(sentence)
        else:
            effects.extend(matched)
    return effects, ". ".join(residual)


def main():
    cards = json.load(open(os.path.join(DATA, "cards.json"), encoding="utf-8"))["cards"]
    out = {}
    auto = 0
    total = 0
    for c in cards:
        entry = {}
        for opt in ("unshaded", "shaded"):
            text = c.get(opt, "")
            if not text:
                continue
            total += 1
            effects, residual = parse_option(text, c.get(opt + "_eg", ""))
            record = {"text": text}
            if residual or not effects:
                record["manual"] = True
                record["residual"] = residual or text
                # anche negli Eventi manuali l'EG+/EG− è automatico
                record["effects"] = [e for e in effects if e["op"] == "eg_side"]
            else:
                record["effects"] = effects
                auto += 1
            entry[opt] = record
        if entry:
            out[str(c["number"])] = entry

    with open(os.path.join(DATA, "event_effects_auto.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "_note": (
                "NON USATO DAL GIOCO. Estrazione automatica di riferimento: il file "
                "buono è event_effects.json, scritto a mano. Qui un'opzione è "
                "automatica solo se OGNI sua frase è stata riconosciuta dai testi; "
                "altrimenti resta marcata `manual`."
            ),
            "events": out,
        }, fh, ensure_ascii=False, indent=1)
    print("opzioni totali: %d — automatiche: %d — manuali: %d" % (total, auto, total - auto))


if __name__ == "__main__":
    main()
