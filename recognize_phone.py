# -*- coding: utf-8 -*-
"""微乐五十K 记牌器 · 手机截图版识别（牌点-only，不分花色）

几何（2556x1179）：
  手牌带 y741-1055，字母带 y746-798，牌裁剪 [a-10,a+70]x[741,955] → (56,150)
  中央白框 y150..735（排除头像/气泡），框内顶带聚簇 → [a-6,a+50]x[top-2,top+108] → (44,96)
  牌点类别：3 4 5 6 7 8 9 T J Q K A 2 JK（两副牌每点8张，JK 4张）

用法：
  python recognize_phone.py                # 全部截图逐帧统计
  python recognize_phone.py --image xx.png # 单帧
"""
import argparse
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
HAND_TPL = os.path.join(ROOT, "templates_phone", "hand")
CTR_TPL = os.path.join(ROOT, "templates_phone", "center")
SAMPLES = os.path.join(ROOT, "samples", "iphone")
DBG = os.path.join(ROOT, "debug_phone")

HAND_NORM = (56, 150)
CTR_NORM = (44, 96)
HAND_Y0, HAND_Y1 = 741, 1055
BAND = (746, 798)
HAND_X = (120, 2440)
PLAY_Y = (150, 735)
UI_BOXES = [(1619, 70, 102, 91), (2300, 273, 129, 129), (1592, 75, 129, 86)]
LADDER = (0.5, 0.6, 0.75, 0.9, 1.0, 1.15, 1.3)
HAND_LADDER = LADDER      # --device 时改 (1.0,)
CTR_LADDER = LADDER
HAND_ACCEPT = 0.60
CTR_ACCEPT = 0.55
RANKS = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2", "JK"]
BASE = {r: (4 if r == "JK" else 8) for r in RANKS}
RANK_CN = {"T": "10", "JK": "王"}


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def load_templates(d, size):
    tpls = []
    if not os.path.isdir(d):
        return tpls
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".png"):
            continue
        cls = fn.split("_")[0]
        img = imread_cn(os.path.join(d, fn))
        if img is None:
            continue
        g = cv2.cvtColor(cv2.resize(img, size, interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
        tpls.append((cls, g.astype(np.float32), fn))
    return tpls


def glyph_mask(bgr):
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    b = bgr[:, :, 0].astype(int)
    r = bgr[:, :, 2].astype(int)
    return (g < 150) | ((r - b > 70) & (r > 110))


def clusters_from(cols_on, merge_gap, min_w, split_w=0, split_at=0):
    out = []
    start, gap = None, 0
    n = len(cols_on)
    for x, v in enumerate(cols_on):
        if v:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= merge_gap:
                if x - gap - start >= min_w:
                    out.append((start, x - gap))
                start = None
    if start is not None and n - 1 - start >= min_w:
        out.append((start, n - 1))
    if split_w:
        res = []
        for a, b in out:
            w = b - a
            if w > split_w:
                k = max(2, round(w / split_at))
                step = w / k
                for j in range(k):
                    res.append((int(a + j * step), int(a + (j + 1) * step)))
            else:
                res.append((a, b))
        out = res
    return out


def classify(crop, tpls, size, accept, min_lh, pad=10, scale_stats=None, winner_stats=None,
             ladder=None):
    """归一化 + 边缘补边平移搜索 NCC，牌点-only 取全类最高分。"""
    lad = ladder or LADDER
    crop = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    h, w = g.shape
    prof = (g[:, int(0.1 * w):int(0.7 * w)] < 150).sum(axis=1)
    lh = 0
    for y in range(h):
        if prof[y] >= 3:
            lh += 1
        elif lh and prof[y] == 0:
            break
    if lh < min_lh:
        return "?", -1.0
    inp = cv2.copyMakeBorder(g, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)
    best_cls, best_s, best_sc, best_fn = "?", -1.0, 1.0, ""
    for cls, tg, fn in tpls:
        for sc in lad:
            t = tg if abs(sc - 1.0) < 0.02 else cv2.resize(tg, None, fx=sc, fy=sc, interpolation=cv2.INTER_AREA)
            th, tw = t.shape
            if th >= inp.shape[0] or tw >= inp.shape[1]:
                continue
            s = float(cv2.matchTemplate(inp, t, cv2.TM_CCOEFF_NORMED).max())
            if s > best_s:
                best_cls, best_s, best_sc, best_fn = cls, s, sc, fn
    if scale_stats is not None and best_cls != "?":
        scale_stats[best_sc] = scale_stats.get(best_sc, 0) + 1
    if winner_stats is not None and best_cls != "?":
        winner_stats[best_fn] = winner_stats.get(best_fn, 0) + 1
    if best_s < accept:
        return "?", best_s
    return best_cls, best_s


def extract_hand(img, tpls, pad=10, scale_stats=None, winner_stats=None, ladder=None):
    gm = glyph_mask(img)
    cols = gm[BAND[0]:BAND[1]].sum(axis=0)
    cl = clusters_from(cols > 2, merge_gap=12, min_w=20)
    out = []
    for a, b in cl:
        if not (HAND_X[0] <= a and b <= HAND_X[1]):
            continue
        crop = img[HAND_Y0:HAND_Y0 + 214, max(0, a - 10):a + 70]
        if crop.shape[1] < 60:
            continue
        cls, s = classify(crop, tpls, HAND_NORM, HAND_ACCEPT, 30 * HAND_NORM[1] // 150, pad=pad,
                          scale_stats=scale_stats, winner_stats=winner_stats, ladder=ladder)
        out.append((cls, s, a))
    return out


def extract_center(img, tpls, pad=10, scale_stats=None, winner_stats=None):
    wm = (img[:, :, 0] > 185) & (img[:, :, 1] > 185) & (img[:, :, 2] > 185)
    play = wm.copy()
    play[:PLAY_Y[0]] = False
    play[PLAY_Y[1]:] = False
    n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
    out = []
    for i in range(1, n):
        x, y, w, h, _a = stats[i]
        if w < 100 or h < 150:
            continue
        if any(abs(x - ux) < 8 and abs(y - uy) < 8 for ux, uy, _uw, _uh in UI_BOXES):
            continue
        box = img[y:y + h, x:x + w]
        gmb = glyph_mask(box)
        cols = gmb[:int(0.55 * h)].sum(axis=0)
        cl = clusters_from(cols > 2, merge_gap=6, min_w=15, split_w=58, split_at=56)
        for a, b in cl:
            sub = gmb[:, max(0, a - 4):b + 5]
            rows = np.where(sub.sum(axis=1) > 1)[0]
            if not len(rows):
                continue
            top = int(rows[0])
            crop = box[max(0, top - 2):top + 108, max(0, a - 6):a + 50]
            if crop.shape[0] < 60 or crop.shape[1] < 30:
                continue
            cls, s = classify(crop, tpls, CTR_NORM, CTR_ACCEPT, max(6, 12 * CTR_NORM[1] // 96), pad=pad,
                              scale_stats=scale_stats, winner_stats=winner_stats)
            out.append((cls, s, x + a, y + top))
    return out


def extract_center(img, tpls, pad=10, scale_stats=None, winner_stats=None, ladder=None,
                   avg_tpls=None):
    """avg_tpls 给定时走真机两级匹配：avg 全阶梯选 top-3 候选牌点（各记其最优
    尺度），再用候选牌点的全量模板在其 ±1 尺度邻域精配。"""
    wm = (img[:, :, 0] > 185) & (img[:, :, 1] > 185) & (img[:, :, 2] > 185)
    play = wm.copy()
    play[:PLAY_Y[0]] = False
    play[PLAY_Y[1]:] = False
    n, lab, stats, _ = cv2.connectedComponentsWithStats(play.astype(np.uint8), 8)
    out = []
    lad = ladder or LADDER
    for i in range(1, n):
        x, y, w, h, _a = stats[i]
        if w < 100 or h < 150:
            continue
        if any(abs(x - ux) < 8 and abs(y - uy) < 8 for ux, uy, _uw, _uh in UI_BOXES):
            continue
        box = img[y:y + h, x:x + w]
        gmb = glyph_mask(box)
        cols = gmb[:int(0.55 * h)].sum(axis=0)
        cl = clusters_from(cols > 2, merge_gap=6, min_w=15, split_w=58, split_at=56)
        for a, b in cl:
            sub = gmb[:, max(0, a - 4):b + 5]
            rows = np.where(sub.sum(axis=1) > 1)[0]
            if not len(rows):
                continue
            top = int(rows[0])
            crop = box[max(0, top - 2):top + 108, max(0, a - 6):a + 50]
            if crop.shape[0] < 60 or crop.shape[1] < 30:
                continue
            if avg_tpls is None:
                cls, s = classify(crop, tpls, CTR_NORM, CTR_ACCEPT,
                                  max(6, 12 * CTR_NORM[1] // 96), pad=pad,
                                  scale_stats=scale_stats, winner_stats=winner_stats,
                                  ladder=ladder)
            else:
                cls, s = classify_two_stage(crop, avg_tpls, tpls, CTR_NORM, CTR_ACCEPT,
                                            max(6, 12 * CTR_NORM[1] // 96), pad=pad, lad=lad)
            out.append((cls, s, x + a, y + top))
    return out


def classify_two_stage(crop, avg_tpls, full_tpls, size, accept, min_lh, pad=10, lad=None):
    """阶段1 avg 模板全阶梯出牌点候选与最优尺度；阶段2 候选牌点全量模板在
    其 ±1 尺度邻域精配。返回 (cls, score)，语义与 classify() 对齐。"""
    lad = lad or LADDER
    crop_r = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(crop_r, cv2.COLOR_BGR2GRAY)
    h, w = g.shape
    prof = (g[:, int(0.1 * w):int(0.7 * w)] < 150).sum(axis=1)
    lh = 0
    for y in range(h):
        if prof[y] >= 3:
            lh += 1
        elif lh and prof[y] == 0:
            break
    if lh < min_lh:
        return "?", -1.0
    inp = cv2.copyMakeBorder(g, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)

    def ncc(tg, sc):
        t = tg if abs(sc - 1.0) < 0.02 else cv2.resize(
            tg, None, fx=sc, fy=sc, interpolation=cv2.INTER_AREA)
        th, tw = t.shape
        if th >= inp.shape[0] or tw >= inp.shape[1]:
            return -1.0
        return float(cv2.matchTemplate(inp, t, cv2.TM_CCOEFF_NORMED).max())

    per_rank = {}
    for cls, tg, _fn in avg_tpls:
        b, bsc = -1.0, 1.0
        for sc in lad:
            s = ncc(tg, sc)
            if s > b:
                b, bsc = s, sc
        if b > per_rank.get(cls, (-2.0, 1.0))[0]:
            per_rank[cls] = (b, bsc)
    top3 = sorted(per_rank, key=lambda k: per_rank[k][0], reverse=True)[:3]
    best_cls, best_s = "?", -1.0
    for rank in top3:
        i0 = lad.index(per_rank[rank][1])
        sub = lad[max(0, i0 - 1):min(len(lad), i0 + 2)]
        for cls, tg, _fn in full_tpls:
            if cls != rank:
                continue
            for sc in sub:
                s = ncc(tg, sc)
                if s > best_s:
                    best_cls, best_s = cls, s
    if best_s < accept:
        return "?", best_s
    return best_cls, best_s


def report(img, pad=10, scale_stats=None, winner_stats=None, ctr_avg_tpls=None,
           hand_ladder=None, ctr_ladder=None):
    hand = extract_hand(img, TPLS_HAND, pad=pad, scale_stats=scale_stats,
                        winner_stats=winner_stats if not isinstance(winner_stats, tuple) else winner_stats[0],
                        ladder=hand_ladder)
    ctr = extract_center(img, TPLS_CTR, pad=pad,
                         scale_stats=scale_stats,
                         winner_stats=winner_stats[1] if isinstance(winner_stats, tuple) else winner_stats,
                         ladder=ctr_ladder, avg_tpls=ctr_avg_tpls)
    hc = {}
    for cls, s, _x in hand:
        if cls != "?":
            hc[cls] = hc.get(cls, 0) + 1
    cc = {}
    for cls, s, _x, _y in ctr:
        if cls != "?":
            cc[cls] = cc.get(cls, 0) + 1
    total = sum(hc.values()) + sum(cc.values())
    over = [r for r in RANKS if hc.get(r, 0) + cc.get(r, 0) > BASE[r]]
    return hand, ctr, hc, cc, total, over


def fmt(counts):
    return " ".join(f"{RANK_CN.get(r, r)}x{c}" for r, c in sorted(counts.items(), key=lambda kv: RANKS.index(kv[0])))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", default="")
    ap.add_argument("--avg", action="store_true", help="用 templates_phone_avg 平均模板")
    ap.add_argument("--hand-tpl", default="", help="覆盖手牌模板目录")
    ap.add_argument("--center-tpl", default="", help="覆盖中央模板目录")
    ap.add_argument("--winners", default="", help="把每 crop 获胜模板文件名计数写到 JSON")
    ap.add_argument("--pad", type=int, default=10, help="NCC 平移搜索半径（归一化空间 px）")
    ap.add_argument("--half", action="store_true",
                    help="归一化减半 (28x75/22x48)——已验证退化，仅存档")
    ap.add_argument("--device", action="store_true",
                    help="模拟真机参数：手牌=平均模板+单尺度；中央=两级匹配")
    ap.add_argument("--stats", action="store_true", help="打印最优尺度直方图")
    args = ap.parse_args()
    if args.half:
        HAND_NORM = (28, 75)
        CTR_NORM = (22, 48)
    CTR_AVG = None
    if args.device:
        TPLS_HAND = load_templates(os.path.join(ROOT, "templates_phone_avg", "hand"), HAND_NORM)
        TPLS_CTR = load_templates(CTR_TPL, CTR_NORM)
        CTR_AVG = load_templates(os.path.join(ROOT, "templates_phone_avg", "center"), CTR_NORM)
        HAND_LADDER = (1.0,)
    else:
        hand_dir = args.hand_tpl or (os.path.join(ROOT, "templates_phone_avg", "hand") if args.avg else HAND_TPL)
        ctr_dir = args.center_tpl or (os.path.join(ROOT, "templates_phone_avg", "center") if args.avg else CTR_TPL)
        TPLS_HAND = load_templates(hand_dir, HAND_NORM)
        TPLS_CTR = load_templates(ctr_dir, CTR_NORM)
    STATS = {} if args.stats else None
    WIN_H = {} if args.winners else None
    WIN_C = {} if args.winners else None
    files = [args.image] if args.image else sorted(
        os.path.join(SAMPLES, f) for f in os.listdir(SAMPLES) if f.endswith(".png"))
    for p in files:
        img = imread_cn(p)
        if img is None:
            continue
        hand, ctr, hc, cc, total, over = report(img, pad=args.pad, scale_stats=STATS,
                                                winner_stats=(WIN_H, WIN_C) if WIN_H else None,
                                                ctr_avg_tpls=CTR_AVG,
                                                hand_ladder=HAND_LADDER)
        bad_h = sum(1 for c, s, _ in hand if c == "?")
        bad_c = sum(1 for c, s, _x, _y in ctr if c == "?")
        flag = " OVER!" if over else ""
        print(f"{os.path.basename(p)}: hand={len(hand)-bad_h}({bad_h}?) ctr={len(ctr)-bad_c}({bad_c}?) total={total}{flag}")
        print(f"  手牌: {fmt(hc)}")
        print(f"  中央: {fmt(cc)}")
        if over:
            print(f"  超基数: {over}")
    if STATS:
        print("尺度直方图:", dict(sorted(STATS.items())))
    if WIN_H is not None:
        import json
        with open(args.winners, "w", encoding="utf-8") as f:
            json.dump({"hand": WIN_H, "center": WIN_C}, f, ensure_ascii=False, indent=1)
        print(f"获胜模板计数 → {args.winners}")
