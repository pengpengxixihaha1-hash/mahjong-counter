# -*- coding: utf-8 -*-
"""把 frame_0164 与 frame_0165 的 7 系检出 crop 拼图对比保存"""
import cv2
import numpy as np

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
rows = []
for fn, xs in (("frame_0164_005508_496.png", [138, 178, 219, 259]),
               ("frame_0165_005510_527.png", [179, 215, 251, 288])):
    fr = rf.imread_cn("samples\\pc_20260926_004419\\" + fn)
    for x in xs:
        # 检出 y=187~189, h=111, w=46；裁剪时向右多带 12px 看邻牌干扰
        crop = fr[187: 187 + 111, x: x + 58]
        crop = cv2.resize(crop, (58, 111))
        cv2.putText(crop, str(x), (2, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 255), 1)
        rows.append(crop)
    sep = np.full((111, 4, 3), 128, np.uint8)
    rows.append(sep)
band = np.hstack(rows)
rf.save_cn("debug_7cmp.png", band)
print("已存 debug_7cmp.png", band.shape)
