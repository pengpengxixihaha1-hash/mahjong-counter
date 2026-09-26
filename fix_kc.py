# -*- coding: utf-8 -*-
"""用 frame_0323 中央检出重裁 KC_1（坏模板 s_l 0.759 → 真 K♣ x=901），并打印全检出验证 JK_2"""
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0323_010326_852.png")
dets = rf.extract_center(fr)
for d in dets:
    print(f"{d[0]}({d[1]:.2f}) x={d[2]} y={d[3]} w={d[4]} h={d[5]} {d[6]}")

# 目标：x=901 精确命中（真 K♣，当前被误判为 KS）
cands = [d for d in dets if d[2] == 901]
assert cands, "x=901 附近无检出"
d = cands[0]
crop = fr[d[3]: d[3] + d[5], d[2]: d[2] + d[4]]
rf.save_cn(rf.CTR_TPL_DIR + "\\KC_1.png", crop)
print(f"\n已覆盖 KC_1.png <- x={d[2]} 原判 {d[0]}({d[1]:.2f}) crop={crop.shape}")
