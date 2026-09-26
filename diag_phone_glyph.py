# -*- coding: utf-8 -*-
"""测量手机版字形几何：手牌字母带列聚簇、字母高度、出牌堆整框裁剪。"""
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
DBG = os.path.join(ROOT, "debug_phone")
HAND_Y0, HAND_Y1 = 741, 1055


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def glyph_mask(bgr):
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    b, gc, r = bgr[:, :, 0].astype(int), bgr[:, :, 1].astype(int), bgr[:, :, 2].astype(int)
    dark = g < 150
    red = (r - b > 70) & (r > 110)
    return dark | red, g


def letter_h(gray):
    h, w = gray.shape
    a, b = int(0.05 * w), int(0.55 * w)
    prof = (gray[:, a:b] < 150).sum(axis=1)
    y = 0
    while y < h // 3 and prof[y] >= (b - a) - 2:
        y += 1
    top = next((v for v in range(y, h) if prof[v] >= 3), None)
    if top is None:
        return 0.0, -1, -1
    y = top
    low = 0
    while y < h:
        if prof[y] >= 2:
            low = 0
        else:
            low += 1
            if low >= 5:
                break
        y += 1
    return float(y - low - top), top, y - low


for fn in ("shot_001.png", "shot_005.png"):
    img = imread_cn(os.path.join(SAMPLES, fn))
    gm, gray = glyph_mask(img)
    # 手牌字形带：试 y 750-880
    for band in ((750, 880), (760, 870)):
        cols = gm[band[0]:band[1]].sum(axis=0)
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
                if gap >= 10:
                    if x - gap - start >= 12:
                        clusters.append((start, x - gap))
                    start = None
        if start is not None:
            clusters.append((start, len(on) - 1))
        print(f"{fn} band={band} n_clusters={len(clusters)}")
        print("  clusters:", clusters[:30])
        if clusters:
            # 第一个簇裁剪保存 + 测字母高
            a, b = clusters[0]
            crop = img[HAND_Y0 - 20:HAND_Y0 + 200, a:b + 1]
            save_cn(os.path.join(DBG, f"handglyph_{fn[:-4]}_{a}.png"), crop)
            cg = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            lh, top, bot = letter_h(cg)
            print(f"  first cluster x={a}..{b} w={b-a+1} crop_h={crop.shape[0]} letter_h={lh} top={top} bot={bot}")

# 出牌堆整框（shot_005 七扇形 + shot_001 六对子）
img5 = imread_cn(os.path.join(SAMPLES, "shot_005.png"))
save_cn(os.path.join(DBG, "pile_shot005_7fan.png"), img5[261:261 + 314, 416:416 + 604])
img1 = imread_cn(os.path.join(SAMPLES, "shot_001.png"))
save_cn(os.path.join(DBG, "pile_shot001_6s.png"), img1[467:467 + 200, 1173:1173 + 210])
# 手牌前4张整体裁剪（含全高）
save_cn(os.path.join(DBG, "hand_shot005_left.png"), img5[741:1055, 60:560])
print("saved pile/hand crops")
