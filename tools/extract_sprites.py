# Usage (from the repo root): python3 tools/extract_sprites.py assets/players
"""Turn the two ChatGPT sheets into clean, recolourable game sprites.

Body: 5 direction panels x 8 animation rows -> one horizontal strip per
animation+direction, every pixel snapped to an exact key colour so a shader
can swap skin / shirt / shorts / socks per player.
Hair: 6 styles x 5 directions -> one image each, scaled to the body's head,
keyed green, with the head-centre anchor recorded.
"""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = sys.argv[1]
os.makedirs(f"{OUT}/body", exist_ok=True)
os.makedirs(f"{OUT}/hair", exist_ok=True)

ANIMS = ["idle", "run", "kick", "pass", "slide", "header", "fall", "celebrate"]
DIRS = ["s", "se", "e", "ne", "n"]          # down, down-right, right, up-right, up
HAIR = ["short", "long", "afro", "curly", "buzz", "ponytail"]

# Canonical key colours (light, dark) per region.
KEYS = {
    "skin":   ((255, 0, 255), (150, 0, 150)),
    "shirt":  ((255, 0, 0), (150, 0, 0)),
    "shorts": ((0, 0, 255), (0, 0, 150)),
    "socks":  ((255, 255, 0), (150, 150, 0)),
}
OUTLINE = (16, 14, 14)


def classify_body(px):
    """px: (...,4) int array -> (...,4) uint8 snapped image."""
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    out = np.zeros(px.shape[:-1] + (4,), np.uint8)
    solid = a >= 140
    bright = px[..., :3].max(-1)
    regions = {
        "skin": (r > 110) & (b > 100) & (g < 110) & (np.abs(r - b) < 90),
        "shirt": (r > 110) & (g < 90) & (b < 90),
        "shorts": (b > 100) & (r < 100) & (g < 100),
        "socks": (r > 120) & (g > 110) & (b < 110),
    }
    taken = np.zeros(r.shape, bool)
    for name, m in regions.items():
        m = m & solid & ~taken
        light, dark = KEYS[name]
        ref = px[..., :3][m].max(-1) if m.any() else None
        isdark = bright < 175
        out[m & ~isdark, :3] = light
        out[m & isdark, :3] = dark
        out[m, 3] = 255
        taken |= m
    outline = solid & ~taken & (bright < 95)
    out[outline, :3] = OUTLINE
    out[outline, 3] = 255
    return out


def keyed_mask(px):
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    solid = a >= 160
    return solid & (((r > 170) & (b > 150) & (g < 110)) | ((r > 170) & (g < 90) & (b < 90))
                    | ((b > 150) & (r < 100) & (g < 100)) | ((r > 170) & (g > 150) & (b < 110)))


def extract_body(path):
    px = np.array(Image.open(path).convert("RGBA")).astype(int)
    key = keyed_mask(px)
    grown = ndimage.binary_dilation(key, iterations=3)
    lab, n = ndimage.label(grown)
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(key, lab, range(1, n + 1))
    PX = [17, 312, 620, 918, 1224, 1530]
    RY = [78, 175, 280, 388, 500, 613, 738, 840, 945]
    cells = {}
    for i, (s, o) in enumerate(zip(sizes, objs)):
        if s <= 150:
            continue
        cy = (o[0].start + o[0].stop) / 2
        cx = (o[1].start + o[1].stop) / 2
        p = next(k for k in range(5) if PX[k] <= cx < PX[k + 1])
        row = next(k for k in range(8) if RY[k] <= cy < RY[k + 1])
        y0, y1, x0, x1 = o[0].start, o[0].stop, o[1].start, o[1].stop
        region = px[y0:y1, x0:x1]
        snapped = classify_body(region)
        # Keep only this figure's own pixels (component), drop ball and neighbours.
        own = lab[y0:y1, x0:x1] == i + 1
        snapped[~own] = 0
        # Drop stray outline specks not touching coloured pixels.
        coloured = snapped[..., 3] > 0
        lab2, n2 = ndimage.label(coloured)
        if n2 > 1:
            sz2 = ndimage.sum(coloured, lab2, range(1, n2 + 1))
            keep = np.isin(lab2, [j + 1 for j, v in enumerate(sz2) if v >= 25])
            snapped[~keep] = 0
        cells.setdefault((p, row), []).append((cx, snapped))
    frames = {}
    for (p, row), lst in cells.items():
        lst.sort(key=lambda t: t[0])
        frames[(DIRS[p], ANIMS[row])] = [im for _, im in lst]
    return frames


