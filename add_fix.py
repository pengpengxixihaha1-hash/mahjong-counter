# -*- coding: utf-8 -*-
"""从 f0477/f0026 保存 TS_2 与 6C/6D 手牌模板（已目检真身）"""
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()

S = "samples\\pc_20260926_004419"
jobs = [
    (S + "\\frame_0477_011303_813.png", 523, "TS_2"),   # 10♠
    (S + "\\frame_0026_004530_042.png", 604, "6C_1"),   # 6♣
    (S + "\\frame_0026_004530_042.png", 658, "6C_2"),   # 6♣
    (S + "\\frame_0026_004530_042.png", 713, "6D_1"),   # 6♦
]
for fp, x, name in jobs:
    fr = rf.imread_cn(fp)
    hit = [d for d in rf.extract_hand(fr) if d[2] == x]
    if not hit:
        raise SystemExit(f"{name}: 未找到 x={x}")
    d = hit[0]
    c = fr[d[3]:d[3] + d[5], d[2]:d[2] + d[4]]
    rf.save_cn(rf.HAND_TPL_DIR + "\\" + name + ".png", c)
    print(f"已存 hand/{name}.png  <- {d[0]}({d[1]:.2f}) x={x} shape={c.shape}")
