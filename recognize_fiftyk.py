# -*- coding: utf-8 -*-
"""
微乐五十K 记牌器 · 识别与牌账（PC 样本验证版）

管线：整帧 → 手牌区/中央出牌区 → 字形锚定切牌 → 归一化 NCC 分类 → 牌账累积
牌账：两副牌 108 张 = 54 类 × 2（王 JK ×4）；已见 = 当前手牌 + 累计中央出牌；
      剩余 = 基数 − 已见；5/10/K 为分牌。

用法：
  python recognize_fiftyk.py --image samples\\xxx\\frame_0100_xxx.png     # 单帧调试（出标注图）
  python recognize_fiftyk.py --dir samples\\pc_20260926_004419            # 整目录回放统计
  python recognize_fiftyk.py --dir ... --save-unknown                     # 保存低置信度裁剪供补标注
"""
import argparse
import os
from collections import Counter

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
HAND_TPL_DIR = os.path.join(ROOT, "templates", "hand")
CTR_TPL_DIR = os.path.join(ROOT, "templates", "center")
UNKNOWN_DIR = os.path.join(ROOT, "templates", "unknown")

HAND_SIZE = (42, 130)   # 手牌角标归一化尺寸
CTR_SIZE = (46, 111)    # 中央牌角标归一化尺寸
BAND_TOP = 453          # 手牌区牌顶 y（1162x697 窗口）
TABLE_Y = (100, 448)    # 中央出牌区 y 范围
ACCEPT = 0.60           # 分类置信度阈值（手牌）
CTR_ACCEPT = 0.75       # 中央区计数阈值：真牌最低~0.79（星标），人像残条最高~0.61
SCALE_LADDER = (0.8, 0.9, 1.0, 1.1, 1.25, 1.4)   # 模板匹配尺度阶梯

RANKS = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2", "JK"]
SUITS = ["S", "H", "C", "D"]
SUIT_CN = {"S": "黑", "H": "红", "C": "梅", "D": "方"}
SCORED = {"5", "T", "K"}   # 分牌
BASE = {r: (4 if r == "JK" else 2) for r in RANKS}  # 每类张数（2副牌）


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def _letter_h(gray):
    """牌点字母的行高（顶部首个连续暗行段），用于匹配前的尺度归一。

    阈值 150 与断口容忍 5：细笔画字干（5/J 的竖笔）抗锯齿后灰度偏高且
    中段可能淡于 125，旧参数会截断成 9px 导致尺度比率错乱（5C_1 事故）。
    另需跳过顶部全宽暗行带：扇形裁剪常把相邻牌的深色边框带进 crop 顶部
    （5C_1 顶部 10 行 23/23 全暗），不跳过会把暗边当字形起点。
    """
    h, w = gray.shape
    a, b = int(0.05 * w), int(0.55 * w)
    prof = (gray[:, a:b] < 150).sum(axis=1)
    y = 0
    while y < h // 3 and prof[y] >= (b - a) - 2:   # 顶部全宽暗边带
        y += 1
    top = next((v for v in range(y, h) if prof[v] >= 3), None)
    if top is None:
        return 0.0
    y = top
    low = 0
    while y < h:
        if prof[y] >= 2:
            low = 0
        else:
            low += 1
            if low >= 5:
                break
        y += 1
    return float(y - low - top)


def _trim_top_band(img, gray):
    """裁掉顶部全宽暗行带（扇形裁剪带入的相邻牌深色边框）。

    这些行进了字母区会压死 NCC（5C_1 天花板 0.75 的根因），也会让
    letter_h 把暗边当字形。仅裁全宽（≥win-2 列暗）连续带，字形顶横
    笔只有约六成宽不会误裁。
    """
    h, w = gray.shape
    a, b = int(0.05 * w), int(0.55 * w)
    win = b - a
    prof = (gray[:, a:b] < 150).sum(axis=1)
    k = 0
    while k < h // 3 and prof[k] >= win - 2:
        k += 1
    if k:
        return img[k:], gray[k:]
    return img, gray


