import CoreVideo
import Foundation

// 屏幕识别 —— 手机版真实识别（几何与 recognize_phone.py 逐项对齐）。
// 参考坐标系 2556x1179 横屏，实际帧按 (W/2556, H/1179) 等比缩放。
// 输入：ReplayKit 帧缓冲（420YpCbCr8BiPlanar Video/FullRange 或 32BGRA）。
// 流程：
//   1. 手牌带 y741-955：字形掩码（gray<150 | 红）列投影 → 聚簇 → 裁剪 [a-10,a+70]x[214]
//   2. 中央白框 y150-735：白掩码（min(r,g,b)>185）连通域（半分辨率）→ 牌堆框
//      → 框内顶 55% 字形列投影 → 裁剪 [a-6,a+50]x[108]
//   3. classifyHand（平均模板单尺度）/ classifyCenter（两级匹配）→ 检出
// 竖屏帧（H>W）不识别（游戏为横屏；返回 nil 由调用方保持状态展示）。
final class ScreenRecognizer {
    struct Result {
        var hand: [CardDetection]
        var center: [CardDetection]
    }

    /// 参考几何（2556x1179 原生像素），数值 = recognize_phone.py 常量
    private enum Geo {
        static let refW: Float = 2556
        static let refH: Float = 1179
        static let handY0: Float = 741
        static let handH: Float = 214
        static let bandY0: Float = 746
        static let bandY1: Float = 798
        static let handX0: Float = 120
        static let handX1: Float = 2440
        static let playY0: Float = 150
        static let playY1: Float = 735
        /// UI 固定块（头像/按钮）排除（x, y, w, h）
        static let uiBoxes: [(Float, Float, Float, Float)] = [
            (1619, 70, 102, 91), (2300, 273, 129, 129), (1592, 75, 129, 86),
        ]
    }

    private let matcher = CardMatcher()

    var templatesLoaded: Bool {
        !matcher.handTemplates.isEmpty && !matcher.centerTemplates.isEmpty
    }

    init() {
        matcher.loadTemplates()
    }

    // MARK: - 帧指纹（静态帧跳过用）

