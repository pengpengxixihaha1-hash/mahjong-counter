# -*- coding: utf-8 -*-
"""抽检局6 段内5帧的中央JK检出，确认王的桌面连续性（一次性诊断脚本）"""
import os

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
d = os.path.join(rf.ROOT, "samples", "pc_20260926_004419")
for fn in ["frame_0144_005241_112", "frame_0154_005426_030",
           "frame_0160_005450_295", "frame_0162_005456_373",
           "frame_0167_005514_595"]:
    fr = rf.imread_cn(os.path.join(d, fn + ".png"))
    dets = rf.extract_center(fr, fn.split("_")[1], None)
    ok = [x for x in dets if x[1] >= rf.CTR_ACCEPT]
    jks = [(round(x[1], 2), x[2], x[3]) for x in ok if x[0] == "JK"]
    others = sorted((x[0], round(x[1], 2), x[2]) for x in ok if x[0] != "JK")
    print(fn[:11], "| JK:", jks)
    print("   其他:", others)
