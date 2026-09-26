# -*- coding: utf-8 -*-
"""手牌裁剪 + 自聚类 → 联系表（供人工标注）。

几何（2556x1179）：
  手牌带 y 741-1055；字母带 y 746-798（字母顶 747 起，pip 顶 ~815 不入带）
  每张牌裁剪 x=[a-10,a+70] y=[741,955]，归一化 (56,150)
"""
import os
import json
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
OUT = os.path.join(ROOT, "phone_crops", "hand")
DBG = os.path.join(ROOT, "debug_phone")
os.makedirs(OUT, exist_ok=True)
os.makedirs(DBG, exist_ok=True)

HAND_Y0 = 741
BAND = (746, 798)          # 字母带
CROP = (-10, 70, 0, 214)   # 相对字母簇左端的裁剪偏移 (dx0, dx1, dy0, dy1)
NORM = (56, 150)


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def glyph_cols(img):
    """列 → 字母带内是否有字形像素（暗或红）。"""
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    b = img[:, :, 0].astype(int)
    r = img[:, :, 2].astype(int)
    dark = g < 150
    red = (r - b > 70) & (r > 110)
    band = (dark | red)[BAND[0]:BAND[1]]
    return band.sum(axis=0), dark, red


def find_clusters(img):
    cols, _, _ = glyph_cols(img)
    on = cols > 2
    clusters = []
    start, gap = None, 0
    for x, v in enumerate(on):
        if v:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= 12:
                if x - gap - start >= 20:
                    clusters.append((start, x - gap))
                start = None
    if start is not None and len(on) - 1 - start >= 20:
        clusters.append((start, len(on) - 1))
    return clusters


def norm_crop(crop):
    return cv2.resize(crop, NORM, interpolation=cv2.INTER_AREA)


def main():
    entries = []   # (name, shot, x, norm_img)
    for fn in sorted(os.listdir(SAMPLES)):
        if not fn.endswith(".png"):
            continue
        img = imread_cn(os.path.join(SAMPLES, fn))
        if img is None:
            continue
        clusters = find_clusters(img)
        kept = [(a, b) for a, b in clusters if 120 <= a and b <= 2440]
        for i, (a, b) in enumerate(kept):
            x0 = max(0, a + CROP[0])
            x1 = min(img.shape[1], a + CROP[1])
            y0 = HAND_Y0 + CROP[2]
            y1 = HAND_Y0 + CROP[3]
            crop = img[y0:y1, x0:x1]
            if crop.shape[0] < 200 or crop.shape[1] < 60:
                continue
            name = f"{fn[:-4]}_c{i:02d}_x{a}"
            save_cn(os.path.join(OUT, name + ".png"), crop)
            entries.append({"name": name, "shot": fn, "x": a, "w": b - a + 1})
    print(f"total crops: {len(entries)}")

    # 自聚类：小图灰度 L2，union-find
    feats = []
    for e in entries:
        p = os.path.join(OUT, e["name"] + ".png")
        im = imread_cn(p)
        g = cv2.cvtColor(norm_crop(im), cv2.COLOR_BGR2GRAY).astype(np.float32) / 255
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
            d = float(np.mean((feats[i] - feats[j]) ** 2))
            if d < thr:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[ri] = rj
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    print(f"clusters: {len(groups)}")

    # 联系表：每簇代表 + 计数，网格铺开
    order = sorted(groups.values(), key=lambda g: -len(g))
    cell_w, cell_h = NORM[0] * 2 + 14, NORM[1] * 2 + 40
    cols_n = 10
    rows_n = (len(order) + cols_n - 1) // cols_n
    sheet = np.full((rows_n * cell_h, cols_n * cell_w, 3), 235, np.uint8)
    for gi, grp in enumerate(order):
        r, c = divmod(gi, cols_n)
        rep = entries[grp[0]]
        im = imread_cn(os.path.join(OUT, rep["name"] + ".png"))
        big = cv2.resize(im, (NORM[0] * 2, NORM[1] * 2), interpolation=cv2.INTER_NEAREST)
        y, x = r * cell_h + 30, c * cell_w + 7
        sheet[y:y + big.shape[0], x:x + big.shape[1]] = big
        cv2.putText(sheet, f"G{gi}#{len(grp)}", (c * cell_w + 6, r * cell_h + 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 200), 2)
        cv2.putText(sheet, rep["shot"][5:9], (c * cell_w + 6, r * cell_h + 36),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 80, 0), 1)
    save_cn(os.path.join(DBG, "hand_clusters_sheet.png"), sheet)
    with open(os.path.join(DBG, "hand_clusters.json"), "w") as f:
        json.dump({f"G{gi}": [entries[k]["name"] for k in grp] for gi, grp in enumerate(order)}, f, indent=1)
    print("sheet + json saved")


if __name__ == "__main__":
    main()