def load_templates():
    tpls = {"hand": [], "center": []}
    for key, d, size in (("hand", HAND_TPL_DIR, HAND_SIZE), ("center", CTR_TPL_DIR, CTR_SIZE)):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".png"):
                continue
            cls = fn.rsplit("_", 1)[0]
            img = imread_cn(os.path.join(d, fn))
            if img is None:
                continue
            img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            img, gray = _trim_top_band(img, gray)
            img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            tpls[key].append((cls, img, gray, fn, _letter_h(gray)))
    return tpls


def classify(crop, tpls, size, min_lh=8):
    """裁剪 → 尺度归一 + 平移搜索匹配（matchTemplate NCC）；同类取最大分。

    中央出牌扇形间距 ~36px，且不同出牌张数下牌面渲染尺度不同（字母高可差
    1.5 倍以上），逐模板缩放后在 ±14px 补边内平移搜索。letter_h 对细笔画
    字尾（9/6）易截断误测，故尺度取候选集 {1.0, lh_in/tlh} 双试取优。
    花色颜色先验：牌点字母与花色颜色跟随花色，字形区红像素占暗像素比例
    判定红/黑，与候选类不符则重罚分，消除跨色误配（9♥→9S、J♦→JS 等）。
    min_lh：牌点字母最小行高，低于此判碎片不入账。手牌裁剪恒含字形带
    用 8；中央区红 J 字干细淡易误判碎片（真 J 被过滤），禁用（0）——
    人像残条由 CTR_ACCEPT 与无匹配模板自然挡住。
    """
    crop = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    gray_in = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    crop, gray_in = _trim_top_band(crop, gray_in)
    lh_in = _letter_h(gray_in)
    if lh_in <= min_lh:
        return ("?", -1.0, "frag")   # 无牌点字母：人像/边缘残条，不入账
    pad = 14
    inp = cv2.copyMakeBorder(gray_in, pad, pad, pad, pad, cv2.BORDER_REPLICATE).astype(np.float32)
    H, W = gray_in.shape
    f16 = crop.astype(np.int16)
    zone = np.zeros((H, W), bool)
    zone[int(0.05 * H):int(0.85 * H), int(0.05 * W):int(0.62 * W)] = True
    # 橙色（伙章/星标）：排除出颜色先验，避免徽章把黑牌误判红
    orange = ((f16[:, :, 2] > 180) & (f16[:, :, 1] > 80) & (f16[:, :, 1] < 190) &
              (f16[:, :, 0] < 110) & zone)
    dark = (gray_in < 160) & zone & ~orange
    red = ((f16[:, :, 2] - f16[:, :, 0]) > 70) & (f16[:, :, 2] > 110) & zone & ~orange
    is_red = is_black = False
    if int(dark.sum()) >= 40:
        ratio = float(red.sum()) / max(1, int(dark.sum()))
        is_red, is_black = ratio > 0.40, ratio < 0.15
    # 星标：橙★替换花色 pip（pip 区 y0.42-0.78），徽章在 y~0.85 下方不触发
    pzone = zone.copy()
    pzone[:int(0.42 * H), :] = False
    pzone[int(0.78 * H):, :] = False
    orange_p = ((f16[:, :, 2] > 180) & (f16[:, :, 1] > 80) & (f16[:, :, 1] < 190) &
                (f16[:, :, 0] < 110) & pzone)
    star = float(orange_p.sum()) / (H * W) > 0.02
    per_cls = {}
    for cls, _img, tg, fn, tlh in tpls:
        # 固定尺度阶梯：中央牌面渲染尺度随张数变化，lh 比率易被字形/pip
        # 连带测量稀释（5C_1 事故），阶梯全覆盖让 NCC 自己选最优尺度
        for r in SCALE_LADDER:
            t = tg.astype(np.float32)
            if abs(r - 1.0) > 0.02:
                t = cv2.resize(tg, None, fx=r, fy=r, interpolation=cv2.INTER_AREA).astype(np.float32)
            th, tw = t.shape
            # 分层匹配：字母区定牌点，花色区定花色（同牌点类字母区同分，花色形状决胜）
            t_l = t[int(0.04 * th):int(0.50 * th), int(0.04 * tw):int(0.70 * tw)]
            t_s = t[int(0.42 * th):int(0.88 * th), int(0.04 * tw):int(0.60 * tw)]
            if t_l.shape[0] >= inp.shape[0] or t_l.shape[1] >= inp.shape[1] or \
               t_s.shape[0] >= inp.shape[0] or t_s.shape[1] >= inp.shape[1]:
                continue
            s_l = float(cv2.matchTemplate(inp, t_l, cv2.TM_CCOEFF_NORMED).max())
            s_s = float(cv2.matchTemplate(inp, t_s, cv2.TM_CCOEFF_NORMED).max())
            d = per_cls.setdefault(cls, [-1.0, -1.0])
            if s_l > d[0]:
                d[0], d[1] = s_l, s_s
    if not per_cls:
        return ("?", -1.0, "")
    # 第一层：牌点（字母区分最高者，容同牌点各类）
    best_l = max(v[0] for v in per_cls.values())
    pool = {c: v for c, v in per_cls.items() if v[0] >= best_l - 0.06}

    def suit_score(c):
        ss = pool[c][1]
        if is_red and c[1] in "SC":
            return ss - 0.50
        if is_black and c[1] in "HD":
            return ss - 0.50
        return ss

    # 第二层：花色（含红/黑先验罚分）
    cls = max(pool, key=suit_score)
    s = 0.5 * pool[cls][0] + 0.5 * suit_score(cls)
    return (cls, s, "star" if star else "")


