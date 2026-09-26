# -*- coding: utf-8 -*-
"""按 winners.json 选中央模板：每牌点获胜次数 top-2，无获胜记录的牌点取字典序前 2。

中央牌随扇形张数变尺度，均值模板已验证退化（6→Q/J 混淆），故保留原始
多尺度样本、仅做数据驱动裁剪：165→28 张，真机 NCC 次数降 ~6 倍。
手牌区固定尺度，用平均模板（templates_phone_avg/hand，17 样本回归一致）。
"""
import json
import os
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "templates_phone", "center")
DST = os.path.join(ROOT, "templates_phone_sel", "center")
RANKS = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2", "JK"]
PER_RANK = 2


def main():
    with open(os.path.join(ROOT, "winners.json"), encoding="utf-8") as f:
        winners = json.load(f)["center"]
    # winners 键即 templates_phone/center 的文件名（如 A_0.png、JK_1.png）
    by_rank = {r: [] for r in RANKS}
    for fn, n in winners.items():
        rank = fn.split("_")[0]
        by_rank.setdefault(rank, []).append((n, fn))
    os.makedirs(DST, exist_ok=True)
    for f in os.listdir(DST):
        os.remove(os.path.join(DST, f))
    picked = []
    for r in RANKS:
        cands = sorted(by_rank.get(r, []), reverse=True)
        names = [fn for _n, fn in cands[:PER_RANK]]
        if not names:  # 样本未出现的牌点：保留字典序前 2
            names = sorted(fn for fn in os.listdir(SRC)
                           if fn.split("_")[0] == r)[:PER_RANK]
        for fn in names:
            shutil.copy(os.path.join(SRC, fn), os.path.join(DST, fn))
            picked.append(fn)
    print(f"选中 {len(picked)} 张中央模板 → {DST}")
    for fn in picked:
        print(" ", fn)


if __name__ == "__main__":
    main()
