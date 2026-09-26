# -*- coding: utf-8 -*-
"""花色标签核对图：每个模板裁出花色符号区 4x 放大 + 文件名，供人工核对红桃/方片、黑桃/梅花"""
import os

import cv2
import numpy as np

from recognize_fiftyk import imread_cn, load_templates, save_cn, ROOT

TPLS = load_templates()
tiles = []
for key in ("center", "hand"):
    for cls, _img, tg, fn in sorted(TPLS[key], key=lambda t: (t[0], t[3])):
        img = imread_cn(os.path.join(ROOT, "templates", key, fn))
        size = img.shape[1], img.shape[0]
        h, w = img.shape[:2]
        suit = img[int(0.40 * h):int(0.88 * h), int(0.03 * w):int(0.62 * w)]
        big = cv2.resize(suit, (suit.shape[1] * 4, suit.shape[0] * 4), interpolation=cv2.INTER_NEAREST)
        cell_h = big.shape[0] + 26
        cell = np.full((cell_h, 120, 3), 255, np.uint8)
        x0 = (120 - big.shape[1]) // 2
        cell[26:, x0:x0 + big.shape[1]] = big
        color = (0, 0, 200) if cls[1] in "HD" else (0, 0, 0)
        cv2.putText(cell, fn.replace(".png", ""), (2, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.42, color, 1)
        tiles.append((key, cls, cell))

for key in ("center", "hand"):
    sub = [c for k, _c, c in [(kk, cc, cell) for kk, cc, cell in tiles] if False]  # placeholder
rows = []
cur = None
for key in ("center", "hand"):
    items = [t for t in tiles if t[0] == key]
    cols = 10
    for i in range(0, len(items), cols):
        row = items[i:i + cols]
        hmax = max(c.shape[0] for _, _, c in row)
        wsum = sum(c.shape[1] for _, _, c in row)
        canvas = np.full((hmax, wsum, 3), 255, np.uint8)
        x = 0
        for _, _, c in row:
            canvas[:c.shape[0], x:x + c.shape[1]] = c
            x += c.shape[1]
        rows.append(canvas)
    rows.append(np.full((20, rows[-1].shape[1], 3), 255, np.uint8))
W = max(r.shape[1] for r in rows)
H = sum(r.shape[0] for r in rows)
sheet = np.full((H, W, 3), 255, np.uint8)
y = 0
for r in rows:
    sheet[y:y + r.shape[0], :r.shape[1]] = r
    y += r.shape[0]
save_cn(os.path.join(ROOT, "check_suits.png"), sheet)
print("saved check_suits.png", sheet.shape, "templates:", len(tiles))