def find_glyph_clusters(band_dark, merge_gap=8, max_w=60, split_at=38):
    cols = band_dark > 2
    clusters = []
    start, gap = None, 0
    for x, v in enumerate(cols):
        if v:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= merge_gap:
                clusters.append((start, x - gap))
                start = None
    if start is not None:
        clusters.append((start, len(cols) - 1))
    out = []
    for a, b in clusters:
        w = b - a
        if w < 10:
            continue
        if w > max_w:
            k = max(2, round(w / split_at))
            step = w / k
            for j in range(k):
                out.append((int(a + j * step), int(a + (j + 1) * step)))
        else:
            out.append((a, b))
    return out


def detect_card_top(gray, a, b, y_top):
    """检测列范围 a:b 的手牌牌顶 y。

    从 y_top-90 向下找首个 12 行白运行；若候选顶与 y_top 之间存在 ≥3 行绿缝
    （行白占比 <0.2），说明锁住的是上方中央出牌区白牌，跳过继续向下找。
    """
    y0 = max(280, y_top - 90)
    strip = gray[y0: y_top + 40, a:b]
    if strip.size == 0:
        return y_top
    wr = (strip > 175).mean(axis=1)
    n = len(wr)
    end_all = min(n, y_top - y0 + 1)   # 候选顶到 y_top 行（含）
    i = 0
    while i < n - 12:
        if wr[i:i + 12].mean() > 0.75:
            bad, ok = 0, True
            for j in range(i, end_all):
                bad = bad + 1 if wr[j] < 0.2 else 0
                if bad >= 3:
                    ok = False
                    break
            if ok:
                return y0 + i
            i += 12   # 中央牌假顶：整块跳过
        else:
            i += 1
    return y_top


