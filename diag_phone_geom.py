# -*- coding: utf-8 -*-
"""手机截图几何探针：测手牌区 y 带、牌左边缘、字形带、中央白牌组件框。"""
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
DBG = os.path.join(ROOT, "debug_phone")
os.makedirs(DBG, exist_ok=True)


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def white_mask(bgr):
    return (bgr[:, :, 0] > 185) & (bgr[:, :, 1] > 185) & (bgr[:, :, 2] > 185)


def hand_band(white):
    """底部手牌带：行白占比>0.35 的连续段（取最靠下的长段）。"""
    frac = white.mean(axis=1)
    rows = frac > 0.35
    bands = []
    y = 0
    H = len(rows)
    while y < H:
        if rows[y]:
            y0 = y
            while y < H and rows[y]:
                y += 1
            bands.append((y0, y - 1))
        else:
            y += 1
    bands = [b for b in bands if b[1] - b[0] > 60]
    return bands[-1] if bands else None


def card_lefts(white, y0, y1):
    """手牌带内逐列白占比，找牌顶行附近的列分段（左边缘阶跃）。"""
    band = white[y0:y1 + 1]
    colw = band.mean(axis=0)
    return colw


for fn in sorted(os.listdir(SAMPLES)):
    img = imread_cn(os.path.join(SAMPLES, fn))
    H, W = img.shape[:2]
    wm = white_mask(img)
    hb = hand_band(wm)
    if hb is None:
        print(f"{fn} {W}x{H} hand_band=None")
        continue
    y0, y1 = hb
    # 中央区（顶栏以下、手牌带以上）白组件
    play = wm.copy()
    play[:int(0.06 * H)] = False
    play[y0 - 6:] = False
    n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
    boxes = []
    for i in range(1, n):
        x, y, w, h, a = stats[i]
        if w > 55 and h > 80:
            boxes.append((int(x), int(y), int(w), int(h)))
    boxes.sort()
    print(f"{fn} {W}x{H} hand_band={hb} play_boxes={boxes}")

# 调试标注图：第一张与中间一张
for fn in ("shot_001.png", "shot_005.png", "shot_010.png"):
    img = imread_cn(os.path.join(SAMPLES, fn))
    wm = white_mask(img)
    hb = hand_band(wm)
    if hb is None:
        continue
    y0, y1 = hb
    play = wm.copy()
    play[:int(0.06 * img.shape[0])] = False
    play[y0 - 6:] = False
    n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
    vis = img.copy()
    cv2.rectangle(vis, (0, y0), (img.shape[1] - 1, y1), (0, 0, 255), 6)
    for i in range(1, n):
        x, y, w, h, a = stats[i]
        if w > 55 and h > 80:
            cv2.rectangle(vis, (x, y), (x + w, y + h), (0, 255, 0), 4)
    small = cv2.resize(vis, (1024, int(1024 * img.shape[0] / img.shape[1])))
    savep = os.path.join(DBG, "geom_" + fn)
    ok, buf = cv2.imencode(".png", small)
    if ok:
        buf.tofile(savep)
print("debug images saved to", DBG)
