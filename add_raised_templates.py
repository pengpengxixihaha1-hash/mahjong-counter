# -*- coding: utf-8 -*-
"""把 f0012 的抬起牌裁剪（真身: 9♠×2 8♦ 7♠）补为模板变体（干净重裁，非烧录图）"""
import os

import cv2

from recognize_fiftyk import (BAND_TOP, HAND_SIZE, ROOT, classify,
                              find_glyph_clusters, imread_cn, load_templates,
                              save_cn, _raised_intervals, extract_hand)

frame = imread_cn(os.path.join(ROOT, "samples", "pc_20260926_004419",
                               "frame_0012_004449_502.png"))
gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
y_top = BAND_TOP
if float((gray[y_top, 100:1000] > 185).mean()) < 0.5:
    for y in range(400, 520):
        if float((gray[y, 100:1000] > 185).mean()) > 0.5:
            y_top = y
            break
col_card = (gray[y_top + 105: y_top + 145, :] > 175).mean(axis=0)
W = frame.shape[1]

TPLS = load_templates()
HAND_DIR = os.path.join(ROOT, "templates", "hand")

# Pass B 重裁：按 dump 输出的 (x, top) 定位
TARGETS = {(849, 414): "9S", (903, 414): "9S", (957, 449): "8D"}
for ra, rb, ct in _raised_intervals(frame, gray, col_card, y_top):
    d2 = (gray[ct + 40: ct + 95, ra:rb] < 125).sum(axis=0)
    for ca, cb in find_glyph_clusters(d2, merge_gap=14, max_w=70, split_at=40):
        a2 = ra + ca
        colband = gray[ct + 12: ct + 96, a2: ra + cb] < 125
        rowdark = colband.sum(axis=1)
        gtop = next((i for i, v in enumerate(rowdark) if v >= 3), None)
        top = min(max(ct + (gtop - 2 if gtop is not None else 0), ct - 25), ct + 40)
        x = max(0, a2 - 5)
        if (x, top) not in TARGETS:
            continue
        cls = TARGETS.pop((x, top))
        crop = frame[top + 9: top + 139, x: x + 42]
        n = 1
        while os.path.exists(os.path.join(HAND_DIR, f"{cls}_{n}.png")):
            n += 1
        save_cn(os.path.join(HAND_DIR, f"{cls}_{n}.png"), crop)
        print(f"已存 {cls}_{n}.png (x={x}, top={top})")

# 7♠: 从 extract_hand 的 7H 检出框直接取
import recognize_fiftyk as rf
rf.TPLS = load_templates()
hand = rf.extract_hand(frame, "", False)
for c, s, x, y, w, h in hand:
    if c == "7H":
        crop = frame[y: y + h, x: x + w]
        save_cn(os.path.join(HAND_DIR, "7S_1.png"), crop)
        print(f"已存 7S_1.png (x={x}, y={y}, score原={s:.2f})")

TPLS = load_templates()
crop9 = frame[414 + 9: 414 + 139, 849: 849 + 42]
print("复检 9♠:", classify(crop9, TPLS["hand"], HAND_SIZE)[:2])