def extract_hand(frame, tag="", save_unknown=False):
    """底部手牌区 → [(cls, score, x, y, w, h)]

    Pass A: 常规牌 —— 字形带(y_top+40..95)聚簇，detect_card_top 自适应牌顶
    Pass B: 抬起牌 —— 逐列中性白从 y_top-8 向上走（穿字形暗隙）得 run_top，
            牌顶范围 [y_top-80, y_top-6] 为抬起列；区间内 ct=run_top 最大值
            （徽章/按钮必叠于牌上方，取最深者即真牌顶），字形带聚簇逐张裁剪
    """
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    y_top = BAND_TOP
    if float((gray[y_top, 100:1000] > 185).mean()) < 0.5:  # 自适应修正牌顶
        for y in range(400, 520):
            if float((gray[y, 100:1000] > 185).mean()) > 0.5:
                y_top = y
                break
    col_card = (gray[y_top + 105: y_top + 145, :] > 175).mean(axis=0)
    W = frame.shape[1]

    def crop_classify(x, card_top, key):
        crop = frame[card_top + 9: card_top + 139, x: x + 42]
        if crop.shape[1] < 42 or crop.shape[0] < 130:
            return None
        cls, score, flag = classify(crop, TPLS["hand"], HAND_SIZE)
        if score < ACCEPT and save_unknown and tag:
            save_cn(os.path.join(UNKNOWN_DIR, f"{tag}_{key}.png"), crop)
        return (cls, score, x, card_top + 9, 42, 130, flag)

    # ---- Pass B 先行：抬起牌列区间，其 x 范围在 Pass A 中跳过
    raised = _raised_intervals(frame, gray, col_card, y_top)
    raised_mask = np.zeros(W, bool)
    for ra, rb, _ in raised:
        raised_mask[ra:rb] = True

    out = []
    # ---- Pass A：常规牌
    dark = (gray[y_top + 40: y_top + 95, :] < 125).sum(axis=0)
    clusters = find_glyph_clusters(dark, merge_gap=14, max_w=70, split_at=40)
    for a0, b0 in clusters:
        a, b = a0, b0
        while a < b and col_card[a] < 0.6:
            a += 1
        while b > a and col_card[b - 1] < 0.6:
            b -= 1
        if b - a < 12:
            continue
        if raised_mask[a:b].sum() * 2 > (b - a):
            continue  # 大部分落在抬起区间内 → 交给 Pass B（边缘小重叠仍由 Pass A 处理）
        a2 = next((x for x in range(a, b) if dark[x] > 2), a)
        while a2 > 0 and dark[a2 - 1] > 2:
            a2 -= 1
        x = max(0, a2 - 5)
        if x + 42 > W:
            continue
        card_top = detect_card_top(gray, a2, min(a2 + 40, b), y_top)
        r = crop_classify(x, card_top, f"h_{a0}")
        if r:
            out.append(r)

    # ---- Pass B：抬起牌（区间顶 ct 为最高牌；层叠更低的牌逐簇用暗行起点反推各自牌顶）
    for ra, rb, ct in raised:
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
            r = crop_classify(x, top, f"h_{ra}")
            if r:
                out.append(r)
    return out


def _raised_intervals(frame, gray, col_card, y_top):
    """检测抬起手牌 → [(a, b, ct)]

    中性白 = 亮且 RGB 通道差小（排除绿桌透色/彩色徽章；牌白与徽章脸无法区分，
    由牌顶范围剔除）。逐列从 y_top-8 向上走，暗隙容 55（穿过字形）；牌顶在
    [y_top-80, y_top-6] 且牌身验证（col_card）通过的列视为抬起列。
    """
    H, W = gray.shape
    f = frame.astype(np.int16)
    Bc, Gc, Rc = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    neutral = (gray > 170) & (np.abs(Rc - Gc) <= 20) & (np.abs(Gc - Bc) <= 20) & (np.abs(Rc - Bc) <= 26)

    base = y_top - 90
    run_top = np.full(W, 10 ** 4, np.int32)
    for x in range(W):
        if col_card[x] <= 0.45:
            continue
        col = neutral[base: y_top + 14, x]
        ai = -1
        for i in range(y_top - 8 - base, y_top - 37 - base, -1):  # 锚点：向上找最近中性白
            if col[i]:
                ai = i
                break
        if ai < 0:
            continue
        top_i, gap, i = ai, 0, ai
        while i > 0 and gap <= 55:
            i -= 1
            if col[i]:
                top_i, gap = i, 0
            else:
                gap += 1
        rt = base + top_i
        if y_top - 80 <= rt <= y_top - 6:
            run_top[x] = rt

    # 连列分组（隙 ≤8 合并），区间牌顶取 run_top 最大值，再用灰度白运行精测
    # （中性白 walk 常停在牌顶描边/光晕下方 ~9px，灰度扫描可回到真实牌顶）
    res = []
    x = 0
    while x < W:
        if run_top[x] >= 10 ** 4:
            x += 1
            continue
        a, b, mx = x, x, run_top[x]
        j = x + 1
        while j < W:
            if run_top[j] < 10 ** 4:
                b, mx = j, max(mx, run_top[j])
                j += 1
            elif j - b <= 8 and any(run_top[k] < 10 ** 4 for k in range(j, min(W, j + 9))):
                j += 1  # 短缺口，向前探
            else:
                break
        if b - a + 1 >= 25:
            ct = mx
            y0 = max(0, mx - 25)
            strip = gray[y0: mx + 8, a:b]
            if strip.size:
                wr = (strip > 170).mean(axis=1)
                for i in range(len(wr) - 12):
                    if wr[i:i + 12].mean() > 0.7:
                        ct = y0 + i
                        break
            res.append((a, b + 1, ct))
        x = b + 1
    return res


