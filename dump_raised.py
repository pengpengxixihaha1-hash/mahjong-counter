# -*- coding: utf-8 -*-
"""导出指定帧的 Pass B 抬起牌裁剪 + 分类分数（用于补对齐变体模板）
用法: python dump_raised.py <帧路径> <输出前缀>
"""
import os
import sys

import cv2
import numpy as np

from recognize_fiftyk import (BAND_TOP, HAND_SIZE, ROOT, classify,
                              find_glyph_clusters, imread_cn, load_templates,
                              save_cn, _raised_intervals)

frame_path = sys.argv[1]
prefix = sys.argv[2] if len(sys.argv) > 2 else "raise"
TPLS = load_templates()

frame = imread_cn(frame_path)
gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
y_top = BAND_TOP
if float((gray[y_top, 100:1000] > 185).mean()) < 0.5:
    for y in range(400, 520):
        if float((gray[y, 100:1000] > 185).mean()) > 0.5:
            y_top = y
            break
col_card = (gray[y_top + 105: y_top + 145, :] > 175).mean(axis=0)
W = frame.shape[1]

outdir = os.path.join(ROOT, "raise_check")
os.makedirs(outdir, exist_ok=True)
k = 0
for ra, rb, ct in _raised_intervals(frame, gray, col_card, y_top):
    d2 = (gray[ct + 40: ct + 95, ra:rb] < 125).sum(axis=0)
    for ca, cb in find_glyph_clusters(d2, merge_gap=14, max_w=70, split_at=40):
        a2 = ra + ca
        colband = gray[ct + 12: ct + 96, a2: ra + cb] < 125
        rowdark = colband.sum(axis=1)
        gtop = next((i for i, v in enumerate(rowdark) if v >= 3), None)
        top = min(max(ct + (gtop - 2 if gtop is not None else 0), ct - 25), ct + 40)
        x = max(0, a2 - 5)
        if x + 42 > W:
            continue
        crop = frame[top + 9: top + 139, x: x + 42]
        if crop.shape[1] < 42 or crop.shape[0] < 130:
            continue
        cls, score, fn = classify(crop, TPLS["hand"], HAND_SIZE)
        big = cv2.resize(crop, (84, 260), interpolation=cv2.INTER_NEAREST)
        cv2.putText(big, f"{k} {cls} {score:.2f} ct{ct} x{x} t{top}", (4, 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
        save_cn(os.path.join(outdir, f"{prefix}_{k}_ct{ct}_x{x}_t{top}.png"), big)
        print(f"{k}: ct={ct} x={x} top={top} -> {cls} {score:.2f} ({fn})")
        k += 1
print(f"共 {k} 张 -> {outdir}")
