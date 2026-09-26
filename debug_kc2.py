# -*- coding: utf-8 -*-
"""debug：x=901 crop（真K♣）对各 KC/KS 模板的 s_l/s_s 分数明细"""
import cv2
import numpy as np

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0323_010326_852.png")
crop = fr[187: 187 + 111, 901: 901 + 46]

size = rf.CTR_SIZE
crop2 = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
gray_in = cv2.cvtColor(crop2, cv2.COLOR_BGR2GRAY)
crop2, gray_in = rf._trim_top_band(crop2, gray_in)
print(f"输入 trim 后 shape={gray_in.shape} lh={rf._letter_h(gray_in)}")

pad = 14
inp = cv2.copyMakeBorder(gray_in, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)

for cls, _img, tg, fn, tlh in rf.TPLS["center"]:
    if cls not in ("KC", "KS"):
        continue
    best = (-1, -1, None)
    for r in rf.SCALE_LADDER:
        t = tg.astype(np.float32)
        if abs(r - 1.0) > 0.02:
            t = cv2.resize(tg, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
        th, tw = t.shape
        t_l = t[int(0.04 * th):int(0.50 * th), int(0.04 * tw):int(0.70 * tw)]
        t_s = t[int(0.42 * th):int(0.88 * th), int(0.04 * tw):int(0.60 * tw)]
        if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1]:
            continue
        s_l = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
        s_s = float(cv2.matchTemplate(inp, t_s, cv2.TM_CCOEFF_NORMED).max())
        if s_l > best[0]:
            best = (s_l, s_s, r)
    print(f"{fn}: s_l={best[0]:.3f} s_s={best[1]:.3f} scale={best[2]} tlh={tlh}")
