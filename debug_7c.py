# -*- coding: utf-8 -*-
"""debug：frame_0164 中央检出全表 + 7 系检出对 7C/7S/7H 模板分数"""
import cv2
import numpy as np

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0164_005508_496.png")
dets = rf.extract_center(fr)
for d in dets:
    print(f"{d[0]}({'*' if d[6]=='star' else ''}{d[1]:.2f}) x={d[2]} y={d[3]}")

# 对 7 系检出逐一打印 7C/7S/7H/7D 模板分数
print("\n--- 7 系检出分数明细 ---")
for d in dets:
    if d[0] not in ("7S", "7H", "7C", "7D"):
        continue
    crop = fr[d[3]: d[3] + d[5], d[2]: d[2] + d[4]]
    size = rf.CTR_SIZE
    c2 = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(c2, cv2.COLOR_BGR2GRAY)
    c2, g = rf._trim_top_band(c2, g)
    pad = 14
    inp = cv2.copyMakeBorder(g, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)
    line = []
    for cls, _img, tg, fn, tlh in rf.TPLS["center"]:
        if cls not in ("7C", "7S", "7H", "7D"):
            continue
        best = -1.0
        for r in rf.SCALE_LADDER:
            t = tg.astype(np.float32)
            if abs(r - 1.0) > 0.02:
                t = cv2.resize(tg, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
            th, tw = t.shape
            t_l = t[int(0.04 * th):int(0.50 * th), int(0.04 * tw):int(0.70 * tw)]
            if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1]:
                continue
            s = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
            best = max(best, s)
        line.append(f"{fn}:{best:.3f}")
    print(f"x={d[2]} {d[0]}({d[1]:.2f}): " + "  ".join(line))