def extract_center(frame, tag="", save_unknown=False):
    """中央出牌区 → [(cls, score, x, y, w, h)]"""
    y0, y1 = TABLE_Y
    roi = frame[y0:y1, :]
    mn = roi.min(axis=2).astype(np.int16)
    mx = roi.max(axis=2).astype(np.int16)
    white = ((mn > 165) & (mx - mn < 55)).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(white, 8)
    out = []
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < 3000 or w < 65 or h < 85 or w > 340 or h > 180:
            continue
        comp = frame[y0 + y: y0 + y + h, x: x + w]
        g = cv2.cvtColor(comp, cv2.COLOR_BGR2GRAY)
        dark = (g[int(h * 0.10): int(h * 0.45), :] < 125).sum(axis=0)
        for a, b in find_glyph_clusters(dark):
            cx = max(0, a - 8)
            cw = min(46, w - cx)
            if cw < 30:
                continue
            crop = comp[0:h, cx: cx + cw]
            cls, score, flag = classify(crop, TPLS["center"], CTR_SIZE, min_lh=0)
            if score < ACCEPT and save_unknown and tag:
                save_cn(os.path.join(UNKNOWN_DIR, f"{tag}_c_{x}_{a}.png"), crop)
            out.append((cls, score, x + cx, y0 + y, cw, h, flag))
    return out


def seat_of(x, y):
    """中央出牌区四家分区（494帧实测坐标）：对家顶部居中 y<160；
    中带左=上家 x<500、右=下家；底部 y>=240=我"""
    if y < 160:
        return 0   # 对家
    if y >= 240:
        return 3   # 我
    return 1 if x < 500 else 2  # 上家 / 下家


SEAT_NAMES = ("对", "上", "下", "我")
_RANK_IDX = {r: i for i, r in enumerate(RANKS)}


def fmt_card(k):
    """紧凑牌点字符：花色略（参考图2 流水风格 2333/099），王→W，10→0"""
    if k == "JK":
        return "W"
    return "0" if k[0] == "T" else k[0]


def multiset(dets, accept=ACCEPT):
    """→ (花色计数, 星标计数)：星标/伙章牌花色不可判，只计牌点。
    JK 排除星标——JOKER 牌面中央图案含大片橙色像素，星标检测必误触发"""
    suit = Counter(d[0] for d in dets if d[1] >= accept
                   and (d[0] == "JK" or d[6] != "star"))
    star = Counter(d[0][0]
                   for d in dets if d[1] >= accept and d[6] == "star"
                   and d[0] != "JK")
    return suit, star


def fmt_class(cls):
    if cls == "JK":
        return "王"
    return f"{cls[0]}{SUIT_CN[cls[1]]}"


