# -*- coding: utf-8 -*-
"""回放日志守恒扫描：各局累计出牌 vs 基数，单帧超基数检出
花色确定牌按类（每类2张/JK4张）；星标牌按牌点（每点8张/JK4张）"""
import re
from collections import Counter

BASE = lambda k: 4 if k == "JK" else 2
BASE_STAR = lambda k: 4 if k == "JK" else 8

games = []
cur = Counter()
star_cur = Counter()
issues = []
for line in open("replay_log3.txt", encoding="utf-8", errors="replace"):
    if "新一局" in line:
        games.append(dict(cur))
        cur = Counter()
        star_cur = Counter()
    m = re.search(r"出牌新增: (\{.*?\})", line)
    if m:
        d = eval(m.group(1))
        tag = line.split("]")[0][1:]
        for k, v in d.items():
            cur[k] += v
            if cur[k] > BASE(k):
                issues.append((tag, k, v, cur[k]))
            if v > BASE(k):
                issues.append((tag, k + "/单帧", v, cur[k]))
    m2 = re.search(r"星标: (\{.*?\})", line)
    if m2:
        d = eval(m2.group(1))
        tag = line.split("]")[0][1:]
        for k, v in d.items():
            star_cur[k] += v
            if star_cur[k] > BASE_STAR(k):
                issues.append((tag, k + "/星标", v, star_cur[k]))
games.append(dict(cur))

print("=== 各局累计出牌 vs 基数 ===")
for gi, g in enumerate(games, 1):
    over = {k: v for k, v in g.items() if v > BASE(k)}
    total = sum(g.values())
    flag = f"超基数: {over}" if over else "OK"
    print(f"局{gi}: 共{total}张  {flag}")
print("=== 违规明细(前30) ===")
for it in issues[:30]:
    print(it)
print("共", len(issues), "条")
