# -*- coding: utf-8 -*-
"""全量模板自诊 + 清洗。

自诊：每张模板 X 的字母区 t_l（按 classify 同比例截取），在同类其他模板的
补边整图上做 SCALE_LADDER 全阶梯搜索，best s_l 即 X 的健康分（同类模板互为
变体，好模板应在 peer 上高匹配）。

规则：
- JK 豁免：小丑/国王两种造型不互匹；类内仅 1 张无法自诊，豁免。
- 删：s_l < 0.75（重度坏）；类内删除后须保留 ≥1 张（优先保 ≥0.85 的好模板，
  全坏则保最高分一张）。0.75-0.85 临界保留（池机制取最大值，坏模板只在
  它赢时才有害，且可能被阶梯救回）。
用法：python clean_templates.py [--apply]   # 无 --apply 仅 dry-run
"""
import os
import sys
from collections import defaultdict

import cv2
import numpy as np

import recognize_fiftyk as rf

BAD = 0.75
GOOD = 0.85


def diag(tpls):
    groups = defaultdict(list)
    for idx, (cls, _img, gray, fn, _lh) in enumerate(tpls):
        groups[cls].append(idx)
    scores = {}
    for cls, idxs in groups.items():
        if cls == "JK" or len(idxs) < 2:
            for i in idxs:
                scores[tpls[i][3]] = None
            continue
        for i in idxs:
            gray_a = tpls[i][2]
            th, tw = gray_a.shape
            t_l = gray_a.astype(np.float32)[
                int(0.04 * th):int(0.50 * th), int(0.04 * tw):int(0.70 * tw)]
            best = -1.0
            for j in idxs:
                if j == i:
                    continue
                inp = cv2.copyMakeBorder(tpls[j][2], 14, 14, 14, 14,
                                         cv2.BORDER_REPLICATE).astype(np.float32)
                for r in rf.SCALE_LADDER:
                    t = t_l
                    if abs(r - 1.0) > 0.02:
                        t = cv2.resize(t_l, None, fx=r, fy=r,
                                       interpolation=cv2.INTER_AREA)
                    if t.shape[0] >= inp.shape[0] or t.shape[1] >= inp.shape[1]:
                        continue
                    s = float(cv2.matchTemplate(inp, t, cv2.TM_CCOEFF_NORMED).max())
                    best = max(best, s)
            scores[tpls[i][3]] = best
    return scores


def plan_deletions(tpls, scores):
    by_cls = defaultdict(list)
    for cls, _img, _gray, fn, _lh in tpls:
        by_cls[cls].append((fn, scores[fn]))
    to_del = []
    for cls, items in sorted(by_cls.items()):
        valid = [(fn, s) for fn, s in items if s is not None]
        if not valid:
            continue
        keep = {fn for fn, s in valid if s >= GOOD}
        if not keep:
            best = max(valid, key=lambda x: x[1])
            keep.add(best[0])
            print(f"[警告] {cls} 无好模板，保最高分 {best[0]}({best[1]:.3f})")
        for fn, s in sorted(valid, key=lambda x: x[1]):
            if s < BAD and fn not in keep:
                to_del.append((cls, fn, s))
    return to_del


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    apply = "--apply" in sys.argv
    tpls = rf.load_templates()
    for kind in ("hand", "center"):
        scores = diag(tpls[kind])
        print(f"\n===== templates/{kind} 自诊（{len(scores)} 张）=====")
        by_cls = defaultdict(list)
        for fn, s in scores.items():
            by_cls[fn.rsplit("_", 1)[0]].append((fn, s))
        for cls in sorted(by_cls):
            line = "  ".join(f"{fn}:{'--' if s is None else f'{s:.3f}'}"
                             for fn, s in sorted(by_cls[cls]))
            print(f"  {cls:>3}: {line}")
        to_del = plan_deletions(tpls[kind], scores)
        if not to_del:
            print("  无需删除")
            continue
        print(f"  拟删 {len(to_del)} 张:")
        for cls, fn, s in to_del:
            mark = "删" if apply else "试"
            print(f"    [{mark}] {fn} (s={s:.3f})")
        if apply:
            d = rf.CTR_TPL_DIR if kind == "center" else rf.HAND_TPL_DIR
            for _cls, fn, _s in to_del:
                os.remove(os.path.join(d, fn))
    if apply:
        print("\n删除完成，重新统计:")
        tpls = rf.load_templates()
        for kind in ("hand", "center"):
            classes = sorted({t[0] for t in tpls[kind]})
            missing = [c for c in rf.RANKS if c != "JK"
                       for c in [c + s for s in rf.SUITS] if c not in classes]
            print(f"  templates/{kind}: {len(tpls[kind])} 张, 类别 {len(classes)}"
                  + (f", 缺失: {' '.join(missing)}" if missing else ""))


if __name__ == "__main__":
    main()
