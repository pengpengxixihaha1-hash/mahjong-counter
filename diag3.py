# -*- coding: utf-8 -*-
"""尺度扫描实验：失效模板在问题裁剪上按多个 r 匹配，找可行尺度"""
import os
import cv2
import numpy as np
import recognize_fiftyk as rf

S = os.path.join("samples", "pc_20260926_004419")
PAD = 14
SCALES = [0.7, 0.85, 1.0, 1.15, 1.3, 1.6, 1.9, 2.2]


def zones(t):
    th, tw = t.shape
    return (t[int(0.04*th):int(0.50*th), int(0.04*tw):int(0.70*tw)],
            t[int(0.42*th):int(0.88*th), int(0.04*tw):int(0.60*tw)])


def sweep(crop, size, tpls_dir, fns):
    c = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    gray_in = cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)
    inp = cv2.copyMakeBorder(gray_in, PAD, PAD, PAD, PAD, cv2.BORDER_REPLICATE).astype(np.float32)
    for fn in fns:
        img = rf.imread_cn(os.path.join(tpls_dir, fn))
        if img is None:
            print(f"  {fn}: 缺失")
            continue
        g = cv2.cvtColor(cv2.resize(img, size, interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
        line = [f"  {fn}:"]
        for r in SCALES:
            t = g.astype(np.float32)
            if abs(r - 1.0) > 0.02:
                t = cv2.resize(g, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
            t_l, t_s = zones(t)
            if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1] or \
               t_s.shape[0] >= inp.shape[0] or t_s.shape[1] >= inp.shape[1]:
                line.append(f"r{r}:越界")
                continue
            s_l = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
            s_s = float(cv2.matchTemplate(inp, t_s, cv2.TM_CCOEFF_NORMED).max())
            line.append(f"r{r}: L{s_l:.3f}/S{s_s:.3f}")
        print("  ".join(line))


rf.TPLS = rf.load_templates()
fr = rf.imread_cn(os.path.join(S, "frame_0477_011303_813.png"))
cd = rf.extract_center(fr)
crop9 = None
for d in cd:
    if d[2] == 543:
        crop9 = fr[d[3]:d[3]+d[5], d[2]:d[2]+d[4]]
print("== 中央 x=543（真身9♦）与 9 系模板 ==")
sweep(crop9, rf.CTR_SIZE, rf.CTR_TPL_DIR, ["9D_1.png", "9D_2.png", "9C_1.png", "9C_2.png", "9H_1.png", "9H_2.png", "9S_1.png"])

hd = rf.extract_hand(fr)
cropT = None
for d in hd:
    if d[2] == 523:
        cropT = fr[d[3]:d[3]+d[5], d[2]:d[2]+d[4]]
print("== 手牌 x=523（真身10♠）与 T 系模板 ==")
sweep(cropT, rf.HAND_SIZE, rf.HAND_TPL_DIR, ["TS_1.png", "TC_1.png", "TD_1.png", "TH_1.png"])
