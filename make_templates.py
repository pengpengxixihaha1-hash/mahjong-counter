# -*- coding: utf-8 -*-
"""
五十K记牌器 · 模板整理与中央区裁剪

1) 按 LABELS 把 hand_raw 角标归类到 templates/hand/<类名>_<变体>.png
   类名 = 点数+花色首字母（S黑桃 H红心 C梅花 D方块），王=JK
2) 在指定帧的中央出牌区检测白色牌块，切角标 → templates/center_raw/ + 拼图
"""
import os
import shutil
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
HAND_RAW = os.path.join(ROOT, "templates", "hand_raw")
HAND_OUT = os.path.join(ROOT, "templates", "hand")
CTR_RAW = os.path.join(ROOT, "templates", "center_raw")

# 人工标注结果（查看 sheet_f0150 / sheet_f0100 后填写）
LABELS = {
    # frame_0150（24张）
    "f0150_s00": "JK", "f0150_s01": "JK", "f0150_s02": "JK",
    "f0150_s03": "5S", "f0150_s04": "5S", "f0150_s05": "5C", "f0150_s06": "5C",
    "f0150_s07": "QH", "f0150_s08": "QC", "f0150_s09": "QD",
    "f0150_s10": "9H", "f0150_s11": "9C", "f0150_s12": "9D",
    "f0150_s13": "8H", "f0150_s14": "8H", "f0150_s15": "8C",
    "f0150_s16": "2C", "f0150_s17": "2D",
    "f0150_s18": "4H", "f0150_s19": "4D",
    "f0150_s20": "3S", "f0150_s21": "3H", "f0150_s22": "7D", "f0150_s23": "6H",
    # frame_0100（19张）
    "f0100_s00": None, "f0100_s01": "JK",
    "f0100_s02": "JH", "f0100_s03": "JH", "f0100_s04": "JC", "f0100_s05": "JC",
    "f0100_s06": "KH", "f0100_s07": "TH", "f0100_s08": "TC", "f0100_s09": "TD",
    "f0100_s10": "5H", "f0100_s11": "2S", "f0100_s12": "2C",
    "f0100_s13": "QS", "f0100_s14": "QH", "f0100_s15": "7H", "f0100_s16": "7D",
    "f0100_s17": "8S", "f0100_s18": "6S",
}


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def organize_hand():
    os.makedirs(HAND_OUT, exist_ok=True)
    count = {}
    for name, cls in LABELS.items():
        if not cls:
            continue
        src = os.path.join(HAND_RAW, name + ".png")
        if not os.path.exists(src):
            continue
        count[cls] = count.get(cls, 0) + 1
        dst = os.path.join(HAND_OUT, f"{cls}_{count[cls]}.png")
        shutil.copyfile(src, dst)
    print(f"手牌模板: {sum(count.values())} 张, {len(count)} 类")
    print("类别:", sorted(count.keys()))


def find_glyph_clusters(band_dark, min_w=10, max_w=60, merge_gap=8):
    cols = band_dark > 2
    clusters = []
    start = None
    gap = 0
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
        if not (min_w <= w):
            continue
        if w > max_w:  # 宽簇（多张牌粘连/角标噪声）按 ~38px 均分拆开
            k = max(2, round(w / 38))
            step = w / k
            for j in range(k):
                out.append((int(a + j * step), int(a + (j + 1) * step)))
        else:
            out.append((a, b))
    return out


def harvest_center(paths):
    """中央出牌区白色牌块 → 角标裁剪"""
    os.makedirs(CTR_RAW, exist_ok=True)
    all_crops = []
    for path in paths:
        frame = imread_cn(path)
        if frame is None:
            continue
        tag = os.path.splitext(os.path.basename(path))[0].split("_")[1]
        # 牌桌区域（避开顶部标题栏与底部手牌/状态栏）
        y0, y1 = 100, 445
        roi = frame[y0:y1, :]
        mn = roi.min(axis=2).astype(np.int16)
        mx = roi.max(axis=2).astype(np.int16)
        white = ((mn > 165) & (mx - mn < 55)).astype(np.uint8)
        n, lab, stats, _ = cv2.connectedComponentsWithStats(white, 8)
        found = 0
        for i in range(1, n):
            x, y, w, h, area = stats[i]
            # 牌块尺寸（中央牌约 80~130 宽）
            if area < 3000 or w < 65 or h < 85 or w > 340 or h > 180:
                continue
            comp = frame[y0 + y: y0 + y + h, x: x + w]
            g = cv2.cvtColor(comp, cv2.COLOR_BGR2GRAY)
            # 中央牌点数行大约在牌顶下 15%~40% 高度
            ra, rb = int(h * 0.10), int(h * 0.45)
            dark = (g[ra:rb, :] < 125).sum(axis=0)
            clusters = find_glyph_clusters(dark)
            print(f"  {tag}: 组件({x},{y0+y},{w}x{h}) 字形簇 {clusters}")
            for ci, (a, b) in enumerate(clusters):
                cx = max(0, a - 8)
                cw = 46
                if cx + cw > w:
                    cw = w - cx
                if cw < 30:
                    continue
                crop = comp[0: h, cx: cx + cw]
                name = f"{tag}_c{i}_{ci}.png"
                save_cn(os.path.join(CTR_RAW, name), crop)
                all_crops.append((name, crop))
                found += 1
        print(f"{tag}: 组件角标 {found}")
    if all_crops:
        ch = max(c.shape[0] for _, c in all_crops)
        cw = max(c.shape[1] for _, c in all_crops)
        cols_n = 8
        rows = (len(all_crops) + cols_n - 1) // cols_n
        sheet = np.full((rows * (ch * 2 + 26) + 6, cols_n * (cw * 2 + 10) + 6, 3), 40, np.uint8)
        for idx, (name, c) in enumerate(all_crops):
            r, col = divmod(idx, cols_n)
            big = cv2.resize(c, (c.shape[1] * 2, c.shape[0] * 2), interpolation=cv2.INTER_NEAREST)
            y, x = 6 + r * (ch * 2 + 26), 6 + col * (cw * 2 + 10)
            sheet[y:y + big.shape[0], x:x + big.shape[1]] = big
            cv2.putText(sheet, name.replace(".png", ""), (x, y + ch * 2 + 18),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1)
        sp = os.path.join(CTR_RAW, "sheet_center.png")
        save_cn(sp, sheet)
        print(f"中央区拼图: {sp}")


if __name__ == "__main__":
    organize_hand()
    frames = sys.argv[1:] or [
        os.path.join(ROOT, "samples", "pc_20260926_004419", "frame_0150_005411_865.png"),
        os.path.join(ROOT, "samples", "pc_20260926_004419", "frame_0100_004933_102.png"),
    ]
    print("\n中央区裁剪:")
    harvest_center(frames)
