# -*- coding: utf-8 -*-
"""从 f0097 最右侧手牌（真身5♥）裁剪保存 5H_2"""
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
fr = rf.imread_cn("samples\\pc_20260926_004419\\frame_0097_004918_954.png")
d = max(rf.extract_hand(fr), key=lambda t: t[2])
print(f"最右检出: {d[0]}({d[1]:.2f}) x={d[2]} y={d[3]}")
c = fr[d[3]:d[3] + d[5], d[2]:d[2] + d[4]]
rf.save_cn(rf.HAND_TPL_DIR + "\\5H_2.png", c)
print("已存 hand/5H_2.png", c.shape)