def anchor_of(im):
    """Feet anchor: x = torso (shirt) centre, y = lowest solid pixel."""
    a = im[..., 3] > 0
    ys, xs = np.nonzero(a)
    shirt = (im[..., 0] > 100) & (im[..., 1] == 0) & (im[..., 2] == 0)
    sx = np.nonzero(shirt)[1]
    ax = float(np.median(sx)) if len(sx) else float(xs.mean())
    return ax, float(ys.max())


def head_of(im):
    """Centre and width of the largest skin blob (the head)."""
    skin = (im[..., 0] > 100) & (im[..., 1] == 0) & (im[..., 2] > 100)
    lab, n = ndimage.label(skin)
    if n == 0:
        return None
    sz = ndimage.sum(skin, lab, range(1, n + 1))
    k = int(np.argmax(sz)) + 1
    ys, xs = np.nonzero(lab == k)
    return float(xs.mean()), float(ys.mean()), float(xs.max() - xs.min() + 1)


def main():
    frames = extract_body("assets/source/players_body.png")
    # Common cell for every frame so anchors line up.
    L = R = U = D = 0
    info = {}
    for key, lst in frames.items():
        for im in lst:
            ax, ay = anchor_of(im)
            h, w = im.shape[:2]
            L = max(L, ax); R = max(R, w - ax); U = max(U, ay); D = max(D, h - ay)
    half = int(np.ceil(max(L, R))) + 2
    W = 2 * half
    top = int(np.ceil(U)) + 2
    H = top + int(np.ceil(D)) + 2
    heads = {}
    for (dr, an), lst in frames.items():
        strip = np.zeros((H, W * len(lst), 4), np.uint8)
        hd = []
        for i, im in enumerate(lst):
            ax, ay = anchor_of(im)
            ox, oy = int(round(half - ax)), int(round(top - ay))
            h, w = im.shape[:2]
            cell = strip[:, i * W:(i + 1) * W]
            ys0, xs0 = max(0, oy), max(0, ox)
            ys1, xs1 = min(H, oy + h), min(W, ox + w)
            src = im[ys0 - oy:ys1 - oy, xs0 - ox:xs1 - ox]
            m = src[..., 3] > 0
            cell[ys0:ys1, xs0:xs1][m] = src[m]
            hh = head_of(cell)
            hd.append((round(hh[0] - half, 1), round(hh[1] - top, 1), round(hh[2], 1)) if hh else (0, -50, 14))
        Image.fromarray(strip).save(f"{OUT}/body/{an}_{dr}.png")
        heads[(an, dr)] = hd
    print("cell", W, H, "anchor", half, top)
    return W, H, half, top, heads, frames


