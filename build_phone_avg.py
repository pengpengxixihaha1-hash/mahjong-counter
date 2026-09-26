# -*- coding: utf-8 -*-
"""把 templates_phone/{hand,center} 每牌点归一化后取均值 → templates_phone_avg。

真机端只打包平均模板（每牌点 1 张）：模板数 165→28，NCC 次数降 6 倍，
且均值模板对多截图光照/尺度差异更稳健。先跑 recognize_phone.py --avg
对 17 张样本回归验证，通过后才拷入 iOS。
"""
import os
import shutil
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SIZES = {"hand": (56, 150), "center": (44, 96)}


def imread_cn(p):
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def save_cn(p, img):
    ok, buf = cv2.imencode(".png", img)
    if ok:
        buf.tofile(p)


def main():
    for kind, size in SIZES.items():
        src = os.path.join(ROOT, "templates_phone", kind)
        dst = os.path.join(ROOT, "templates_phone_avg", kind)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        os.makedirs(dst, exist_ok=True)
        groups = {}
        for fn in sorted(os.listdir(src)):
            if not fn.endswith(".png"):
                continue
            cls = fn.split("_")[0]
            img = imread_cn(os.path.join(src, fn))
            if img is None:
                continue
            g = cv2.cvtColor(cv2.resize(img, size, interpolation=cv2.INTER_AREA),
                             cv2.COLOR_BGR2GRAY)
            groups.setdefault(cls, []).append(g)
        for cls, imgs in sorted(groups.items()):
            avg = np.mean(imgs, axis=0).round().astype(np.uint8)
            save_cn(os.path.join(dst, f"{cls}_avg.png"), avg)
            print(f"{kind}/{cls}: {len(imgs)} 张均池化")


if __name__ == "__main__":
    main()