    /// 低成本帧指纹：Y 平面网格采样（BGRA 帧用亮度近似）。竖屏帧返回 nil。
    func fingerprint(_ pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        let W = CVPixelBufferGetWidth(pixelBuffer)
        let H = CVPixelBufferGetHeight(pixelBuffer)
        guard W >= H else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        var out: [UInt8] = []
        let xs = 24, ys = 16
        out.reserveCapacity((W / xs + 1) * (H / ys + 1))
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yp = yBase.assumingMemoryBound(to: UInt8.self)
            for y in stride(from: 0, to: H, by: ys) {
                for x in stride(from: 0, to: W, by: xs) {
                    out.append(yp[y * yStride + x])
                }
            }
        } else {
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let strideBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in stride(from: 0, to: H, by: ys) {
                for x in stride(from: 0, to: W, by: xs) {
                    let o = y * strideBytes + x * 4
                    let lum = (299 * Int(p[o + 2]) + 587 * Int(p[o + 1]) + 114 * Int(p[o])) / 1000
                    out.append(UInt8(max(0, min(255, lum))))
                }
            }
        }
        return out
    }

    // MARK: - 单帧识别

    func process(_ pixelBuffer: CVPixelBuffer) -> Result? {
        let W = CVPixelBufferGetWidth(pixelBuffer)
        let H = CVPixelBufferGetHeight(pixelBuffer)
        guard W >= H, let planes = FramePlanes(pixelBuffer) else { return nil }
        let sx = Float(W) / Geo.refW
        let sy = Float(H) / Geo.refH
        var hand = extractHand(planes, sx: sx, sy: sy)
        let center = extractCenter(planes, sx: sx, sy: sy)
        hand.removeAll { $0.cls == "?" }
        return Result(hand: hand, center: center)
    }

    // MARK: - 手牌区

    private func extractHand(_ planes: FramePlanes, sx: Float, sy: Float) -> [CardDetection] {
        let W = planes.width
        let y0 = Int(Geo.bandY0 * sy), y1 = Int(Geo.bandY1 * sy)
        guard y1 > y0 else { return [] }
        var cols = [Int](repeating: 0, count: W)
        for y in y0..<y1 {
            for x in 0..<W {
                let (r, g, b) = planes.rgb(x, y)
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                if gray < 150 || (r - b > 70 && r > 110) {
                    cols[x] += 1
                }
            }
        }
        let clusters = CardMatcher.glyphClusters(bandDark: cols, mergeGap: max(4, Int(12 * sx)),
                                                 minW: max(8, Int(20 * sx)))
        let cx0 = Int(Geo.handX0 * sx), cx1 = Int(Geo.handX1 * sx)
        let cy0 = Int(Geo.handY0 * sy), ch = Int(Geo.handH * sy)
        var out: [CardDetection] = []
        for (a, b) in clusters {
            guard a >= cx0, b <= cx1 else { continue }
            let x0 = max(0, a - Int(10 * sx)), x1 = a + Int(70 * sx)
            guard x1 - x0 >= Int(60 * sx) else { continue }
            let cw = x1 - x0
            var gray = [Float](repeating: 0, count: ch * cw)
            for dy in 0..<ch {
                let row = dy * cw
                for dx in 0..<cw {
                    let (r, g, bl) = planes.rgb(x0 + dx, cy0 + dy)
                    gray[row + dx] = 0.299 * r + 0.587 * g + 0.114 * bl
                }
            }
            let crop = CropPixels(w: cw, h: ch, gray: gray)
            let res = matcher.classifyHand(crop, accept: 0.60, minLH: 30)
            out.append(CardDetection(cls: res.cls, score: res.score, x: a, y: cy0))
        }
        return out
    }

    // MARK: - 中央区

    private func extractCenter(_ planes: FramePlanes, sx: Float, sy: Float) -> [CardDetection] {
        let W = planes.width, H = planes.height
        let py0 = Int(Geo.playY0 * sy), py1 = min(Int(Geo.playY1 * sy), H)
        guard py1 > py0 else { return [] }
        // 白掩码（Python: r,g,b 全 >185），OR 降采样到半分辨率
        let hw = (W + 1) / 2, hh = (H + 1) / 2
        var white = [Bool](repeating: false, count: hw * hh)
        for y in py0..<py1 {
            let hrow = (y >> 1) * hw
            for x in 0..<W {
                let (r, g, b) = planes.rgb(x, y)
                if r > 185 && g > 185 && b > 185 {
                    white[hrow + (x >> 1)] = true
                }
            }
        }
        // 连通域（8 连通，半分辨率）→ 牌堆框（换算回原生坐标）
        var label = [Int32](repeating: -1, count: hw * hh)
        var stack: [Int] = []
        var boxes: [(x: Int, y: Int, w: Int, h: Int)] = []
        var next: Int32 = 0
        for i in 0..<(hw * hh) where white[i] && label[i] < 0 {
            stack.removeAll(keepingCapacity: true)
            stack.append(i)
            label[i] = next
            var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
            while let cur = stack.popLast() {
                let cy = cur / hw, cx = cur % hw
                if cx < minX { minX = cx }
                if cx > maxX { maxX = cx }
                if cy < minY { minY = cy }
                if cy > maxY { maxY = cy }
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < hw, ny >= 0, ny < hh else { continue }
                        let ni = ny * hw + nx
                        if white[ni] && label[ni] < 0 {
                            label[ni] = next
                            stack.append(ni)
                        }
                    }
                }
            }
            next += 1
            let bx = minX * 2, by = minY * 2
            let bw = (maxX - minX + 1) * 2, bh = (maxY - minY + 1) * 2
            if bw < Int(100 * sx) || bh < Int(150 * sy) { continue }
            // UI 固定块排除（顶左坐标比对，与 Python 一致）
            let isUI = Geo.uiBoxes.contains { (ux, uy, _, _) in
                abs(Float(bx) - ux) < 8 && abs(Float(by) - uy) < 8
            }
            if isUI { continue }
            boxes.append((bx, by, bw, bh))
        }

        var out: [CardDetection] = []
        for box in boxes {
            let (bx, by, bw, bh) = (box.x, box.y, box.w, box.h)
            // 框内顶 55% 行的字形列投影
            let gy1 = min(by + Int(0.55 * Float(bh)), H)
            var cols = [Int](repeating: 0, count: bw)
            for y in by..<gy1 {
                for dx in 0..<bw {
                    let (r, g, b) = planes.rgb(bx + dx, y)
                    let gray = 0.299 * r + 0.587 * g + 0.114 * b
                    if gray < 150 || (r - b > 70 && r > 110) {
                        cols[dx] += 1
                    }
                }
            }
            let clusters = CardMatcher.glyphClusters(bandDark: cols,
                                                     mergeGap: max(3, Int(6 * sx)),
                                                     minW: max(8, Int(15 * sx)),
                                                     splitW: Int(58 * sx),
                                                     splitAt: Int(56 * sx))
            for (a, b) in clusters {
                // 字形顶行：全框高内 [a-4, b+5) 列 glyph 数 > 1 的首行
                let ca = max(0, a - Int(4 * sx)), cb = min(bw - 1, b + Int(5 * sx))
                var top = -1
                for y in by..<min(by + bh, H) {
                    var cnt = 0
                    for x in ca...cb {
                        let (r, g, bl) = planes.rgb(bx + x, y)
                        let gray = 0.299 * r + 0.587 * g + 0.114 * bl
                        if gray < 150 || (r - bl > 70 && r > 110) { cnt += 1 }
                    }
                    if cnt > 1 {
                        top = y
                        break
                    }
                }
                guard top >= 0 else { continue }
                let cy0 = max(0, top - Int(2 * sy)), cy1 = top + Int(108 * sy)
                let cx0 = max(0, a - Int(6 * sx)), cx1 = a + Int(50 * sx)
                guard cy1 - cy0 >= Int(60 * sy), cx1 - cx0 >= Int(30 * sx) else { continue }
                let cw = cx1 - cx0, chh = cy1 - cy0
                var gray = [Float](repeating: 0, count: chh * cw)
                for dy in 0..<chh {
                    let row = dy * cw
                    for dx in 0..<cw {
                        let (r, g, bl) = planes.rgb(bx + cx0 + dx, cy0 + dy)
                        gray[row + dx] = 0.299 * r + 0.587 * g + 0.114 * bl
                    }
                }
                let crop = CropPixels(w: cw, h: chh, gray: gray)
                let res = matcher.classifyCenter(crop, accept: 0.55, minLH: 12)
                out.append(CardDetection(cls: res.cls, score: res.score, x: bx + a, y: top))
            }
        }
        return out
    }
}

