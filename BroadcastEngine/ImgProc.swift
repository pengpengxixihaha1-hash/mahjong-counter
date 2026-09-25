import Foundation
import CoreVideo

/// 灰度帧（降采样后的单通道图像）
struct GrayFrame {
    let w: Int
    let h: Int
    let px: [UInt8]   // 行优先，0~255
}

struct Blob {
    var x: Int, y: Int, w: Int, h: Int, area: Int
}

/// 图像处理工具：降采样灰度 / 白色牌块连通域 / 块内角标墨迹连通域 / 归一化匹配
enum ImgProc {

    // MARK: - CVPixelBuffer → 降采样灰度

    /// 取 Y 通道（YUV）或加权灰度（BGRA），按 stride 降采样到目标宽
    static func grayDownscale(_ pb: CVPixelBuffer, targetW: Int = 480) -> GrayFrame? {
        let srcW = CVPixelBufferGetWidth(pb)
        let srcH = CVPixelBufferGetHeight(pb)
        guard srcW > 0, srcH > 0 else { return nil }
        let stride = max(1, srcW / targetW)
        let outW = srcW / stride
        let outH = srcH / stride
        guard outW > 16, outH > 16 else { return nil }
        var px = [UInt8](repeating: 0, count: outW * outH)
        let type = CVPixelBufferGetPixelFormatType(pb)

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        if type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
            type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for oy in 0..<outH {
                let rowOff = oy * stride * bpr
                let dst = oy * outW
                for ox in 0..<outW {
                    px[dst + ox] = p[rowOff + ox * stride]
                }
            }
            // VideoRange Y∈[16,235] 拉伸到 0~255，阈值统一
            let video = type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            if video {
                for i in px.indices {
                    let v = (Int(px[i]) - 16) * 255 / 219
                    px[i] = UInt8(min(255, max(0, v)))
                }
            }
            return GrayFrame(w: outW, h: outH, px: px)
        } else if type == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for oy in 0..<outH {
                let rowOff = oy * stride * bpr
                let dst = oy * outW
                for ox in 0..<outW {
                    let off = rowOff + ox * stride * 4
                    let b = Int(p[off]), g = Int(p[off + 1]), r = Int(p[off + 2])
                    px[dst + ox] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
                }
            }
            return GrayFrame(w: outW, h: outH, px: px)
        }
        return nil
    }

    // MARK: - 白色牌块（连通域）

    /// 找白色连通域（牌面白底），返回外接矩形
    static func brightBlobs(_ f: GrayFrame, threshold: UInt8 = 190, minArea: Int = 300) -> [Blob] {
        let w = f.w, h = f.h, total = w * h
        var visited = [UInt8](repeating: 0, count: total)
        var blobs: [Blob] = []
        var stack: [Int] = []
        stack.reserveCapacity(2048)
        var minX = 0, maxX = 0, minY = 0, maxY = 0, area = 0

        for start in 0..<total where visited[start] == 0 && f.px[start] >= threshold {
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = 1
            minX = w; maxX = 0; minY = h; maxY = 0; area = 0
            while let idx = stack.popLast() {
                let x = idx % w
                let y = idx / w
                area += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if x > 0 { let n = idx - 1; if visited[n] == 0 && f.px[n] >= threshold { visited[n] = 1; stack.append(n) } }
                if x < w - 1 { let n = idx + 1; if visited[n] == 0 && f.px[n] >= threshold { visited[n] = 1; stack.append(n) } }
                if y > 0 { let n = idx - w; if visited[n] == 0 && f.px[n] >= threshold { visited[n] = 1; stack.append(n) } }
                if y < h - 1 { let n = idx + w; if visited[n] == 0 && f.px[n] >= threshold { visited[n] = 1; stack.append(n) } }
            }
            if area >= minArea {
                blobs.append(Blob(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1, area: area))
            }
        }
        return blobs
    }

    // MARK: - 区域内墨迹小块（角标字形）

    /// 在指定矩形内找深色墨迹连通域（牌角标数字），过滤出字形大小
    static func inkBlobs(_ f: GrayFrame,
                         x0: Int, y0: Int, x1: Int, y1: Int,
                         threshold: UInt8 = 165,
                         minW: Int = 5, maxW: Int = 80,
                         minH: Int = 8, maxH: Int = 90,
                         minArea: Int = 24) -> [Blob] {
        let cx0 = max(0, x0), cy0 = max(0, y0)
        let cx1 = min(f.w, x1), cy1 = min(f.h, y1)
        guard cx1 > cx0, cy1 > cy0 else { return [] }
        let rw = cx1 - cx0
        let rh = cy1 - cy0
        var visited = [UInt8](repeating: 0, count: rw * rh)
        var blobs: [Blob] = []
        var stack: [Int] = []
        stack.reserveCapacity(256)
        var minX = 0, maxX = 0, minY = 0, maxY = 0, area = 0

        for sy in 0..<rh {
            let rowBase = sy * rw
            for sx in 0..<rw {
                let start = rowBase + sx
                if visited[start] != 0 || f.px[(cy0 + sy) * f.w + cx0 + sx] >= threshold { continue }
                stack.removeAll(keepingCapacity: true)
                stack.append(start)
                visited[start] = 1
                minX = rw; maxX = 0; minY = rh; maxY = 0; area = 0
                while let idx = stack.popLast() {
                    let x = idx % rw
                    let y = idx / rw
                    area += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    let gx = cx0 + x, gy = cy0 + y
                    if x > 0 { let n = idx - 1; if visited[n] == 0 && f.px[gy * f.w + gx - 1] < threshold { visited[n] = 1; stack.append(n) } }
                    if x < rw - 1 { let n = idx + 1; if visited[n] == 0 && f.px[gy * f.w + gx + 1] < threshold { visited[n] = 1; stack.append(n) } }
                    if y > 0 { let n = idx - rw; if visited[n] == 0 && f.px[(gy - 1) * f.w + gx] < threshold { visited[n] = 1; stack.append(n) } }
                    if y < rh - 1 { let n = idx + rw; if visited[n] == 0 && f.px[(gy + 1) * f.w + gx] < threshold { visited[n] = 1; stack.append(n) } }
                }
                let bw = maxX - minX + 1
                let bh = maxY - minY + 1
                if area >= minArea, bw >= minW, bw <= maxW, bh >= minH, bh <= maxH {
                    blobs.append(Blob(x: cx0 + minX, y: cy0 + minY, w: bw, h: bh, area: area))
                }
            }
        }
        return blobs
    }

    // MARK: - 裁剪 + 归一化

    /// 取 blob 区域，墨迹紧裁剪，双线性缩放到 outW×outH，二值化归一化为 0/1 浮点
    static func normalizedGlyph(_ f: GrayFrame, blob: Blob, outW: Int = 40, outH: Int = 52,
                                inkThreshold: UInt8 = 165) -> [Float]? {
        // 1) blob 外接框内墨迹紧裁剪
        var minX = blob.x + blob.w, maxX = blob.x, minY = blob.y + blob.h, maxY = blob.y
        for y in blob.y..<(blob.y + blob.h) {
            let row = y * f.w
            for x in blob.x..<(blob.x + blob.w) {
                if f.px[row + x] < inkThreshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let cw = maxX - minX + 1
        let ch = maxY - minY + 1

        // 2) 双线性缩放 + 二值化
        var out = [Float](repeating: 0, count: outW * outH)
        for oy in 0..<outH {
            let syF = Float(oy) * Float(ch - 1) / Float(outH - 1)
            let sy0 = Int(syF)
            let sy1 = min(ch - 1, sy0 + 1)
            let fy = syF - Float(sy0)
            let row0 = (minY + sy0) * f.w
            let row1 = (minY + sy1) * f.w
            for ox in 0..<outW {
                let sxF = Float(ox) * Float(cw - 1) / Float(outW - 1)
                let sx0 = Int(sxF)
                let sx1 = min(cw - 1, sx0 + 1)
                let fx = sxF - Float(sx0)
                let v00 = Float(f.px[row0 + minX + sx0])
                let v01 = Float(f.px[row0 + minX + sx1])
                let v10 = Float(f.px[row1 + minX + sx0])
                let v11 = Float(f.px[row1 + minX + sx1])
                let top = v00 + (v01 - v00) * fx
                let bot = v10 + (v11 - v10) * fx
                let v = top + (bot - top) * fy
                // 墨迹=1（浅色背景→0）
                out[oy * outW + ox] = v < Float(inkThreshold) ? 1.0 : 0.0
            }
        }
        return normalize(out, outW: outW, outH: outH)
    }

    /// 均值 0 / 方差 1 归一化（用于 NCC 点积）
    static func normalize(_ v: [Float], outW: Int, outH: Int) -> [Float]? {
        let n = Float(v.count)
        guard n > 0 else { return nil }
        var mean: Float = 0
        for x in v { mean += x }
        mean /= n
        var variance: Float = 0
        for x in v { let d = x - mean; variance += d * d }
        variance /= n
        guard variance > 1e-4 else { return nil }
        let inv = 1 / sqrt(variance)
        var out = [Float](repeating: 0, count: v.count)
        for i in v.indices { out[i] = (v[i] - mean) * inv }
        return out
    }

    /// 两个已归一化向量的相关系数（直接点积）
    static func ncc(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in a.indices { s += a[i] * b[i] }
        return s / Float(a.count)
    }
}
