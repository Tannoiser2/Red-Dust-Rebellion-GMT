"""Estrae le carte Evento (e Asset/Campaign se presenti) dal Playbook di Red Dust Rebellion.

Uso (dalla root del repo):
    python3 sources/rules/estrai_carte_rdr.py

Il Playbook elenca ogni carta nella forma:

    12. Red Wednesday Riots (3) M D C R
    <titolo effetto non ombreggiato>: <testo>
    <titolo effetto ombreggiato>: <testo>
    Tips: ...
    Background: ...

dove il numero fra parentesi è il valore Flashpoint e le lettere sono l'ordine di
Eligibility (M=MarsGov, C=Corporations, D=Red Dust, R=Church of the Reclaimer).

Scrive `godot/games/red_dust_rebellion/data/cards.json`.
"""

import json
import os
import re

import fitz  # PyMuPDF

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PDF = os.path.join(REPO, "sources", "rules", "RDR_Play+Booklet_1D_Web.pdf")
OUT = os.path.join(REPO, "godot", "games", "red_dust_rebellion", "data", "cards.json")

FACTION = {"M": "marsgov", "C": "corporations", "D": "red_dust", "R": "reclaimer"}

# "12. Red Wednesday Riots (3) M D C R"
HEAD = re.compile(r"^(\d{1,2})\.\s+(.+?)\s*\((\d)\)\s*((?:[MCDR]\s*){4})$")

# Titoli dei tre Eventi Dust Storm (non elencati nel Playbook).
DUST_STORMS = {49: "Dust Storm", 50: "Dust Storm", 51: "Dust Storm"}


def column_blocks(page):
    """Blocchi di testo ordinati per colonna (sinistra, poi destra) e poi per y."""
    blocks = [b for b in page.get_text("blocks") if b[4].strip()]
    blocks.sort(key=lambda b: (0 if b[0] < 300 else 1, b[1]))
    return [b[4].strip() for b in blocks]


def flow(pdf_path, first_page=23, last_page=40):
    doc = fitz.open(pdf_path)
    out = []
    for i in range(first_page, min(last_page + 1, doc.page_count)):
        out.extend(column_blocks(doc[i]))
    return out


def clean(text):
    t = " ".join(text.replace("\n", " ").split())
    # ricompone le parole spezzate a fine riga dal PDF ("Lab- yrinths" -> "Labyrinths")
    return re.sub(r"(\w)- (?=[a-z])", r"\1", t)


def split_effect(text):
    """'[EG+] Titolo: testo' -> (titolo, testo, eg)."""
    eg = ""
    t = clean(text)
    m = re.match(r"^\[(EG[+–\-])\]\s*(.*)$", t)
    if m:
        eg = "EG+" if "+" in m.group(1) else "EG-"
        t = m.group(2)
    if ":" in t:
        head, body = t.split(":", 1)
        # evita di spezzare su ':' che compare a metà frase
        if len(head) < 90:
            head, body = clean(head), clean(body)
            # alcuni titoli contengono a loro volta ':' (#21 "Directive 1: Serve…")
            if ":" in body and len(body.split(":", 1)[0]) < 40:
                extra, body = body.split(":", 1)
                head = "%s: %s" % (head, extra.strip())
                body = clean(body)
            return head, body, eg
    return "", t, eg


def main():
    blocks = flow(PDF)
    cards = {}
    cur = None
    slot = 0
    for b in blocks:
        first = b.split("\n", 1)[0].strip()
        m = HEAD.match(first)
        if m:
            num = int(m.group(1))
            cur = {
                "number": num,
                "title": m.group(2).strip(),
                "flashpoint": int(m.group(3)),
                "faction_order": [FACTION[c] for c in m.group(4).split()],
                "unshaded": "",
                "shaded": "",
            }
            cards[num] = cur
            slot = 0
            continue
        if cur is None:
            continue
        c = clean(b)
        if c.startswith("Tips:"):
            cur["tips"] = clean(c[len("Tips:"):])
            slot = 9
            continue
        if c.startswith("Background:"):
            cur["history"] = clean(c[len("Background:"):])
            slot = 9
            continue
        if slot == 0:
            head, body, eg = split_effect(b)
            cur["unshaded_title"] = head
            cur["unshaded"] = body
            if eg:
                cur["unshaded_eg"] = eg
            slot = 1
        elif slot == 1:
            head, body, eg = split_effect(b)
            cur["shaded_title"] = head
            cur["shaded"] = body
            if eg:
                cur["shaded_eg"] = eg
            slot = 2

    for num, title in DUST_STORMS.items():
        cards[num] = {
            "number": num,
            "title": title,
            "flashpoint": 0,
            "faction_order": [],
            "dust_storm": True,
            "unshaded": "",
            "shaded": "",
        }

    ordered = [cards[k] for k in sorted(cards)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(
            {
                "_note": (
                    "48 carte Evento + 3 Dust Storm. Testi ed Eligibility estratti dal "
                    "Playbook (pp. 24-40) con sources/rules/estrai_carte_rdr.py. "
                    "flashpoint = valore del simbolo fulmine; faction_order = ordine "
                    "di Eligibility stampato sulla carta."
                ),
                "cards": ordered,
            },
            fh,
            ensure_ascii=False,
            indent=1,
        )
    missing = [n for n in range(1, 52) if n not in cards]
    print("carte estratte:", len(ordered), "mancanti:", missing)
    for c in ordered[:3]:
        print(c["number"], c["title"], c["flashpoint"], c["faction_order"])


if __name__ == "__main__":
    main()
