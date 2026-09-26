# -*- coding: utf-8 -*-
"""全量回放验证四家分账（seat 归属/剩余推算/与全局账一致性）"""
import os
import sys

from collections import Counter

import recognize_fiftyk as rf


def main():
    d = os.path.join(rf.ROOT, "samples", "pc_20260926_004419")
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    rf.TPLS = rf.load_templates()
    led = rf.Ledger()
    games = []          # 每局末的 seat_disp 快照
    mismatch = 0        # seat 总出牌数与全局不一致的帧数
    neg = 0             # 剩余为负的帧数
    for fn in files:
        frame = rf.imread_cn(os.path.join(d, fn))
        if frame is None:
            continue
        tag = os.path.splitext(fn)[0].split("_")[1]
        led.process_frame(rf.extract_hand(frame, tag, False),
                          rf.extract_center(frame, tag, False))
        seat_total = sum(sum(p.values()) for p in led.played_seat)
        glob_total = sum(led.played.values()) + sum(led.played_star.values())
        if seat_total != glob_total:
            mismatch += 1
        if any(27 - sum(p.values()) < 0 for p in led.played_seat):
            neg += 1
        if led.seat_disp:
            games.append((fn, led.seat_disp))
    print(f"共 {len(files)} 帧 | 新局 {len(games) and '见下'}")
    print(f"seat与全局不一致帧数: {mismatch} | 剩余为负帧数: {neg}")
    # 抽样打印：每 40 帧一次的最新流水
    for i in range(0, len(games), 40):
        fn, disp = games[i]
        s = " | ".join(f"{t}{l}{' ' + c if c else ''}" for t, l, c in disp)
        print(f"{fn[6:11]}  {s}")
    if games:
        fn, disp = games[-1]
        s = " | ".join(f"{t}{l}{' ' + c if c else ''}" for t, l, c in disp)
        print(f"末帧 {fn[6:11]}  {s}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
