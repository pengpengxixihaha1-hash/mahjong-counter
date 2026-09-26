# -*- coding: utf-8 -*-
"""手牌模板全量拼图（3×），供花色错标核对"""
import os
import cv2
import numpy as np
import recognize_fiftyk as rf

tiles = []
for fn in sorted(os.listdir(rf.HAND_TPL_DIR)):
    if not fn.endswith(".png"):
        continue
    img = rf.imread_cn(os.path.join(rf.HAND_TPL_DIR, fn))
    if img is None:
        continue
    t = cv2.resize(img, None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
    t = cv2.copyMakeBorder(t, 20, 4, 4, 4, cv2.BORDER_CONSTANT, value=(40, 40, 40))
    cv2.putText(t, fn[:-4], (4, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 255, 255), 1)
    tiles.append(t)
per = 12
tw = max(t.shape[1] for t in tiles)
th = max(t.shape[0] for t in tiles)
rows = []
for i in range(0, len(tiles), per):
    row = tiles[i:i + per]
    m = np.zeros((th, sum(t.shape[1] for t in row) + 4 * len(row), 3), np.uint8)
    x = 0
    for t in row:
        m[:t.shape[0], x:x + t.shape[1]] = t
        x += t.shape[1] + 4
    rows.append(m)
w = max(r.shape[1] for r in rows)
m = np.zeros((sum(r.shape[0] + 4 for r in rows), w, 3), np.uint8)
y = 0
for r in rows:
    m[y:y + r.shape[0], :r.shape[1]] = r
    y += r.shape[0] + 4
rf.save_cn("check_hand_tpls.png", m)
print(f"共 {len(tiles)} 张模板 -> check_hand_tpls.png")
