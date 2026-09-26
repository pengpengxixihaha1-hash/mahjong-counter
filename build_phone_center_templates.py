# -*- coding: utf-8 -*-
"""生成 templates_phone/center（牌点-only）。

来源：center 联系表标注簇 + shot_004 补采的 4 + 手牌 JK 兜底（匹配时靠尺度阶梯缩小）。
"""
import os
import json
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
CROPS_C = os.path.join(ROOT, "phone_crops", "center")
CROPS_H = os.path.join(ROOT, "templates_phone", "hand")
TPL = os.path.join(ROOT, "templates_phone", "center")
DBG = os.path.join(ROOT, "debug_phone")

# G编号 → 牌点（None=剔除：角标/黄闪/人物画/残pip/顶切）
LABELS = {
    "G0": "J", "G1": "7", "G2": "7", "G3": "Q", "G4": "Q", "G5": "Q",
    "G6": "Q", "G7": "J", "G8": "J", "G9": "J", "G12": "8", "G13": "J",
    "G14": "T", "G15": "T", "G16": "T", "G17": "8", "G18": "8", "G19": "Q",
    "G20": "5", "G21": "6", "G22": "6", "G23": "7", "G24": "7", "G26": "3",
    "G27": "3", "G28": "3", "G29": "A", "G30": "K", "G32": "6", "G33": "6",
    "G37": "9", "G38": "9", "G39": "T", "G40": "6", "G41": "6", "G42": "9",
    "G43": "9", "G44": "9", "G45": "J", "G47": "2", "G48": "2", "G49": "A",
    "G50": "A", "G51": "7", "G52": "5", "G53": "5", "G54": "5", "G55": "K",
    "G57": "5", "G58": "T", "G59": "K",
    "G10": None, "G11": None, "G25": None, "G31": None, "G34": None,
    "G35": None, "G36": None, "G46": None, "G56": None, "G60": None,
}
FOURS = [f"shot_004_four_{i}" for i in range(1, 7)]
PER_GROUP = 2


def main():
    if os.path.isdir(TPL):
        shutil.rmtree(TPL)
    os.makedirs(TPL, exist_ok=True)
    with open(os.path.join(DBG, "center_clusters.json")) as f:
        groups = json.load(f)
    counts = {}
    n = 0
    for g, members in groups.items():
        rank = LABELS.get(g, None)
        if not rank:
            continue
        for name in members[:PER_GROUP]:
            src = os.path.join(CROPS_C, name + ".png")
            if not os.path.isfile(src):
                continue
            counts[rank] = counts.get(rank, 0) + 1
            os.replace(src, os.path.join(TPL, f"{rank}_{counts[rank]-1}.png"))
            n += 1
    for name in FOURS:
        src = os.path.join(CROPS_C, name + ".png")
        if os.path.isfile(src):
            counts["4"] = counts.get("4", 0) + 1
            os.replace(src, os.path.join(TPL, f"4_{counts['4']-1}.png"))
            n += 1
    # JK 兜底：手牌模板直接复制（匹配时尺度阶梯缩到 0.5-0.6）
    for fn in sorted(os.listdir(CROPS_H)):
        if fn.startswith("JK_") and fn.endswith(".png"):
            shutil.copyfile(os.path.join(CROPS_H, fn),
                            os.path.join(TPL, fn.replace(".png", "_h.png")))
            counts["JK"] = counts.get("JK", 0) + 1
            n += 1
    print(f"center templates: {n}")
    for r in sorted(counts):
        print(f"  {r}: {counts[r]}")


if __name__ == "__main__":
    main()
