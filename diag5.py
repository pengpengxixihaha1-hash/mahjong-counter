# -*- coding: utf-8 -*-
"""可疑模板 6× 放大核对：K/Q 系 + 7H_2/JK_1/5H_1"""
import os
import cv2
import numpy as np
import recognize_fiftyk as rf

names = ["KD_1", "KD_2", "KH_1", "KS_1", "KS_2",
         "QC_1", "QD_1", "QH_1", "QH_2", "QS_1",
         "JK_1", "7H_2", "5H_1", "TS_1"]
tiles = []
for n in names:
    p = os.path.join(rf.HAND_TPL_DIR, n + ".png")
    img = rf.imread_cn(p)
    if img is None:
        print("缺失", n)
        continue
    t = cv2.resize(img, None, fx=6, fy=6, interpolation=cv2.INTER_NEAREST)
    t = cv2.copyMakeBorder(t, 26, 6, 6, 6, cv2.BORDER_CONSTANT, value=(40, 40, 40))
    cv2.putText(t, n, (6, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
    tiles.append(t)
per = 7
th = max(t.shape[0] for t in tiles)
rows = []
for i in range(0, len(tiles), per):
    row = tiles[i:i + per]
    m = np.zeros((th, sum(t.shape[1] for t in row) + 6 * len(row), 3), np.uint8)
    x = 0
    for t in row:
        m[:t.shape[0], x:x + t.shape[1]] = t
        x += t.shape[1] + 6
    rows.append(m)
w = max(r.shape[1] for r in rows)
m = np.zeros((sum(r.shape[0] + 6 for r in rows), w, 3), np.uint8)
y = 0
for r in rows:
    m[y:y + r.shape[0], :r.shape[1]] = r
    y += r.shape[0] + 6
rf.save_cn("debug_sus.png", m)
print("拼图: debug_sus.png", len(tiles), "张")
