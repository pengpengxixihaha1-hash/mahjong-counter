# -*- coding: utf-8 -*-
"""肖像簇确认：回到源帧裁宽上下文，看人头牌完整牌面（含角标）"""
import glob
import os

import cv2
import numpy as np

from recognize_fiftyk import imread_cn, save_cn

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "pc_20260926_004419")

# (簇号, 帧号, x, y)
ITEMS = [
    (2, 7, 505, 110),
    (3, 1, 179, 71),
    (7, 5, 179, 109),
    (10, 98, 830, 109),
    (20, 78, 541, 42),
    (75, 48, 830, 109),
    (94, 6, 554, 92),
    (131, 235, 106, 108),
]

tiles = []
for cid, fi, x, y in ITEMS:
    fs = glob.glob(os.path.join(SAMPLES, f"frame_{fi:04d}_*.png"))
    if not fs:
        print(f"cluster {cid}: frame {fi} not found")
        continue
    frame = imread_cn(fs[0])
    ctx = frame[max(0, y - 50): y + 300, max(0, x - 70): min(frame.shape[1], x + 230)]
    ctx = cv2.resize(ctx, (ctx.shape[1] * 2, ctx.shape[0] * 2), interpolation=cv2.INTER_NEAREST)
    cv2.putText(ctx, f"C{cid} f{fi} x{x} y{y}", (10, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
    tiles.append(ctx)

h = max(t.shape[0] for t in tiles)
w = max(t.shape[1] for t in tiles)
sheet = np.zeros((h * 2 + 60, w * 4 + 100, 3), np.uint8)
for i, t in enumerate(tiles):
    r, c = divmod(i, 4)
    sheet[r * (h + 20): r * (h + 20) + t.shape[0],
          c * (w + 20): c * (w + 20) + t.shape[1]] = t
save_cn(os.path.join(ROOT, "portrait_context.png"), sheet)
print("saved portrait_context.png", sheet.shape)
