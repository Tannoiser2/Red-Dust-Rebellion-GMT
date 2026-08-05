"""Simboli ★/⊘ delle carte Evento: estrazione + foglio di contatto per la verifica."""
import json, os, collections
from PIL import Image

ROOT = os.path.expanduser("~/Documents/GitHub/Red-Dust-Rebellion/godot/games/red_dust_rebellion")
CARDS = os.path.join(ROOT, "assets", "cards")
DATA = os.path.join(ROOT, "data")
SLOT_X = [147, 200, 252, 305]
HALF, HEIGHT = 8, 14


def is_grey(px, x, y):
    r, g, b = px.getpixel((x, y))
    return (max(r, g, b) - min(r, g, b) < 45) and 60 < (r + g + b) // 3 < 185


# Carte la cui riga dei simboli non si trova col criterio automatico: la fascia
# poco satura dell'illustrazione inganna la ricerca. Misurate a mano.
TOP_OVERRIDE = {}

# La carta 37 ha l'intestazione più alta e il riquadro sfiora l'icona nera delle
# Corporations, che al test del grigio passa per inchiostro. Letta a video e
# fissata qui: ⊘ sotto Red Dust e ⊘ sotto i Reclaimer, niente sulle altre due.
SYMBOL_OVERRIDE = {
    37: {"red_dust": "not_performed", "reclaimer": "not_performed"},
}


def symbol_top(img, number=0):
    """La riga dei simboli sta dove finiscono le icone colorate: si scende finché
    non si incontrano due righe di seguito senza pixel saturi."""
    if number in TOP_OVERRIDE:
        return TOP_OVERRIDE[number]
    px = img.convert("RGB")
    clean = 0
    for y in range(240, 285):
        colored = 0
        for x in range(130, 320, 2):
            r, g, b = px.getpixel((x, y))
            if max(r, g, b) - min(r, g, b) > 60:
                colored += 1
        if colored == 0:
            clean += 1
            if clean >= 2:
                return y - 1
        else:
            clean = 0
    return 254


def mask(img, top, x):
    px = img.convert("RGB")
    out = []
    for y in range(top, top + HEIGHT):
        for xx in range(x - HALF, x + HALF):
            out.append(1 if is_grey(px, xx, y) else 0)
    return out


W = 2 * HALF


def holes(m):
    """Pixel di fondo racchiusi dal simbolo.

    È il discriminante vero: il ⊘ è un anello e racchiude due sacche di fondo
    (sopra e sotto la sbarra), la ★ è piena e non ne racchiude nessuna. Contare
    i buchi è topologia, non somiglianza di forme: non risente di uno scarto di
    due pixel nell'allineamento, che è ciò che faceva sbagliare il confronto coi
    modelli.
    """
    h = len(m) // W
    seen = [False] * len(m)
    stack = []
    for x in range(W):
        for y in (0, h - 1):
            stack.append(y * W + x)
    for y in range(h):
        for x in (0, W - 1):
            stack.append(y * W + x)
    while stack:
        i = stack.pop()
        if i < 0 or i >= len(m) or seen[i] or m[i]:
            continue
        seen[i] = True
        x, y = i % W, i // W
        if x > 0: stack.append(i - 1)
        if x < W - 1: stack.append(i + 1)
        if y > 0: stack.append(i - W)
        if y < h - 1: stack.append(i + W)
    return sum(1 for i in range(len(m)) if not m[i] and not seen[i])


def classify_all():
    cards = {int(c["number"]): c for c in json.load(
        open(os.path.join(DATA, "cards.json"), encoding="utf-8"))["cards"]}
    rows = []
    for n in sorted(cards):
        path = os.path.join(CARDS, "%02d.jpg" % n)
        if not os.path.exists(path):
            continue
        img = Image.open(path)
        top = symbol_top(img, n)
        order = list(cards[n].get("faction_order", []))
        for i, x in enumerate(SLOT_X):
            if i >= len(order):
                continue
            m = mask(img, top, x)
            if sum(m) < 15:
                kind = "none"
            else:
                kind = "not_performed" if holes(m) >= 4 else "critical"
            if n in SYMBOL_OVERRIDE:
                kind = SYMBOL_OVERRIDE[n].get(order[i], "none")
            rows.append({"card": n, "faction": order[i], "slot": i, "kind": kind,
                         "patch": img.crop((x - HALF, top, x + HALF, top + HEIGHT))})
    return rows


def sheet(rows, path):
    Z, COLS = 5, 14
    PW, PH = 2 * HALF * Z, HEIGHT * Z
    blocks = []
    for kind in ("critical", "not_performed", "none"):
        items = [r for r in rows if r["kind"] == kind]
        blocks.append((kind, items))
    height = sum(((len(i) + COLS - 1) // COLS) * (PH + 6) + 26 for _, i in blocks)
    out = Image.new("RGB", (COLS * (PW + 6), height), "white")
    y = 0
    index = []
    for kind, items in blocks:
        index.append("=== %s (%d) ===" % (kind, len(items)))
        for k, r in enumerate(items):
            out.paste(r["patch"].resize((PW, PH), Image.NEAREST),
                      ((k % COLS) * (PW + 6), y + (k // COLS) * (PH + 6)))
            if k % COLS == 0:
                index.append("  riga %2d: %s" % (k // COLS, ""))
            index[-1] += "#%d/%s " % (r["card"], r["faction"][:2])
        y += ((len(items) + COLS - 1) // COLS) * (PH + 6) + 26
    out.save(path)
    return index


rows = classify_all()
idx = sheet(rows, "verify.png")
print("\n".join(idx))
print(collections.Counter(r["kind"] for r in rows))


def write_json(rows):
    out = collections.OrderedDict()
    for r in rows:
        out.setdefault(str(r["card"]), collections.OrderedDict())
        if r["kind"] != "none":
            out[str(r["card"])][r["faction"]] = r["kind"]
    doc = collections.OrderedDict()
    doc["_note"] = (
        "Simboli Non-Player stampati sotto le icone delle Fazioni sulle carte Evento "
        "(§8.5.5): `critical` = \u2605, l'Evento è Critico per quella Fazione; "
        "`not_performed` = \u2298, quella Fazione non lo esegue. Estratti dalle immagini "
        "del modulo Vassal contando i buchi racchiusi dal simbolo — il \u2298 è un anello "
        "e ne ha due, la \u2605 è piena e non ne ha — e poi VERIFICATI A VISTA tutti e 204, "
        "raggruppati per classe su un foglio di contatto. La carta 37 ha l'intestazione più "
        "alta e il riquadro sfiorava l'icona nera: è l'unica letta a mano. Le Fazioni "
        "assenti da una voce non hanno simbolo su quella carta."
    )
    doc["cards"] = out
    with open(os.path.join(DATA, "np_event_symbols.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("scritto np_event_symbols.json")


write_json(rows)
