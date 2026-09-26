# -*- coding: utf-8 -*-
"""
五十K记牌器 · 模板裁剪（glyph 锚定版）

在底部手牌区检测每张牌的「点数字形」位置（暗色像素列聚类），
按字形位置切出「点数+花色」角标，生成放大拼图供人工标注。
自校准 x0/pitch，不依赖固定坐标。
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "templates", "hand_raw")


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def detect_band_top(gray):
    h, w = gray.shape
    for y in range(370, h - 40):
        if float((gray[y, 100:900] > 185).mean()) > 0.5:
            return y
    return 397


def find_glyph_clusters(band_dark):
    """按列聚类暗像素段，返回 [(start,end)]，合并间距<14 的段（处理“10”）"""
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
            if gap >= 14:
                clusters.append((start, x - gap))
                start = None
    if start is not None:
        clusters.append((start, len(cols) - 1))
    return [(a, b) for a, b in clusters if 8 <= b - a <= 70]


def main():
    path = sys.argv[1]
    tag = sys.argv[2] if len(sys.argv) > 2 else "f"

    frame = imread_cn(path)
    if frame is None:
        print("读取失败:", path)
        return
    h, w = frame.shape[:2]
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    y_top = detect_band_top(gray)
    print(f"帧 {w}x{h}  牌顶 y={y_top}")

    # 点数行：牌顶下 40~95px（bootstrap 帧无抬起牌，窄带即可；与 recognize Pass A 一致）
    dark = (gray[y_top + 40: y_top + 95, :] < 125).sum(axis=0)
    clusters = find_glyph_clusters(dark)
    print(f"检测到 {len(clusters)} 个点数字形")

    centers = [(a + b) / 2 for a, b in clusters]
    diffs = np.diff(centers)
    pitch = float(np.median(diffs))
    print(f"相邻字形间距: {[f'{d:.1f}' for d in diffs]}")
    print(f"中位 pitch = {pitch:.1f}")

    crop_w = 42
    # 与 recognize_fiftyk.extract_hand 相同的修边+重锚定+逐牌顶边逻辑，保证裁剪一致
    col_card = (gray[y_top + 105: y_top + 145, :] > 175).mean(axis=0)

    def detect_card_top(a, b):
        y0 = max(280, y_top - 90)
        strip = gray[y0: y_top + 40, a:b]
        if strip.size == 0:
            return y_top
        wr = (strip > 175).mean(axis=1)
        for i in range(len(wr) - 12):
            if wr[i:i + 12].mean() > 0.75:
                return y0 + i
        return y_top

    crops = []
    for i, (a0, b0) in enumerate(clusters):
        a, b = a0, b0
        while a < b and col_card[a] < 0.6:
            a += 1
        while b > a and col_card[b - 1] < 0.6:
            b -= 1
        if b - a < 12:
            continue
        a2 = next((x for x in range(a, b) if dark[x] > 2), a)
        while a2 > 0 and dark[a2 - 1] > 2:
            a2 -= 1
        x = max(0, a2 - 5)
        card_top = detect_card_top(a2, min(a2 + 40, b))
        crop = frame[card_top + 9: card_top + 9 + 130, x: x + crop_w]
        if crop.shape[1] < crop_w:
            continue
        name = f"{tag}_s{i:02d}.png"
        save_cn(os.path.join(OUT, name), crop)
        crops.append((name, crop))

    ch = 130 * 2
    cols_n = 10
    rows = (len(crops) + cols_n - 1) // cols_n
    sheet = np.full((rows * (ch + 26) + 6, cols_n * (crop_w * 2 + 10) + 6, 3), 40, np.uint8)
    for idx, (name, c) in enumerate(crops):
        r, col = divmod(idx, cols_n)
        big = cv2.resize(c, (crop_w * 2, ch), interpolation=cv2.INTER_NEAREST)
        y, x = 6 + r * (ch + 26), 6 + col * (crop_w * 2 + 10)
        sheet[y:y + ch, x:x + crop_w * 2] = big
        cv2.putText(sheet, name.replace(".png", ""), (x, y + ch + 18),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 255, 255), 1)
    sp = os.path.join(OUT, f"sheet_{tag}.png")
    save_cn(sp, sheet)
    print(f"已保存 {len(crops)} 个角标 -> {OUT}\n拼图: {sp}")


if __name__ == "__main__":
    main()
