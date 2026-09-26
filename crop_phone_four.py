# -*- coding: utf-8 -*-
"""补采 shot_004 出牌堆的 4：严格顶带 y467..535 聚簇，避免与下行 J 并簇。"""
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
OUT = os.path.join(ROOT, "phone_crops", "center")


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


img = imread_cn(os.path.join(SAMPLES, "shot_004.png"))
x, y, w, h = 1009, 467, 538, 200
box = img[y:y + h, x:x + w]
g = cv2.cvtColor(box, cv2.COLOR_BGR2GRAY)
b = box[:, :, 0].astype(int)
r = box[:, :, 2].astype(int)
gm = (g < 150) | ((r - b > 70) & (r > 110))
cols = gm[0:68].sum(axis=0)   # 4 的字母行
on = cols > 1
clusters = []
start, gap = None, 0
for xx, v in enumerate(on):
    if v:
        if start is None:
            start = xx
        gap = 0
    elif start is not None:
        gap += 1
        if gap >= 5:
            if xx - gap - start >= 12:
                clusters.append((start, xx - gap))
            start = None
if start is not None:
    clusters.append((start, len(on) - 1))
print("clusters:", clusters)
n = 0
for a, bb in clusters:
    sub = gm[:, max(0, a - 4):bb + 5]
    rows = np.where(sub.sum(axis=1) > 1)[0]
    if not len(rows):
        continue
    top = int(rows[0])
    c = box[max(0, top - 2):top + 108, max(0, a - 6):a + 50]
    if c.shape[0] < 60 or c.shape[1] < 30:
        continue
    save_cn(os.path.join(OUT, f"shot_004_four_{n}.png"), c)
    print(f"saved four_{n} top={top} a={a}")
    n += 1
