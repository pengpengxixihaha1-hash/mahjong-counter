# -*- coding: utf-8 -*-
"""微乐五十K 实时记牌器（PC 验证版）——顶栏横排显示各牌点剩余张数。

用法：
  python counter_gui.py                       # 启动后拖拽框选对局区域（与采集样本同法）
  python counter_gui.py --region 100,80,1162,697

识别管线与样本完全一致（1162x697 对局窗口坐标系），游戏窗口尺寸改变需重新框选。
显示条置顶、可拖动；ESC 或关窗退出。识别约 0.4-0.6s/帧，刷新 ~2fps。
"""
import argparse
import queue
import threading
import time

import cv2
import numpy as np

import recognize_fiftyk as rf

ORDER = ["JK", "2", "A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3"]
LABEL = {"JK": "王", "T": "10"}


def worker(region, q, stop):
    x, y, w, h = region
    rf.TPLS = rf.load_templates()
    led = rf.Ledger()
    import mss
    with mss.mss() as sct:
        while not stop.is_set():
            t0 = time.time()
            try:
                raw = np.array(sct.grab({"left": x, "top": y, "width": w, "height": h}))
                frame = cv2.cvtColor(raw, cv2.COLOR_BGRA2BGR)
                hand = rf.extract_hand(frame)
                center = rf.extract_center(frame)
                hs, ht, _g, _gs, ng = led.process_frame(hand, center)
                if ng:
                    q.put(("new",))
                seen, star = led.seen(hs, ht)
                row = {}
                for r in ORDER:
                    if r == "JK":
                        left = max(0, 4 - seen.get("JK", 0) - star.get("JK", 0))
                    else:
                        left = max(0, 8 - sum(seen.get(r + s, 0) for s in rf.SUITS)
                                   - star.get(r, 0))
                    row[r] = left
                q.put(("ok", row, led.seat_disp))
            except Exception as e:
                q.put(("err", repr(e)))
            stop.wait(max(0.0, 0.5 - (time.time() - t0)))


class Bar:
    def __init__(self, q, stop):
        self.q, self.stop = q, stop
        self.tk = tk.Tk()
        self.tk.overrideredirect(True)
        self.tk.attributes("-topmost", True)
        self.tk.configure(bg="#1b1e26")
        self.tk.geometry("+120+60")
        self.tk.bind("<Escape>", lambda e: self.quit())
        self._dx = self._dy = 0
        self.tk.bind("<Button-1>", self._down)
        self.tk.bind("<B1-Motion>", self._move)
        self.cells = {}
        for i, r in enumerate(ORDER):
            c = i + 1
            tk.Label(self.tk, text=LABEL.get(r, r), fg="#cfd3dc", bg="#1b1e26",
                     font=("Microsoft YaHei", 10), width=3).grid(row=0, column=c, padx=1, pady=(2, 0))
            v = tk.Label(self.tk, text="-", fg="#ffffff", bg="#1b1e26",
                         font=("Consolas", 12, "bold"), width=3)
            v.grid(row=1, column=c, padx=1, pady=(0, 2))
            if r in rf.SCORED:
                v.configure(fg="#ffb84d")
            self.cells[r] = v
        tk.Label(self.tk, text="五十K", fg="#8a90a0", bg="#1b1e26",
                 font=("Microsoft YaHei", 9)).grid(row=0, column=0, rowspan=2, padx=6)
        self.status = tk.Label(self.tk, text="识别中...", fg="#8a90a0", bg="#1b1e26",
                               font=("Microsoft YaHei", 8))
        self.status.grid(row=2, column=0, columnspan=len(ORDER) + 1, sticky="w", padx=6)
        # 四家流水行：对/上/下/我 剩余张数 + 最近出牌（紧凑串）
        self.seat_lbl = {}
        for i, tag in enumerate(("对", "上", "下", "我")):
            v = tk.Label(self.tk, text=f"{tag} 27", fg="#9fc4e8", bg="#1b1e26",
                         font=("Microsoft YaHei", 9), anchor="w", width=30)
            v.grid(row=3 + i, column=0, columnspan=len(ORDER) + 1, sticky="w", padx=6)
            self.seat_lbl[tag] = v
        self.tk.after(250, self.tick)

    def _down(self, e):
        self._dx, self._dy = e.x, e.y

    def _move(self, e):
        self.tk.geometry(f"+{e.x_root - self._dx}+{e.y_root - self._dy}")

    def tick(self):
        try:
            while True:
                item = self.q.get_nowait()
                if item[0] == "ok":
                    for r, v in item[1].items():
                        self.cells[r].configure(text=str(v))
                    if len(item) > 2 and item[2]:
                        for tag, left, cards in item[2]:
                            self.seat_lbl[tag].configure(
                                text=f"{tag} {left}" + (f"  {cards}" if cards else ""))
                    self.status.configure(text=f"更新 {time.strftime('%H:%M:%S')}")
                elif item[0] == "new":
                    self.status.configure(text="新一局，牌账已重置")
                elif item[0] == "err":
                    self.status.configure(text=f"错误: {item[1][:60]}")
        except queue.Empty:
            pass
        self.tk.after(250, self.tick)

    def run(self):
        self.tk.mainloop()

    def quit(self):
        self.stop.set()
        self.tk.destroy()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="")
    args = ap.parse_args()

    if args.region:
        region = tuple(int(v) for v in args.region.split(","))
    else:
        import mss
        with mss.mss() as sct:
            mon = sct.monitors[1]
            raw = np.array(sct.grab(mon))
        frame = cv2.cvtColor(raw, cv2.COLOR_BGRA2BGR)
        print("拖拽框选对局区域（游戏窗口），按 ENTER 确认")
        rx, ry, rw, rh = cv2.selectROI("框选对局区域后按 ENTER", frame, showCrosshair=True)
        cv2.destroyAllWindows()
        if rw == 0:
            print("未框选，退出")
            return
        region = (mon["left"] + rx, mon["top"] + ry, rw, rh)

    q = queue.Queue()
    stop = threading.Event()
    threading.Thread(target=worker, args=(region, q, stop), daemon=True).start()
    Bar(q, stop).run()


if __name__ == "__main__":
    main()
