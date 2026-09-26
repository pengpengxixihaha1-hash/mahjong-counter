# -*- coding: utf-8 -*-
"""探查四家出牌的桌面位置分布（一次性诊断）"""
import os

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
d = os.path.join(rf.ROOT, "samples", "pc_20260926_004419")
for fn in ["frame_0001_004421_109", "frame_0160_005450_295",
           "frame_0477_011303_813", "frame_0297_010223_913",
           "frame_0098_004927_035"]:
    fr = rf.imread_cn(os.path.join(d, fn + ".png"))
    dets = rf.extract_center(fr, fn.split("_")[1], None)
    ok = [(x[0], round(x[1], 2), x[2], x[3]) for x in dets if x[1] >= rf.CTR_ACCEPT]
    print(fn[6:11], sorted(ok, key=lambda t: (t[3], t[2])))
