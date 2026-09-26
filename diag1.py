# -*- coding: utf-8 -*-
"""诊断：f0026 手牌 6 系列候选裁剪（补 6C/6D 模板）+ f0477 两处跨色误判中间值"""
import os
import cv2
import numpy as np
import recognize_fiftyk as rf

S = os.path.join("samples", "pc_20260926_004419")


def crop_of(frame, d):
    _, _, x, y, w, h = d
    return frame[y:y + h, x:x + w]


def color_prior(crop, size):
    c = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)
    H, W = gray.shape
    f16 = c.astype(np.int16)
    zone = np.zeros((H, W), bool)
    zone[int(0.05 * H):int(0.85 * H), int(0.05 * W):int(0.62 * W)] = True
    dark = (gray < 160) & zone
    red = ((f16[:, :, 2] - f16[:, :, 0]) > 70) & (f16[:, :, 2] > 110) & zone
    n = int(dark.sum())
    ratio = float(red.sum()) / max(1, n)
    return n, ratio


def layer_scores(crop, tpls, size, prefix):
    c = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    gray_in = cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)
    lh_in = rf._letter_h(gray_in)
    pad = 14
    inp = cv2.copyMakeBorder(gray_in, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)
    res = {}
    for cls, _img, tg, fn, tlh in tpls:
        if not cls.startswith(prefix):
            continue
        t = tg.astype(np.float32)
        if lh_in > 8 and tlh > 8:
            r = min(2.2, max(0.5, lh_in / tlh))
            if abs(r - 1.0) > 0.05:
                t = cv2.resize(tg, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
        th, tw = t.shape
        t_l = t[int(0.04 * th):int(0.50 * th), int(0.04 * tw):int(0.70 * tw)]
        t_s = t[int(0.42 * th):int(0.88 * th), int(0.04 * tw):int(0.60 * tw)]
        if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1] or \
           t_s.shape[0] >= inp.shape[0] or t_s.shape[1] >= inp.shape[1]:
            continue
        s_l = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
        s_s = float(cv2.matchTemplate(inp, t_s, cv2.TM_CCOEFF_NORMED).max())
        d = res.setdefault(cls, [-1.0, -1.0])
        d[0] = max(d[0], s_l)
        d[1] = max(d[1], s_s)
    return res, lh_in


def row_montage(crops, labels, scale, path):
    tiles = []
    for c, lb in zip(crops, labels):
        t = cv2.resize(c, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
        t = cv2.copyMakeBorder(t, 22, 4, 4, 4, cv2.BORDER_CONSTANT, value=(30, 30, 30))
        cv2.putText(t, lb, (6, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 255), 1)
        tiles.append(t)
    w = sum(t.shape[1] for t in tiles)
    h = max(t.shape[0] for t in tiles)
    m = np.zeros((h, w, 3), np.uint8)
    x = 0
    for t in tiles:
        m[:t.shape[0], x:x + t.shape[1]] = t
        x += t.shape[1]
    rf.save_cn(path, m)
    print("拼图:", path)


rf.TPLS = rf.load_templates()

# ---- 1) f0026 手牌：6 系列候选
fr = rf.imread_cn(os.path.join(S, "frame_0026_004530_042.png"))
dets = rf.extract_hand(fr)
print("== f0026 手牌 ==")
for d in sorted(dets, key=lambda t: t[2]):
    print(f"  {d[0]}({d[1]:.2f}) x={d[2]} y={d[3]}")
six = sorted([d for d in dets if d[0].startswith("6")], key=lambda t: t[2])
row_montage([crop_of(fr, d) for d in six],
            [f"{i}:x{d[2]} {d[1]:.2f}" for i, d in enumerate(six)],
            2.0, "debug_6s.png")

# ---- 2) f0477 中央 9 系列 + 手牌 T 系列
fr2 = rf.imread_cn(os.path.join(S, "frame_0477_011303_813.png"))
cd = rf.extract_center(fr2)
tgt = [d for d in cd if d[0] == "9S" and d[1] < 0.95]
for d in tgt:
    c = crop_of(fr2, d)
    n, ratio = color_prior(c, rf.CTR_SIZE)
    res, lh = layer_scores(c, rf.TPLS["center"], rf.CTR_SIZE, "9")
    print(f"== 中央 {d[0]}({d[1]:.2f}) x={d[2]} letter_h={lh} dark={n} red_ratio={ratio:.2f}")
    for cls, v in sorted(res.items(), key=lambda kv: -kv[1][0]):
        print(f"   {cls}: s_l={v[0]:.3f} s_s={v[1]:.3f}")
row_montage([c], [f"x{d[2]}"], 4.0, f"debug_diag9_{d[2]}.png")

hd = rf.extract_hand(fr2)
tgt = [d for d in hd if d[0] == "TD"]
for d in tgt:
    c = crop_of(fr2, d)
    n, ratio = color_prior(c, rf.HAND_SIZE)
    res, lh = layer_scores(c, rf.TPLS["hand"], rf.HAND_SIZE, "T")
    print(f"== 手牌 {d[0]}({d[1]:.2f}) x={d[2]} letter_h={lh} dark={n} red_ratio={ratio:.2f}")
    for cls, v in sorted(res.items(), key=lambda kv: -kv[1][0]):
        print(f"   {cls}: s_l={v[0]:.3f} s_s={v[1]:.3f}")
row_montage([c], [f"x{d[2]}"], 4.0, f"debug_diagT_{d[2]}.png")
