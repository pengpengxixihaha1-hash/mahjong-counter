# -*- coding: utf-8 -*-
"""从 frame_0165（7C/7H 判 0.99，质量高）重裁替换中央 7C_1 / 7H_1"""
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0165_005510_527.png")
dets = rf.extract_center(fr)
for d in dets:
    print(f"{d[0]}({'*' if d[6]=='star' else ''}{d[1]:.2f}) x={d[2]} y={d[3]} w={d[4]} h={d[5]}")

for target, fn in (("7C", "7C_1.png"), ("7H", "7H_1.png")):
    cands = [d for d in dets if d[0] == target and d[1] >= 0.97 and not d[6] == "star"]
    assert cands, f"{target} 无高质量检出"
    d = cands[0]
    crop = fr[d[3]: d[3] + d[5], d[2]: d[2] + d[4]]
    rf.save_cn(rf.CTR_TPL_DIR + "\\" + fn, crop)
    print(f"已覆盖 {fn} <- x={d[2]} {d[0]}({d[1]:.2f})")
