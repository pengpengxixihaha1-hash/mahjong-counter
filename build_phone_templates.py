# -*- coding: utf-8 -*-
"""按联系表标注生成 templates_phone/hand（牌点-only，不分花色）。

每牌点取红/黑两版、每版最多3张（不同截图的轻微尺度/光照差异），
类别名沿用 PC 约定：3 4 5 6 7 8 9 T J Q K A 2 JK（T=10）。
"""
import os
import json
import shutil
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
CROPS = os.path.join(ROOT, "phone_crops", "hand")
DBG = os.path.join(ROOT, "debug_phone")
TPL = os.path.join(ROOT, "templates_phone", "hand")

# G编号 → 牌点（None=剔除：徽章/残缺/伙章遮挡）
LABELS = {
    "G0": "K", "G1": "7", "G2": "9", "G3": "5", "G4": "8", "G5": "4",
    "G6": "6", "G7": "2", "G8": "6", "G9": "A", "G10": "4", "G11": "Q",
    "G12": "A", "G13": "Q", "G14": "T", "G15": "5", "G16": "7", "G17": "3",
    "G18": "2", "G19": "J", "G20": "9", "G21": "T", "G22": "8", "G23": "K",
    "G24": "JK", "G25": "J", "G28": "JK", "G31": "3", "G32": "A", "G33": "A",
    "G34": "2",
    "G26": None, "G27": None, "G29": None, "G30": None, "G35": None, "G36": None,
}
PER_GROUP = 3   # 每簇最多取几张


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def main():
    if os.path.isdir(TPL):
        shutil.rmtree(TPL)
    os.makedirs(TPL, exist_ok=True)
    with open(os.path.join(DBG, "hand_clusters.json")) as f:
        groups = json.load(f)
    counts = {}
    n = 0
    for g, members in groups.items():
        rank = LABELS.get(g, None)
        if not rank:
            continue
        for k, name in enumerate(members[:PER_GROUP]):
            img = imread_cn(os.path.join(CROPS, name + ".png"))
            if img is None:
                continue
            counts[rank] = counts.get(rank, 0) + 1
            save_cn(os.path.join(TPL, f"{rank}_{counts[rank]-1}.png"), img)
            n += 1
    print(f"templates: {n} -> {TPL}")
    for r in sorted(counts):
        print(f"  {r}: {counts[r]}")


if __name__ == "__main__":
    main()