class Ledger:
    """实时牌账状态机：单帧检出 → 去抖 → 换轮检测 → 累计出牌。

    与 main --dir 回放循环同逻辑（回放#5 验证版），供实时 GUI 复用。
    process_frame 每帧调用一次：传入 extract_hand / extract_center 的检出，
    返回 (手牌花色计数, 手牌星标, gained, gained_star, new_game)。
    """

    def __init__(self):
        self.played = Counter()       # 累计出牌（花色确定）
        self.played_star = Counter()  # 累计星标牌（只按牌点）
        self.center_hist = []         # 近3帧中央计数，逐类取最大吸收漏检闪烁
        self.star_hist = []
        self.prev_center_raw = []     # 上一帧中央检出点数：同点数确认去抖
        self.hand_prev_total = 0
        self.cur_seen = Counter()     # 当前已见（手牌+累计出牌），每帧刷新
        self.cur_star = Counter()
        self.last_game = (Counter(), Counter())   # 新局重置前的上一局末账
        self.played_seat = [Counter() for _ in range(4)]  # 各家累计出牌（花色级）
        self.last_seat = [Counter() for _ in range(4)]    # 各家桌面吸收基准
        self.seat_hist = [[] for _ in range(4)]           # 各家3帧吸收窗
        self.seat_disp = []           # [(方位, 剩余, 最近出牌串)] 供 GUI 显示

    def reset(self):
        self.__init__()

    def process_frame(self, hand_dets, center_dets):
        hs, ht = multiset(hand_dets)
        raw = center_dets
        # 去抖：中央检出须在上一帧原始检出中有同点数者才入账（不限位置——
        # 张数变化使整套牌平移 30-40px，位置约束会错位全滤）。首帧放行
        if self.prev_center_raw:
            confirmed = [d for d in raw
                         if any(p == ("JK" if d[0] == "JK" else d[0][0])
                                for p in self.prev_center_raw)]
        else:
            confirmed = raw
        self.prev_center_raw = [("JK" if d[0] == "JK" else d[0][0]) for d in raw]
        cs, ct = multiset(confirmed, CTR_ACCEPT)
        hand_total = sum(hs.values()) + sum(ht.values())
        # 新一局检测：满 26 张（局中重发）、手牌从 0 恢复增长（发牌动画期
        # 手牌渐增，永远达不到 26 触发条件 → 旧账叠加超基数）、或手牌大幅
        # 增长（五十K 无摸牌，局中手牌只减不增；8→25 跳增 = 新局）
        new_game = False
        full = (hand_total >= 26 and self.hand_prev_total
                and self.hand_prev_total < 26)
        resumed = (hand_total > 0 and self.hand_prev_total == 0
                   and (self.played or self.center_hist))
        grew = (hand_total >= 15 and self.hand_prev_total < 15
                and hand_total > self.hand_prev_total)
        if full or resumed or grew:
            new_game = True
            self.last_game = (self.cur_seen.copy(), self.cur_star.copy())
            self.played.clear()
            self.played_star.clear()
            self.center_hist.clear()
            self.star_hist.clear()
            self.played_seat = [Counter() for _ in range(4)]
            self.last_seat = [Counter() for _ in range(4)]
        self.hand_prev_total = hand_total
        # prev_eff 基于当前帧之前的窗口（含当前帧会使 gained 恒空）
        prev_eff = Counter()
        for h in self.center_hist:
            prev_eff = prev_eff | h
        prev_star_eff = Counter()
        for h in self.star_hist:
            prev_star_eff = prev_star_eff | h
        # 换轮检测：可见牌损失过半或≥3张视为桌面换新，重建基准
        skip_hist = False
        if new_game:
            # 新局首帧桌面混杂上局残留与发牌动画，不入账不入基准
            gained, gained_star = Counter(), Counter()
            skip_hist = True
        # 花色级差分天然免疫换轮重复：同花色同类牌全局唯一，收走动画
        # 残留/未收走旧牌的键已计过（差分自动 0），只有真新牌是新键入账。
        # 故无需换轮 skip——skip 反而会漏计换轮瞬间上桌的同点数新牌
        # （进 cs_t 被跳过后，下一帧差分为 0 永久丢失）
        if not new_game:
            gained = Counter({k: v - prev_eff.get(k, 0)
                              for k, v in cs.items() if v > prev_eff.get(k, 0)})
            gained_star = Counter({k: v - prev_star_eff.get(k, 0)
                                   for k, v in ct.items() if v > prev_star_eff.get(k, 0)})
            # 基数夹逼保险丝：王是大牌，打出后在桌面停留可超过 hist 的
            # 3 帧窗口，检出闪烁致键从并集消失 → 重现时差分再入（JK:6 型）。
            # 同键超基数必为重复误检（同类牌全局唯一/王仅4张），夹到基数
            for k in list(gained):
                cap = 4 if k == "JK" else 2
                room = max(0, cap - self.played.get(k, 0))
                if gained[k] > room:
                    gained[k] = room
        self.played.update(gained)
        self.played_star.update(gained_star)
        self.center_hist.append(Counter() if skip_hist else cs)
        self.star_hist.append(Counter() if skip_hist else ct)
        if len(self.center_hist) > 3:
            self.center_hist.pop(0)
            self.star_hist.pop(0)
        self.cur_seen = hs + self.played
        self.cur_star = ht + self.played_star
        # 四家分账：按检出位置归属，花色级差分（各家桌面基准独立）。
        # 新局帧桌面牌写入基准但不入账（与全局路径语义对齐）
        self.seat_disp = []
        by_seat = [[], [], [], []]
        for d in confirmed:
            if d[1] >= CTR_ACCEPT:
                by_seat[seat_of(d[2], d[3])].append(d)
        for si in range(4):
            cur = Counter(d[0] for d in by_seat[si]
                          if d[0] == "JK" or d[6] != "star")
            if new_game:
                self.seat_hist[si] = [cur.copy()]
                self.last_seat[si] = cur
                continue
            # 3帧窗口逐类最大值吸收闪烁，再差分
            self.seat_hist[si].append(cur.copy())
            if len(self.seat_hist[si]) > 3:
                self.seat_hist[si].pop(0)
            merged = Counter()
            for h in self.seat_hist[si]:
                merged |= h
            g = Counter({k: v - self.last_seat[si].get(k, 0)
                         for k, v in merged.items()
                         if v > self.last_seat[si].get(k, 0)})
            self.last_seat[si] = merged
            self.played_seat[si].update(g)
            left = max(0, 27 - sum(self.played_seat[si].values()))
            cards = "".join(fmt_card(k) * v for k, v in
                            sorted(g.items(),
                                   key=lambda kv: 13 if kv[0] == "JK"
                                   else _RANK_IDX.get(kv[0][0], 0)))
            self.seat_disp.append((SEAT_NAMES[si], left, cards))
        return hs, ht, gained, gained_star, new_game

    def seen(self, hs, ht):
        """当前已见 = 手牌快照 + 累计出牌"""
        return hs + self.played, ht + self.played_star


