# -*- coding: utf-8 -*-
"""批量导出簇代表（带 ID 标注）：python debug_passb.py <kind> <起> <止>
kind=H/C，输出 sheet_check_<kind>_<起>.png，每行 5 个"""
import sys, json, cv2
import numpy as np
from recognize_fiftyk import imread_cn, save_cn

kind, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
d = json.load(open('templates/unknown/clusters.json', encoding='utf-8'))
cls = d['hand' if kind == 'H' else 'center']
tiles = []
for i in range(a, min(b, len(cls))):
    rep = cls[i]['rep_file']
    img = imread_cn(f'templates/unknown/{rep}')
    img = cv2.resize(img, (img.shape[1] * 2, img.shape[0] * 2), interpolation=cv2.INTER_NEAREST)
    cv2.putText(img, f"{kind}{i} n={cls[i]['n']}", (2, img.shape[0] - 6),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 255), 2)
    tiles.append(img)
if not tiles:
    print('empty'); sys.exit(0)
COLS = 5
cw = max(t.shape[1] for t in tiles) + 6
ch = max(t.shape[0] for t in tiles) + 6
rows = (len(tiles) + COLS - 1) // COLS
canvas = np.full((rows * ch, COLS * cw, 3), 40, np.uint8)
for k, t in enumerate(tiles):
    r, c = divmod(k, COLS)
    canvas[r * ch: r * ch + t.shape[0], c * cw: c * cw + t.shape[1]] = t
save_cn(f'sheet_check_{kind}_{a}.png', canvas)
print(f'sheet_check_{kind}_{a}.png  clusters {a}-{min(b, len(cls))-1}')
