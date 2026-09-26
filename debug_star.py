# -*- coding: utf-8 -*-
"""debug：7★/5★ 检出 crop 的星标检测中间量"""
import cv2
import numpy as np

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0165_005510_527.png")
dets = rf.extract_center(fr)
# 7★ 在上排第 4 张（x 最大），5★ 在下排右 3 张
targets = [d for d in dets if d[0] in ("7D", "5D")]
for d in targets:
    x, y, w, h = d[2], d[3], d[4], d[5]
    crop = fr[y: y + h, x: x + w]
    size = rf.CTR_SIZE
    c2 = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(c2, cv2.COLOR_BGR2GRAY)
    c2, g = rf._trim_top_band(c2, g)
    H, W = g.shape
    f16 = c2.astype(np.int16)
    zone = np.zeros((H, W), bool)
    zone[int(0.05 * H):int(0.85 * H), int(0.05 * W):int(0.62 * W)] = True
    pzone = zone.copy()
    pzone[:int(0.42 * H), :] = False
    pzone[int(0.78 * H):, :] = False
    orange_p = ((f16[:, :, 2] > 180) & (f16[:, :, 1] > 80) & (f16[:, :, 1] < 190) &
                (f16[:, :, 0] < 110) & pzone)
    ratio = float(orange_p.sum()) / (H * W)
    # 橙色全图统计（不限 pzone）
    o_full = ((f16[:, :, 2] > 180) & (f16[:, :, 1] > 80) & (f16[:, :, 1] < 190) &
              (f16[:, :, 0] < 110) & zone)
    print(f"{d[0]}({d[1]:.2f}) x={x} trim后H={H} orange_p={int(orange_p.sum())} "
          f"ratio={ratio:.4f} (阈值0.02) orange_zone全图={int(o_full.sum())}")
