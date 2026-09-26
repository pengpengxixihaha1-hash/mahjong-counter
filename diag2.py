# -*- coding: utf-8 -*-
"""检查 9/T 模板的 letter_h 与分层区域几何：画 t_l(绿)/t_s(红) 框拼图"""
import cv2
import numpy as np
import recognize_fiftyk as rf

rf.TPLS = rf.load_templates()


def tpl_montage(tpls, prefixes, path):
    tiles = []
    for cls, img, gray, fn, tlh in tpls:
        if cls[0] not in prefixes:
            continue
        th, tw = gray.shape
        t = cv2.resize(img, None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
        for (yy, xx, hh, ww), col in (((int(0.04*th), int(0.04*tw), int(0.50*th)-int(0.04*th), int(0.70*tw)-int(0.04*tw)), (0, 255, 0)),
                                      ((int(0.42*th), int(0.04*tw), int(0.88*th)-int(0.42*th), int(0.60*tw)-int(0.04*tw)), (0, 0, 255))):
            cv2.rectangle(t, (xx*3, yy*3), ((xx+ww)*3, (yy+hh)*3), col, 1)
        cv2.putText(t, f"{fn} h={tlh:.0f}", (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 255, 255), 1)
        tiles.append(t)
    if not tiles:
        print("无模板", path)
        return
    tw_ = max(t.shape[1] for t in tiles)
    th_ = max(t.shape[0] for t in tiles)
    per = 5
    rows = []
    for i in range(0, len(tiles), per):
        row = tiles[i:i + per]
        m = np.zeros((th_, sum(t.shape[1] for t in row) + 4 * len(row), 3), np.uint8)
        x = 0
        for t in row:
            m[:t.shape[0], x:x + t.shape[1]] = t
            x += t.shape[1] + 4
        rows.append(m)
    w = max(r.shape[1] for r in rows)
    m = np.zeros((sum(r.shape[0] + 4 for r in rows), w, 3), np.uint8)
    y = 0
    for r in rows:
        m[y:y + r.shape[0], :r.shape[1]] = r
        y += r.shape[0] + 4
    rf.save_cn(path, m)
    print("拼图:", path, f"({len(tiles)} 个)")


for key, prefixes, path in (("center", "9", "debug_tpl9c.png"),
                            ("center", "T", "debug_tplTc.png"),
                            ("hand", "T", "debug_tplTh.png"),
                            ("hand", "6", "debug_tpl6h.png")):
    for cls, _img, _g, fn, tlh in rf.TPLS[key]:
        if cls[0] in prefixes:
            print(f"  {key} {fn}: tlh={tlh:.1f}")
    tpl_montage(rf.TPLS[key], prefixes, path)
