# -*- coding: utf-8 -*-
"""出牌堆字形裁剪 + 自聚类 → 联系表。

堆框内：全框字形列聚簇（间距紧 merge_gap=6），逐簇找字形顶，
裁 [a-6,a+50]x[top,top+110] 归一化 (44,96)。
"""
import os
import json
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
OUT = os.path.join(ROOT, "phone_crops", "center")
DBG = os.path.join(ROOT, "debug_phone")
os.makedirs(OUT, exist_ok=True)
HAND_Y0 = 741
UI_BOXES = [(1619, 70, 102, 91), (2300, 273, 129, 129), (1592, 75, 129, 86)]
NORM = (44, 96)


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def glyph(bgr):
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    b = bgr[:, :, 0].astype(int)
    r = bgr[:, :, 2].astype(int)
    return (g < 150) | ((r - b > 70) & (r > 110))


def pile_boxes():
    boxes = []
    for fn in sorted(os.listdir(SAMPLES)):
        img = imread_cn(os.path.join(SAMPLES, fn))
        if img is None:
            continue
        wm = (img[:, :, 0] > 185) & (img[:, :, 1] > 185) & (img[:, :, 2] > 185)
        play = wm.copy()
        play[:150] = False
        play[HAND_Y0 - 6:] = False
        n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
        for i in range(1, n):
            x, y, w, h, a = stats[i]
            if w < 100 or h < 150:
                continue
            if any(abs(x - ux) < 8 and abs(y - uy) < 8 for ux, uy, uw, uh in UI_BOXES):
                continue
            boxes.append((fn, x, y, w, h))
    return boxes


def main():
    entries = []
    for fn, x, y, w, h in pile_boxes():
        img = imread_cn(os.path.join(SAMPLES, fn))
        crop_box = img[y:y + h, x:x + w]
        gm = glyph(crop_box)
        cols = gm[:int(0.55 * h)].sum(axis=0)   # 顶带聚簇（首行牌字母）
        on = cols > 2
        clusters = []
        start, gap = None, 0
        for xx, v in enumerate(on):
            if v:
                if start is None:
                    start = xx
                gap = 0
            elif start is not None:
                gap += 1
                if gap >= 6:
                    if xx - gap - start >= 15:
                        clusters.append((start, xx - gap))
                    start = None
        if start is not None and len(on) - 1 - start >= 15:
            clusters.append((start, len(on) - 1))
        for ci, (a, b) in enumerate(clusters):
            band = gm[:, max(0, a - 4):b + 5]
            rows = np.where(band.sum(axis=1) > 1)[0]
            if len(rows) == 0:
                continue
            top = int(rows[0])
            c = crop_box[max(0, top - 2):top + 108, max(0, a - 6):a + 50]
            if c.shape[0] < 60 or c.shape[1] < 30:
                continue
            name = f"{fn[:-4]}_b{x}_{y}_c{ci}"
            save_cn(os.path.join(OUT, name + ".png"), c)
            entries.append({"name": name, "shot": fn, "box": [x, y, w, h]})
    print(f"crops: {len(entries)}")

    feats = []
    for e in entries:
        im = imread_cn(os.path.join(OUT, e["name"] + ".png"))
        g = cv2.cvtColor(cv2.resize(im, NORM, interpolation=cv2.INTER_AREA),
                         cv2.COLOR_BGR2GRAY).astype(np.float32) / 255
        feats.append(g)
    n = len(feats)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    thr = 0.010
    for i in range(n):
        for j in range(i + 1, n):
            if float(np.mean((feats[i] - feats[j]) ** 2)) < thr:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[ri] = rj
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    order = sorted(groups.values(), key=lambda g: -len(g))
    print(f"clusters: {len(groups)}")

    cw, ch = NORM[0] * 2 + 12, NORM[1] * 2 + 36
    per_row = 12
    rows_n = (len(order) + per_row - 1) // per_row
    sheet = np.full((rows_n * ch, per_row * cw, 3), 235, np.uint8)
    for gi, grp in enumerate(order):
        r, c = divmod(gi, per_row)
        im = imread_cn(os.path.join(OUT, entries[grp[0]]["name"] + ".png"))
        big = cv2.resize(im, (NORM[0] * 2, NORM[1] * 2), interpolation=cv2.INTER_NEAREST)
        sheet[r * ch + 24:r * ch + 24 + big.shape[0], c * cw + 6:c * cw + 6 + big.shape[1]] = big
        cv2.putText(sheet, f"G{gi}#{len(grp)}", (c * cw + 4, r * ch + 16),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 200), 1)
    save_cn(os.path.join(DBG, "center_clusters_sheet.png"), sheet)
    with open(os.path.join(DBG, "center_clusters.json"), "w") as f:
        json.dump({f"G{gi}": [entries[k]["name"] for k in grp] for gi, grp in enumerate(order)}, f, indent=1)
    print("sheet + json saved")


if __name__ == "__main__":
    main()