def extract_hair(head_w):
    global HAIR
    px = np.array(Image.open("assets/source/players_hair.png").convert("RGBA")).astype(int)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    grn = (g > 120) & (r < 120) & (b < 120) & (g - r > 60)
    dark = (px[..., :3].max(-1) < 70)
    grown = ndimage.binary_dilation(grn, iterations=2)
    lab, n = ndimage.label(grown)
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(grn, lab, range(1, n + 1))
    PX = [13, 288, 613, 924, 1300, 1530]
    RY = [90, 226, 362, 502, 643, 782, 922]
    first = {}
    for i, (s, o) in enumerate(zip(sizes, objs)):
        if s <= 60:
            continue
        cy = (o[0].start + o[0].stop) / 2; cx = (o[1].start + o[1].stop) / 2
        p = next(k for k in range(5) if PX[k] <= cx < PX[k + 1])
        row = next(k for k in range(6) if RY[k] <= cy < RY[k + 1])
        if (p, row) not in first or cx < first[(p, row)][0]:
            first[(p, row)] = (cx, i, o)
    # Global scale: short hair (front) cap width -> body head width (+ outline).
    ref = first[(0, 0)][2]
    ref_w = (ref[1].stop - ref[1].start) - 4
    scale = (head_w + 4) / ref_w
    anchors = {}
    for (p, row), (cx, i, o) in first.items():
        y0, y1, x0, x1 = o[0].start, o[0].stop, o[1].start, o[1].stop
        own = lab[y0:y1, x0:x1] == i + 1
        g_ = grn[y0:y1, x0:x1] & own
        d_ = dark[y0:y1, x0:x1] & own & ndimage.binary_dilation(g_, iterations=2)
        img = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        bright = px[y0:y1, x0:x1, 1]
        img[g_ & (bright >= 190)] = (0, 255, 0, 255)
        img[g_ & (bright < 190)] = (0, 150, 0, 255)
        img[d_] = (*OUTLINE, 255)
        nw = max(1, int(round(img.shape[1] * scale))); nh = max(1, int(round(img.shape[0] * scale)))
        small = Image.fromarray(img).resize((nw, nh), Image.NEAREST)
        small.save(f"{OUT}/hair/{HAIR[row]}_{DIRS[p]}.png")
        # Head centre in the hair image: centre of the top cap, one head-radius down.
        sa = np.array(small)[..., 3] > 0
        ys, xs = np.nonzero(sa)
        topy = ys.min()
        capband = sa[topy:topy + max(2, int(head_w * 0.5))]
        cxs = np.nonzero(capband)[1]
        hx = float((cxs.min() + cxs.max()) / 2)
        hy = float(topy + head_w * 0.5 + 1)
        anchors[(HAIR[row], DIRS[p])] = (round(hx, 1), round(hy, 1), nw, nh)
    return anchors, scale


# Second hair sheet: rows mix facing directions, so views are picked by hand
# (panel, row, column). Back views missing from it reuse the closest first-sheet style.
HAIR2 = {
    "fringe": {"s": (0, 0, 0), "se": (0, 3, 0), "e": (0, 1, 0), "back_like": "short"},
    "long2": {"s": (1, 0, 0), "se": (1, 3, 0), "e": (1, 1, 0), "back_like": "long"},
    "afro2": {"s": (2, 0, 0), "se": (2, 3, 0), "e": (2, 1, 0), "n": (2, 0, 1), "back_like": "afro"},
    "curls": {"s": (3, 0, 0), "se": (3, 3, 0), "e": (3, 1, 0), "back_like": "curly"},
    "crop": {"s": (4, 0, 0), "se": (4, 3, 0), "e": (4, 1, 0), "back_like": "buzz"},
    "buns": {"s": (5, 0, 0), "se": (5, 3, 0), "e": (5, 1, 0), "back_like": "ponytail"},
}


