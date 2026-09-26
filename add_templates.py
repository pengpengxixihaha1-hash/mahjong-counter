# -*- coding: utf-8 -*-
"""按簇号把已标注的未知裁剪拷贝为正式模板（只拷人工目检干净的角标簇）"""
import json
import os

from recognize_fiftyk import imread_cn, save_cn

ROOT = os.path.dirname(os.path.abspath(__file__))
UNK = os.path.join(ROOT, "templates", "unknown")

# 手牌：缺失类优先 + 干净变体（H 编号 = clusters.json["hand"] 索引）
HAND = {
    11: "6H", 13: "AS", 15: "9S", 24: "7C", 30: "8D", 31: "KS",
    64: "KD", 65: "KD", 82: "3C", 93: "TS",
    4: "5C", 7: "JK", 8: "7H", 26: "2C", 27: "JC",
}

# 中央：角标簇（肖像簇一律不拷，防同帧双计）
CENTER = {
    0: "KH", 1: "JD", 4: "9D", 5: "5S", 6: "TC", 8: "7S", 9: "6C",
    11: "4S", 12: "TH", 13: "4C", 14: "8C", 15: "9S", 16: "JS", 17: "AC",
    18: "JS", 19: "6D", 21: "7D", 22: "6H", 23: "2C", 24: "AD", 25: "TC",
    26: "4D", 27: "AH", 28: "7S", 29: "7H", 30: "AS", 31: "5D", 32: "4H",
    33: "6S", 34: "6C", 35: "8H", 36: "8S", 37: "KS", 38: "7C", 39: "5H",
    40: "2S", 41: "4H", 42: "8D", 43: "3C", 44: "AD", 45: "TS", 46: "KD",
    47: "4D", 48: "2C", 49: "JC", 50: "TD",
    52: "QD", 53: "6H", 55: "9H", 56: "JH", 57: "KS", 58: "KD", 59: "7S",
    60: "3H", 61: "3C", 62: "AH", 71: "AS", 77: "8C",
    85: "6H", 91: "TC", 93: "KH", 100: "3S",
    104: "8C", 105: "9C", 106: "9H", 112: "9D", 119: "3S", 136: "4S",
    141: "8H", 143: "AC", 144: "2D", 156: "2H", 157: "5C",
}

d = json.load(open(os.path.join(UNK, "clusters.json"), encoding="utf-8"))
cnt = {"hand": 0, "center": 0}
for kind, mapping in (("hand", HAND), ("center", CENTER)):
    outdir = os.path.join(ROOT, "templates", kind)
    os.makedirs(outdir, exist_ok=True)
    existing = set(os.listdir(outdir))
    clusters = d[kind]
    for idx, cls in sorted(mapping.items()):
        src = os.path.join(UNK, clusters[idx]["rep_file"])
        img = imread_cn(src)
        if img is None:
            print(f"[跳过] {kind} 簇{idx} 读取失败: {src}")
            continue
        n = 1
        while f"{cls}_{n}.png" in existing:
            n += 1
        dst = os.path.join(outdir, f"{cls}_{n}.png")
        save_cn(dst, img)
        existing.add(os.path.basename(dst))
        cnt[kind] += 1
print(f"拷贝完成: 手牌 +{cnt['hand']} 张, 中央 +{cnt['center']} 张")
for kind in ("hand", "center"):
    p = os.path.join(ROOT, "templates", kind)
    fns = os.listdir(p)
    print(f"templates/{kind}: {len(fns)} 张")
    classes = sorted({f.rsplit('_', 1)[0] for f in fns})
    print("  类别:", " ".join(classes))
