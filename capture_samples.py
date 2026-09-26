# -*- coding: utf-8 -*-
"""
对局样本截图采集脚本（微乐江西麻将记牌器 · 样本采集阶段）

用途：边打对局边自动截图，积累 P2 阶段做识别模板与验收用的样本图。
     相邻帧变化小于阈值时自动跳过，避免存下上千张重复图。

两种模式：
  1) PC 模式（默认）：截取本机"微信PC版里的微乐"画面
     python capture_samples.py                       # 启动后弹出预览，鼠标框选对局区域，按 ENTER 开始
     python capture_samples.py --region 100,80,1200,700
     python capture_samples.py --full                # 全屏采集

  2) iOS 模式：通过 USB 连接 iPhone，用 pymobiledevice3 定时截图
     pip install pymobiledevice3   # 首次需安装，iPhone 需信任电脑并配对
     python capture_samples.py --ios --interval 3

常用参数：
  --interval 2        截图间隔秒数（默认 2）
  --diff-threshold 3  变化阈值(0~255均值)，越小越灵敏，存图越多
  --out samples\\xxx  输出目录（默认 samples/pc_时间戳 或 samples/ios_时间戳）
  --max 30            最多保存多少张后自动停止
  --duration 600      采集多少秒后自动停止

停止：Ctrl+C，结束时会打印保存统计。
注意：iOS 模式截图时手机必须亮屏、解锁、停留在对局界面。
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))


def parse_args():
    p = argparse.ArgumentParser(description="对局样本截图采集")
    p.add_argument("--ios", action="store_true", help="使用 iPhone USB 截图模式")
    p.add_argument("--interval", type=float, default=2.0, help="截图间隔（秒）")
    p.add_argument("--diff-threshold", type=float, default=3.0,
                   help="画面变化阈值，低于该值跳过保存（PC 模式）")
    p.add_argument("--region", type=str, default="",
                   help='采集区域 "x,y,w,h"（PC 模式；留空则交互框选）')
    p.add_argument("--full", action="store_true", help="全屏采集（PC 模式）")
    p.add_argument("--monitor", type=int, default=1, help="显示器编号（PC 模式，1=主屏）")
    p.add_argument("--out", type=str, default="", help="输出目录")
    p.add_argument("--max", type=int, default=0, help="最多保存张数（0=不限）")
    p.add_argument("--duration", type=float, default=0, help="采集时长秒数（0=不限）")
    return p.parse_args()


def make_outdir(args, tag):
    out = args.out or os.path.join(ROOT, "samples", f"{tag}_{datetime.now():%Y%m%d_%H%M%S}")
    os.makedirs(out, exist_ok=True)
    return out


def save_png(img, path):
    """兼容中文路径的 PNG 保存（cv2.imwrite 在中文目录下会失败）"""
    import cv2
    ok, buf = cv2.imencode(".png", img)
    if ok:
        buf.tofile(path)
    return ok


# ---------------------------------------------------------------- PC 模式

def resolve_region(args):
    import cv2
    import mss
    import numpy as np

    with mss.mss() as sct:
        mon = sct.monitors[args.monitor]
        raw = np.array(sct.grab(mon))
    frame = cv2.cvtColor(raw, cv2.COLOR_BGRA2BGR)

    if args.full:
        return mon["left"], mon["top"], mon["width"], mon["height"]
    if args.region:
        x, y, w, h = [int(v) for v in args.region.split(",")]
        return x, y, w, h

    print("请在预览窗口拖拽框选对局区域，然后按 ENTER 确认（ESC 取消改用全屏）")
    rx, ry, rw, rh = cv2.selectROI("框选对局区域后按 ENTER", frame, showCrosshair=True)
    cv2.destroyAllWindows()
    if rw == 0 or rh == 0:
        print("未选择区域，改用全屏")
        return mon["left"], mon["top"], mon["width"], mon["height"]
    # selectROI 返回的是相对预览图的坐标，预览图本身取自主显示器原点
    return mon["left"] + rx, mon["top"] + ry, rw, rh


def pc_mode(args):
    import cv2
    import mss
    import numpy as np

    x, y, w, h = resolve_region(args)
    print(f"采集区域: x={x} y={y} w={w} h={h}  间隔={args.interval}s  阈值={args.diff_threshold}")

    out = make_outdir(args, "pc")
    print(f"输出目录: {out}\n开始采集，Ctrl+C 停止...")

    saved = skipped = 0
    last_gray = None
    t0 = time.time()
    try:
        with mss.mss() as sct:
            while True:
                time.sleep(args.interval)
                if args.duration and time.time() - t0 > args.duration:
                    break
                raw = np.array(sct.grab({"left": x, "top": y, "width": w, "height": h}))
                frame = cv2.cvtColor(raw, cv2.COLOR_BGRA2BGR)

                small = cv2.resize(frame, (320, max(1, int(320 * h / w))))
                gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
                if last_gray is not None:
                    diff = float(np.mean(cv2.absdiff(gray, last_gray)))
                    if diff < args.diff_threshold:
                        skipped += 1
                        continue
                last_gray = gray

                saved += 1
                ts = datetime.now().strftime("%H%M%S_%f")[:-3]
                save_png(frame, os.path.join(out, f"frame_{saved:04d}_{ts}.png"))
                print(f"[已保存 {saved:4d}] 跳过 {skipped} 帧", end="\r")
                if args.max and saved >= args.max:
                    break
    except KeyboardInterrupt:
        pass
    print(f"\n完成：保存 {saved} 张，跳过 {skipped} 帧，目录 {out}")


# ---------------------------------------------------------------- iOS 模式

def find_ios_cli():
    exe = shutil.which("pymobiledevice3")
    if exe:
        return [exe]
    return [sys.executable, "-m", "pymobiledevice3"]


def ios_mode(args):
    out = make_outdir(args, "ios")
    print(f"输出目录: {out}")
    print("开始采集 iPhone 截图（手机需亮屏解锁、停留在对局界面），Ctrl+C 停止...")

    cmd = find_ios_cli() + ["screenshot"]
    saved = failed = 0
    t0 = time.time()
    try:
        while True:
            saved += 1
            ts = datetime.now().strftime("%H%M%S_%f")[:-3]
            path = os.path.join(out, f"ios_{saved:04d}_{ts}.png")
            r = subprocess.run(cmd + [path], capture_output=True, text=True)
            if r.returncode == 0 and os.path.exists(path):
                print(f"[已保存 {saved:4d}] 失败 {failed}", end="\r")
            else:
                saved -= 1
                failed += 1
                msg = (r.stderr or r.stdout or "").strip().splitlines()
                print(f"\n[失败] {msg[-1] if msg else '未知错误'}"
                      f"（检查：手机是否解锁亮屏/是否已信任配对/数据线）")
            if args.max and saved >= args.max:
                break
            if args.duration and time.time() - t0 > args.duration:
                break
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    print(f"\n完成：保存 {saved} 张，失败 {failed} 次，目录 {out}")


def main():
    args = parse_args()
    if args.ios:
        ios_mode(args)
    else:
        pc_mode(args)


if __name__ == "__main__":
    main()
