# -*- coding: utf-8 -*-
"""出牌堆联系表：所有截图的中央白牌框 1:1 拼图。"""
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(ROOT, "samples", "iphone")
DBG = os.path.join(ROOT, "debug_phone")
HAND_Y0 = 741
UI_BOXES = [(1619, 70, 102, 91), (2300, 273, 129, 129)]


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def white_mask(bgr):
    return (bgr[:, :, 0] > 185) & (bgr[:, :, 1] > 185) & (bgr[:, :, 2] > 185)


cells = []
for fn in sorted(os.listdir(SAMPLES)):
    img = imread_cn(os.path.join(SAMPLES, fn))
    wm = white_mask(img)
    play = wm.copy()
    play[:150] = False
    play[HAND_Y0 - 6:] = False
    n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
    for i in range(1, n):
        x, y, w, h, a = stats[i]
        if w < 55 or h < 80:
            continue
        if any(abs(x - ux) < 8 and abs(y - uy) < 8 for ux, uy, uw, uh in UI_BOXES):
            continue
        cells.append((fn, x, y, w, h))

print(f"{len(cells)} pile boxes")
cell_h = 230
sheet_rows = []
for fn, x, y, w, h in cells:
    img = imread_cn(os.path.join(SAMPLES, fn))
    crop = img[y:y + h, x:x + w]
    canvas = np.full((cell_h, max(w, 160), 3), 225, np.uint8)
    cv2.rectangle(canvas, (0, 0), (canvas.shape[1] - 1, canvas.shape[0] - 1), (180, 180, 180), 1)
    ch = min(h, cell_h)
    canvas[0:ch, 0:w] = crop[0:ch]
    cv2.putText(canvas, f"{fn[5:9]} {x},{y} {w}x{h}", (3, cell_h - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 200), 1)
    sheet_rows.append(canvas)

# 横向拼接，每行最多6格
per_row = 6
rows = []
for i in range(0, len(sheet_rows), per_row):
    row = sheet_rows[i:i + per_row]
    W = sum(c.shape[1] + 4 for c in row)
    canvas = np.full((cell_h, W, 3), 225, np.uint8)
    xx = 0
    for c in row:
        canvas[:, xx:xx + c.shape[1]] = c
        xx += c.shape[1] + 4
    rows.append(canvas)
W = max(r.shape[1] for r in rows)
H = sum(r.shape[0] + 4 for r in rows)
sheet = np.full((H, W, 3), 225, np.uint8)
yy = 0
for r in rows:
    sheet[yy:yy + r.shape[0], 0:r.shape[1]] = r
    yy += r.shape[0] + 4
save_cn(os.path.join(DBG, "center_boxes_sheet.png"), sheet)
print("saved center_boxes_sheet.png")
