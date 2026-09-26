# -*- coding: utf-8 -*-
"""
把 templates/unknown 里的低置信度裁剪按相似度聚类，
输出簇代表拼图（按簇大小排序）+ 簇号，供人工快速标注。

用法：python cluster_unknowns.py
产出：templates/unknown/sheet_clusters_00.png ...  + clusters.json（簇代表文件清单）
"""
import json
import os
import re
from collections import defaultdict

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
UNK = os.path.join(ROOT, "templates", "unknown")


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(os.path.splitext(p)[1], img)
    if ok:
        buf.tofile(p)


def norm_patch(img, size):
    img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    g = (g - g.mean()) / (g.std() + 1e-6)
    return g.flatten()


def main():
    hand, center = [], []
    for fn in sorted(os.listdir(UNK)):
        if not fn.endswith(".png") or fn.startswith("sheet"):
            continue
        img = imread_cn(os.path.join(UNK, fn))
        if img is None:
            continue
        (hand if "_h_" in fn else center).append((fn, img))

    def cluster(items, size, thresh=0.86):
        reps = []      # (mean_vec, [fn...])
        vecs = np.stack([norm_patch(im, size) for _, im in items]) if items else np.zeros((0,))
        for i, (fn, _im) in enumerate(items):
            best_j, best_s = -1, thresh
            for j, (rep, members) in enumerate(reps):
                s = float(np.dot(vecs[i], rep) / (np.linalg.norm(vecs[i]) * np.linalg.norm(rep) + 1e-6))
                if s > best_s:
                    best_s, best_j = s, j
            if best_j >= 0:
                reps[best_j][1].append(fn)
            else:
                reps.append((vecs[i], [fn]))
        reps.sort(key=lambda r: -len(r[1]))
        return reps

    rh = cluster(hand, (42, 130))
    rc = cluster(center, (46, 111))
    print(f"unknown: 手牌 {len(hand)} 张 -> {len(rh)} 簇; 中央 {len(center)} 张 -> {len(rc)} 簇")

    info = {"hand": [{"rep_file": ms[1][0], "n": len(ms[1]), "members": ms[1]} for ms in rh],
            "center": [{"rep_file": ms[1][0], "n": len(ms[1]), "members": ms[1]} for ms in rc]}
    with open(os.path.join(UNK, "clusters.json"), "w", encoding="utf8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)

    # 拼图：手牌簇 + 中央簇分块，每页 10x5
    def sheet(reps, items_map, prefix, size):
        all_pages = []
        cell_w, cell_h = size[0] * 2, size[1] * 2
        per_page = 50
        for page in range(0, len(reps), per_page):
            rows = 5
            cols = 10
            sh = np.full((rows * (cell_h + 24) + 6, cols * (cell_w + 8) + 6, 3), 40, np.uint8)
            for k, (rep, members) in enumerate(reps[page: page + per_page]):
                r, c = divmod(k, cols)
                fn = members[0]
                img = imread_cn(os.path.join(UNK, fn))
                big = cv2.resize(img, (cell_w, cell_h), interpolation=cv2.INTER_NEAREST)
                y, x = 6 + r * (cell_h + 24), 6 + c * (cell_w + 8)
                sh[y:y + cell_h, x:x + cell_w] = big
                cv2.putText(sh, f"{prefix}{page+k} n={len(members)}", (x, y + cell_h + 17),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1)
            sp = os.path.join(UNK, f"sheet_clusters_{prefix}_{page//per_page:02d}.png")
            save_cn(sp, sh)
            all_pages.append(sp)
        return all_pages

    pages = sheet(rh, hand, "H", (42, 130)) + sheet(rc, center, "C", (46, 111))
    for p in pages:
        print("拼图:", p)


if __name__ == "__main__":
    main()
