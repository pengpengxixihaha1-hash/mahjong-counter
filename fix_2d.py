# -*- coding: utf-8 -*-
"""颜色错位扫描：检出类别颜色与裁剪实测颜色矛盾的（缺失类真身在此），哈希去重拼图"""
import hashlib
import os

import cv2
import numpy as np

import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()
D = "samples\\pc_20260926_004419"
os.makedirs("midband", exist_ok=True)
for f in os.listdir("midband"):
    os.remove(os.path.join("midband", f))


def crop_color(crop, size):
    c2 = cv2.resize(crop, size, interpolation=cv2.INTER_AREA)
    g = cv2.cvtColor(c2, cv2.COLOR_BGR2GRAY)
    H, W = g.shape
    f16 = c2.astype(np.int16)
    zone = np.zeros((H, W), bool)
    zone[int(0.05 * H):int(0.85 * H), int(0.05 * W):int(0.62 * W)] = True
    orange = ((f16[:, :, 2] > 180) & (f16[:, :, 1] > 80) & (f16[:, :, 1] < 190) &
              (f16[:, :, 0] < 110) & zone)
    dark = (g < 160) & zone & ~orange
    if int(dark.sum()) < 40:
        return "?"
    red = ((f16[:, :, 2] - f16[:, :, 0]) > 70) & (f16[:, :, 2] > 110) & zone & ~orange
    ratio = float(red.sum()) / max(1, int(dark.sum()))
    return "red" if ratio > 0.40 else ("black" if ratio < 0.15 else "?")


COLOR = {"S": "black", "C": "black", "H": "red", "D": "red"}
seen = set()
items = []
for fn in sorted(os.listdir(D)):
    if not fn.endswith(".png"):
        continue
    fr = rf.imread_cn(os.path.join(D, fn))
    if fr is None:
        continue
    for key_prefix, dets, size, lo in (("h", rf.extract_hand(fr), rf.HAND_SIZE, 0.60),
                                       ("c", rf.extract_center(fr), rf.CTR_SIZE, 0.75)):
        for d in dets:
            cls, score, x, y, w, h, flag = d
            if flag == "star" or score < lo or cls == "JK" or cls == "?":
                continue
            if COLOR[cls[1]] != crop_color(fr[y:y + h, x:x + w], size):
                crop = fr[y:y + h, x:x + w]
                key = key_prefix + hashlib.md5(cv2.resize(crop, (20, 60)).tobytes()).hexdigest()[:10]
                if key not in seen:
                    seen.add(key)
                    items.append((f"{key_prefix}_{cls}_{int(score * 100)}_{fn[6:14]}_{x}.png", crop))

print(f"颜色错位去重后 {len(items)} 张")
for name, crop in items:
    rf.save_cn(os.path.join("midband", name), crop)

files = sorted(os.listdir("midband"))
CELL_W, CELL_H, LABEL, COLS, ROWS = 92, 222, 24, 9, 3
per = COLS * ROWS
for si in range((len(files) + per - 1) // per):
    chunk = files[si * per: (si + 1) * per]
    rows = (len(chunk) + COLS - 1) // COLS
    sheet = np.full((rows * (CELL_H + LABEL) + LABEL, COLS * CELL_W, 3), 245, np.uint8)
    for i, f in enumerate(chunk):
        img = rf.imread_cn(os.path.join("midband", f))
        r, c = divmod(i, COLS)
        x0, y0 = c * CELL_W, r * (CELL_H + LABEL) + LABEL
        big = cv2.resize(img, (CELL_W - 4, CELL_H - 4), interpolation=cv2.INTER_NEAREST)
        sheet[y0:y0 + big.shape[0], x0 + 2:x0 + 2 + big.shape[1]] = big
        cv2.putText(sheet, f[:-4], (x0 + 2, y0 - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.34, (0, 0, 200), 1)
    rf.save_cn(f"midband_{si}.png", sheet)
    print(f"midband_{si}.png: {len(chunk)} 张")