// MARK: - 帧平面访问

/// CVPixelBuffer 平面只读访问：420YpCbCr8BiPlanar（Video/FullRange）或 32BGRA。
/// rgb(x,y) 返回全幅 RGB（BT.601 视频域转换，与 cv2 灰度/阈值口径一致）。
/// 生命周期内持锁，必须在调用方的 autoreleasepool 中即建即用。
final class FramePlanes {
    let width: Int
    let height: Int
    private let pb: CVPixelBuffer
    private let is420: Bool
    private let yBase: UnsafePointer<UInt8>?
    private let yStride: Int
    private let cBase: UnsafePointer<UInt8>?
    private let cStride: Int
    private let bgraBase: UnsafePointer<UInt8>?
    private let bgraStride: Int

    init?(_ pixelBuffer: CVPixelBuffer) {
        pb = pixelBuffer
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        is420 = fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        if is420 {
            guard let y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let c = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                return nil
            }
            yBase = UnsafePointer(y.assumingMemoryBound(to: UInt8.self))
            yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            cBase = UnsafePointer(c.assumingMemoryBound(to: UInt8.self))
            cStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            bgraBase = nil
            bgraStride = 0
        } else {
            guard let b = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                return nil
            }
            yBase = nil
            yStride = 0
            cBase = nil
            cStride = 0
            bgraBase = UnsafePointer(b.assumingMemoryBound(to: UInt8.self))
            bgraStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        }
    }

    deinit {
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    }

    /// 全幅 RGB（r, g, b）
    func rgb(_ x: Int, _ y: Int) -> (Float, Float, Float) {
        if is420, let yb = yBase, let cb_ = cBase {
            let Y = Float(yb[y * yStride + x]) - 16
            let o = (y >> 1) * cStride + (x >> 1) * 2
            let cb = Float(cb_[o]) - 128
            let cr = Float(cb_[o + 1]) - 128
            let yy = 1.164 * Y
            return (yy + 1.596 * cr, yy - 0.392 * cb - 0.813 * cr, yy + 2.017 * cb)
        }
        if let base = bgraBase {
            let o = y * bgraStride + x * 4
            return (Float(base[o + 2]), Float(base[o + 1]), Float(base[o]))
        }
        return (0, 0, 0)
    }
}
