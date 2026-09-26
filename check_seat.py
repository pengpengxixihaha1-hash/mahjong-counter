# -*- coding: utf-8 -*-
"""验证四家分账 seat_disp（一次性诊断）"""
import os

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
led = rf.Ledger()
d = os.path.join(rf.ROOT, "samples", "pc_20260926_004419")
for fn in ["frame_0001_004421_109", "frame_0098_004927_035",
           "frame_0160_005450_295", "frame_0477_011303_813"]:
    fr = rf.imread_cn(os.path.join(d, fn + ".png"))
    tag = fn.split("_")[1]
    led.process_frame(rf.extract_hand(fr, tag, False), rf.extract_center(fr, tag, False))
    print(fn[6:11], "=>", led.seat_disp)