def extract_hair2(scale, head_w, anchors):
    import shutil
    px = np.array(Image.open("assets/source/players_hair2.png").convert("RGBA")).astype(int)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    grn = (g > 120) & (r < 120) & (b < 120) & (g - r > 60)
    tie = (r > 180) & (g > 80) & (g < 190) & (b < 90)          # orange hair ties
    dark = (px[..., :3].max(-1) < 70)
    lab, n = ndimage.label(ndimage.binary_dilation(grn | tie, iterations=2))
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(grn, lab, range(1, n + 1))
    PX = [8, 280, 533, 770, 1018, 1268, 1530]
    RY = [65, 178, 288, 398, 510, 625, 738, 850, 955]
    cells = {}
    for i, (s_, o) in enumerate(zip(sizes, objs)):
        if s_ <= 60:
            continue
        cy = (o[0].start + o[0].stop) / 2; cx = (o[1].start + o[1].stop) / 2
        p = next(k for k in range(6) if PX[k] <= cx < PX[k + 1])
        row = next(k for k in range(8) if RY[k] <= cy < RY[k + 1])
        cells.setdefault((p, row), []).append((cx, i, o))
    for k in cells:
        cells[k].sort(key=lambda t: t[0])
    for style, picks in HAIR2.items():
        for dr in DIRS:
            if dr in picks:
                _, i, o = cells[(picks[dr][0], picks[dr][1])][picks[dr][2]]
                own = lab[o] == i + 1
                g_ = grn[o] & own
                t_ = tie[o] & own
                d_ = dark[o] & own & ndimage.binary_dilation(g_ | t_, iterations=2)
                img = np.zeros(own.shape + (4,), np.uint8)
                bright = px[o][..., 1]
                img[g_ & (bright >= 190)] = (0, 255, 0, 255)
                img[g_ & (bright < 190)] = (0, 150, 0, 255)
                img[t_] = (230, 120, 30, 255)   # ties keep their own colour
                img[d_] = (*OUTLINE, 255)
                nw = max(1, int(round(img.shape[1] * scale))); nh = max(1, int(round(img.shape[0] * scale)))
                small = Image.fromarray(img).resize((nw, nh), Image.NEAREST)
                small.save(f"{OUT}/hair/{style}_{dr}.png")
                sa = np.array(small)[..., 3] > 0
                ys, xs = np.nonzero(sa)
                topy = ys.min()
                cxs = np.nonzero(sa[topy:topy + max(2, int(head_w * 0.5))])[1]
                anchors[(style, dr)] = (round(float((cxs.min() + cxs.max()) / 2), 1), round(float(topy + head_w * 0.5 + 1), 1), nw, nh)
            else:
                src = picks["back_like"]
                shutil.copy(f"{OUT}/hair/{src}_{dr}.png", f"{OUT}/hair/{style}_{dr}.png")
                anchors[(style, dr)] = anchors[(src, dr)]


GK_ANIMS = ["gk_ready", "gk_dive_l", "gk_dive_r", "gk_catch", "gk_throw", "gk_punt"]


def extract_gk():
    """Goalkeeper sheet: same 5 directions, 6 animation rows. White gloves and
    the ball in his hands are kept as drawn (they aren't key colours)."""
    px = np.array(Image.open("assets/source/players_gk.png").convert("RGBA")).astype(int)
    key = keyed_mask(px)
    lab, n = ndimage.label(ndimage.binary_dilation(key, iterations=6))
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(key, lab, range(1, n + 1))
    PX = [12, 316, 618, 918, 1220, 1530]
    RY = [85, 228, 362, 505, 648, 800, 940]
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    white = (a >= 140) & (r > 190) & (g > 190) & (b > 190)
    cells = {}
    for i, (s_, o) in enumerate(zip(sizes, objs)):
        if s_ < 120:
            continue
        cy = (o[0].start + o[0].stop) / 2; cx = (o[1].start + o[1].stop) / 2
        p = next((k for k in range(5) if PX[k] <= cx < PX[k + 1]), None)
        row = next((k for k in range(6) if RY[k] <= cy < RY[k + 1]), None)
        if p is None or row is None:
            continue
        region = px[o]
        snapped = classify_body(region)
        own = lab[o] == i + 1
        w_ = white[o] & own
        snapped[w_] = (240, 240, 236, 255)
        snapped[~own] = 0
        coloured = snapped[..., 3] > 0
        lab2, n2 = ndimage.label(coloured)
        if n2 > 1:
            sz2 = ndimage.sum(coloured, lab2, range(1, n2 + 1))
            keep = np.isin(lab2, [j + 1 for j, v in enumerate(sz2) if v >= 25])
            snapped[~keep] = 0
        cells.setdefault((p, row), []).append((cx, snapped))
    frames = {}
    for (p, row), lst in cells.items():
        lst.sort(key=lambda t: t[0])
        frames[(DIRS[p], GK_ANIMS[row])] = [im for _, im in lst]
    # Own canvas: dives are wide.
    L = R = U = D = 0
    for lst in frames.values():
        for im in lst:
            ax, ay = anchor_of(im)
            h, w = im.shape[:2]
            L = max(L, ax); R = max(R, w - ax); U = max(U, ay); D = max(D, h - ay)
    half = int(np.ceil(max(L, R))) + 2
    W = 2 * half
    top = int(np.ceil(U)) + 2
    H = top + int(np.ceil(D)) + 2
    heads = {}
    for (dr, an), lst in frames.items():
        strip = np.zeros((H, W * len(lst), 4), np.uint8)
        hd = []
        for i, im in enumerate(lst):
            ax, ay = anchor_of(im)
            ox, oy = int(round(half - ax)), int(round(top - ay))
            h, w = im.shape[:2]
            cell = strip[:, i * W:(i + 1) * W]
            ys0, xs0 = max(0, oy), max(0, ox)
            ys1, xs1 = min(H, oy + h), min(W, ox + w)
            src = im[ys0 - oy:ys1 - oy, xs0 - ox:xs1 - ox]
            m = src[..., 3] > 0
            cell[ys0:ys1, xs0:xs1][m] = src[m]
            hh = head_of(cell)
            hd.append((round(hh[0] - half, 1), round(hh[1] - top, 1), round(hh[2], 1)) if hh else (0, -50, 14))
        Image.fromarray(strip).save(f"{OUT}/body/{an}_{dr}.png")
        heads[(an, dr)] = hd
    print("gk cell", W, H, "anchor", half, top)
    return W, H, half, top, heads


