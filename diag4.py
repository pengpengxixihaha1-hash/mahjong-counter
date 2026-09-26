# -*- coding: utf-8 -*-
"""x=822（真身5♠）被判 JK(0.99) 诊断：JK/5 系模板扫描"""
import cv2
import numpy as np
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
PAD = 14

fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0026_004530_042.png")
d = [t for t in rf.extract_hand(fr) if t[2] == 822][0]
crop = fr[d[3]:d[3] + d[5], d[2]:d[2] + d[4]]
c = cv2.resize(crop, rf.HAND_SIZE, interpolation=cv2.INTER_AREA)
gray_in = cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)
lh_in = rf._letter_h(gray_in)
inp = cv2.copyMakeBorder(gray_in, PAD, PAD, PAD, PAD, cv2.BORDER_REPLICATE).astype(np.float32)
print(f"x=822 det={d[0]}({d[1]:.2f}) letter_h={lh_in}")

for cls, _img, tg, fn, tlh in rf.TPLS["hand"]:
    if cls not in ("JK", "5S", "5C", "5H", "5D"):
        continue
    line = [f"{fn} tlh={tlh:.0f}:"]
    for r in (1.0, min(2.2, max(0.5, lh_in / tlh)) if tlh > 8 else None):
        if r is None:
            continue
        t = tg.astype(np.float32)
        if abs(r - 1.0) > 0.02:
            t = cv2.resize(tg, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
        th, tw = t.shape
        t_l = t[int(0.04*th):int(0.50*th), int(0.04*tw):int(0.70*tw)]
        t_s = t[int(0.42*th):int(0.88*th), int(0.04*tw):int(0.60*tw)]
        if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1]:
            line.append(f"r{r}:越界")
            continue
        s_l = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
        s_s = float(cv2.matchTemplate(inp, t_s, cv2.TM_CCOEFF_NORMED).max())
        line.append(f"r{r}: L{s_l:.3f}/S{s_s:.3f}")
    print("  ".join(line))

t = cv2.resize(crop, None, fx=4, fy=4, interpolation=cv2.INTER_NEAREST)
rf.save_cn("debug_822.png", t)
print("拼图: debug_822.png")