def render_ledger(seen, star=None, title=""):
    star = star or Counter()
    lines = []
    lines.append("=" * 46)
    if title:
        lines.append(title)
    header = "    " + "  ".join(SUITS) + "   剩/基"
    lines.append(header)
    total_left = 0
    scored_left = 0
    for r in RANKS:
        if r == "JK":
            left = max(0, 4 - seen.get("JK", 0) - star.get("JK", 0))
            lines.append(f"{r:>2}  {left}       {left}/4")
            total_left += left
            continue
        cells = []
        for s in SUITS:
            base = 2
            left = max(0, base - seen.get(r + s, 0))
            mark = "*" if r in SCORED else " "
            cell = f"{left}{mark}" if left < base else f"{left} "
            if left == 0:
                cell = " 0"   # 绝张
            cells.append(cell)
        # 行剩余按牌点总计（含星标牌——花色不可判只计牌点）
        row_left = max(0, 8 - sum(seen.get(r + s, 0) for s in SUITS) - star.get(r, 0))
        lines.append(f"{r:>2}  {'  '.join(cells)}   {row_left}/8")
        total_left += row_left
        if r in SCORED:
            scored_left += row_left
    lines.append(f"牌池剩余总 {total_left} 张 | 分牌(5/10/K)剩 {scored_left} 张")
    lines.append("=" * 46)
    return "\n".join(lines)