if __name__ == "__main__":
    W, H, half, top, heads, frames = main()
    GW, GH, ghalf, gtop, gheads = extract_gk()
    # Median front head width drives hair scale.
    widths = [h[2] for (an, dr), lst in heads.items() for h in lst if an == "idle"]
    head_w = float(np.median(widths))
    anchors, scale = extract_hair(head_w)
    extract_hair2(scale, head_w, anchors)
    HAIR = HAIR + list(HAIR2.keys())
    print("head_w", head_w, "hair scale", round(scale, 3))
    with open(f"{OUT}/../../scripts/sprite_data.gd", "w") as f:
        f.write("class_name SpriteData\n## Generated by tools/extract_sprites.py — do not edit by hand.\n\n")
        f.write(f"const CELL := Vector2i({W}, {H})\n")
        f.write(f"## Feet sit at this point inside every cell.\nconst ANCHOR := Vector2({half}, {top})\n")
        f.write(f"## Goalkeeper animations (gk_*) use their own, wider cell.\nconst GK_CELL := Vector2i({GW}, {GH})\nconst GK_ANCHOR := Vector2({ghalf}, {gtop})\n\n")
        f.write("const ANIMS := " + str(ANIMS).replace("'", '"') + "\n")
        f.write("const DIRS := " + str(DIRS).replace("'", '"') + "\n")
        f.write("const HAIR_STYLES := " + str(HAIR).replace("'", '"') + "\n\n")
        f.write("## Frame counts per animation and direction.\nconst FRAMES := {\n")
        heads.update(gheads)
        for (an, dr), lst in sorted(heads.items()):
            f.write(f'\t"{an}_{dr}": {len(lst)},\n')
        f.write("}\n\n## Head centre (relative to feet) and width, per frame.\nconst HEADS := {\n")
        for (an, dr), lst in sorted(heads.items()):
            f.write(f'\t"{an}_{dr}": [' + ", ".join(f"Vector3({x}, {y}, {w})" for x, y, w in lst) + "],\n")
        f.write("}\n\n## Hair image: head-centre point inside the image.\nconst HAIR_ANCHOR := {\n")
        for (st, dr), (hx, hy, nw, nh) in sorted(anchors.items()):
            f.write(f'\t"{st}_{dr}": Vector2({hx}, {hy}),\n')
        f.write("}\n")