def annotate(frame, hand, center, path_out):
    vis = frame.copy()
    for cls, score, x, y, w, h, flag in hand:
        cv2.rectangle(vis, (x, y), (x + w, y + h), (0, 200, 0), 2)
        cv2.putText(vis, f"{cls}{'*' if flag == 'star' else ''} {score:.2f}", (x, y - 4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 255), 1)
    for cls, score, x, y, w, h, flag in center:
        cv2.rectangle(vis, (x, y), (x + w, y + h), (255, 0, 0), 2)
        cv2.putText(vis, f"{cls}{'*' if flag == 'star' else ''} {score:.2f}", (x, y - 4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 0, 0), 1)
    save_cn(path_out, vis)


def main():
    global TPLS
    ap = argparse.ArgumentParser()
    ap.add_argument("--image")
    ap.add_argument("--dir")
    ap.add_argument("--save-unknown", action="store_true")
    ap.add_argument("--annotate-dir", default="")
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    TPLS = load_templates()
    print(f"模板: 手牌 {len(TPLS['hand'])} 张 / 中央 {len(TPLS['center'])} 张")
    if args.save_unknown:
        os.makedirs(UNKNOWN_DIR, exist_ok=True)

    if args.image:
        frame = imread_cn(args.image)
        tag = os.path.splitext(os.path.basename(args.image))[0]
        hand = extract_hand(frame, tag, args.save_unknown)
        center = extract_center(frame, tag, args.save_unknown)
        print(f"\n手牌 {len(hand)} 张:")
        print("  " + " ".join(f"{d[0]}{'*' if d[6] == 'star' else ''}({d[1]:.2f})" for d in hand))
        print(f"中央 {len(center)} 张:")
        print("  " + " ".join(f"{d[0]}{'*' if d[6] == 'star' else ''}({d[1]:.2f})" for d in center))
        hs, ht = multiset(hand)
        cs, ct = multiset(center, CTR_ACCEPT)
        print(render_ledger(hs + cs, ht + ct, "本帧快照（手牌+中央，未含历史出牌）"))
        out = os.path.join(ROOT, f"debug_{tag}.png")
        annotate(frame, hand, center, out)
        print(f"标注图: {out}")
        return

    if args.dir:
        files = sorted(f for f in os.listdir(args.dir) if f.endswith(".png") and not f.startswith("sheet"))
        led = Ledger()
        new_game_cnt = 0
        for fn in files:
            frame = imread_cn(os.path.join(args.dir, fn))
            if frame is None:
                continue
            tag = os.path.splitext(fn)[0].split("_")[1]
            hand = extract_hand(frame, tag, args.save_unknown)
            center = extract_center(frame, tag, args.save_unknown)
            hs, ht, gained, gained_star, new_game = led.process_frame(hand, center)
            hand_total = sum(hs.values()) + sum(ht.values())
            if new_game:
                new_game_cnt += 1
                print(f"\n######## 上一局结束牌账（{fn} 之前）########")
                ps, pt = led.last_game
                print(render_ledger(ps, pt))
                print(f"\n######## 检测到新一局（{fn}）########")
            if gained or gained_star:
                extra = f" | 星标: {dict(gained_star)}" if gained_star else ""
                print(f"[{fn}] 出牌新增: {dict(gained)}{extra} | 手牌{hand_total}张")
        print(f"\n共 {len(files)} 帧，检测到新局 {new_game_cnt} 次")
        print(render_ledger(led.cur_seen, led.cur_star, "回放结束牌账（剩余=基数−已见）"))
        return


import sys

if __name__ == "__main__":
    main()
