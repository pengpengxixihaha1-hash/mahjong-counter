import CoreGraphics
import Foundation
import ImageIO
import Accelerate

// 牌面模板匹配引擎 —— PC 版 classify() 的移植（布局无关部分）。
//
// 已移植（与 PC 语义一致，均为踩坑结论，勿轻改）：
//   · _letter_h：字形行高测量（阈值150/断口容忍5/跳顶部全宽暗边带）
//   · _trim_top_band：裁顶部全宽暗行（扇形裁剪带入的相邻牌边框，压死 NCC 的根因）
//   · find_glyph_clusters：列投影聚簇（含超宽簇等分）
//   · classify：尺度归一 + 分层匹配（字母区定牌点、花色区定花色）+
//     颜色先验罚分（跨色 -0.50）+ 星标检测（pip 区橙色占比）
//
// 待阶段 3 优化：nccMax 为朴素滑窗实现（vDSP 逐行点积），真机几何定下来后
// 视性能需要换积分图/FFT。
struct GrayImage {
    var w: Int
    var h: Int
    var p: [Float]   // 行主序 0-255
}

struct CropPixels {
    var w: Int
    var h: Int
    var gray: [Float]
    var r: [Float]
    var g: [Float]
    var b: [Float]
}

final class CardMatcher {
    struct Template {
        let cls: String
        let name: String
        let gray: GrayImage
        let letterH: Float
    }

    struct ClassifyResult {
        let cls: String
        let score: Double
        let star: Bool
    }

    // 归一化尺寸：与 PC templates 一致（手牌角标 42x130 / 中央角标 46x111）
    static let handSize = (w: 42, h: 130)
    static let centerSize = (w: 46, h: 111)
    /// 固定尺度阶梯：中央牌面渲染尺度随张数变化，阶梯全覆盖让 NCC 自己选最优
    static let scaleLadder: [Float] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.4]
    static let pad = 14

    private(set) var handTemplates: [Template] = []
    private(set) var centerTemplates: [Template] = []

    // MARK: - 模板加载（bundle Templates/hand|center/*.png，命名 类_序.png）

    func loadTemplates(bundle: Bundle = .main) {
        handTemplates = load("Templates/hand", size: Self.handSize, bundle: bundle)
        centerTemplates = load("Templates/center", size: Self.centerSize, bundle: bundle)
    }

    private func load(_ sub: String, size: (Int, Int), bundle: Bundle) -> [Template] {
        guard let urls = bundle.urls(forResourcesWithExtension: "png",
                                     subdirectory: sub) else { return [] }
        var out: [Template] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "_").map(String.init)
            let cls = parts.count > 1 ? parts.dropLast().joined(separator: "_") : name
            guard let img = CardMatcher.loadGray(url, width: size.w, height: size.h) else { continue }
            let trimmed = CardMatcher.dropRows(img, CardMatcher.trimTopBandCount(img))
            out.append(Template(cls: cls, name: name, gray: trimmed,
                                letterH: CardMatcher.letterH(trimmed)))
        }
        return out
    }

    static func loadGray(_ url: URL, width: Int, height: Int) -> GrayImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return resizeCG(cg, width: width, height: height)
    }

    static func resizeCG(_ cg: CGImage, width: Int, height: Int) -> GrayImage {
        var p = [Float](repeating: 0, count: width * height)
        let cs = CGColorSpaceCreateDeviceGray()
        guard width > 0, height > 0,
              let ctx = CGContext(data: &p, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return GrayImage(w: width, h: height, p: p)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var flipped = p
        for y in 0..<height {
            flipped.replaceSubrange(
                y * width..<y * width + width,
                with: p[(height - 1 - y) * width..<(height - y) * width])
        }
        return GrayImage(w: width, h: height, p: flipped)
    }

    // MARK: - 灰度几何（PC 移植）

    private static func bandRange(_ w: Int) -> (a: Int, b: Int) {
        (Int(0.05 * Float(w)), Int(0.55 * Float(w)))
    }

    /// 牌点字母的行高：顶部首个连续暗行段。
    /// 阈值 150 与断口容忍 5：细笔画字干（5/J 竖笔）抗锯齿后灰度偏高；
    /// 另跳过顶部全宽暗行带（扇形裁剪带入的相邻牌深色边框）。
    static func letterH(_ g: GrayImage) -> Float {
        let (w, h, p) = (g.w, g.h, g.p)
        let (a, b) = bandRange(w)
        let win = b - a
        if win <= 0 || h == 0 { return 0 }
        var prof = [Int](repeating: 0, count: h)
        for y in 0..<h {
            var s = 0
            let row = y * w
            for x in a..<b where p[row + x] < 150 { s += 1 }
            prof[y] = s
        }
        var y = 0
        while y < h / 3 && prof[y] >= win - 2 { y += 1 }   // 顶部全宽暗边带
        var top: Int? = nil
        for v in y..<h where prof[v] >= 3 {
            top = v
            break
        }
        guard let topY = top else { return 0 }
        y = topY
        var low = 0
        while y < h {
            if prof[y] >= 2 {
                low = 0
            } else {
                low += 1
                if low >= 5 { break }
            }
            y += 1
        }
        return Float(y - low - topY)
    }

    /// 顶部全宽暗行带行数（仅裁 ≥win-2 列暗的连续带；字形顶横笔约六成宽不会误裁）
    static func trimTopBandCount(_ g: GrayImage) -> Int {
        let (w, h, p) = (g.w, g.h, g.p)
        let (a, b) = bandRange(w)
        let win = b - a
        if win <= 0 { return 0 }
        var k = 0
        while k < h / 3 {
            var dark = 0
            let row = k * w
            for x in a..<b where p[row + x] < 150 { dark += 1 }
            if dark >= win - 2 { k += 1 } else { break }
        }
        return (k > 0 && k < h) ? k : 0
    }

    static func dropRows(_ g: GrayImage, _ k: Int) -> GrayImage {
        guard k > 0, k < g.h else { return g }
        return GrayImage(w: g.w, h: g.h - k, p: Array(g.p[k * g.w...]))
    }

    /// 列投影聚簇（PC find_glyph_clusters）：merge_gap 内合并；超宽簇按 split_at 等分
    static func glyphClusters(bandDark: [Int], mergeGap: Int = 8,
                              maxW: Int = 60, splitAt: Int = 38) -> [(Int, Int)] {
        var clusters: [(Int, Int)] = []
        var start: Int? = nil
        var gap = 0
        for (x, v) in bandDark.enumerated() {
            if v > 2 {
                if start == nil { start = x }
                gap = 0
            } else if let s = start {
                gap += 1
                if gap >= mergeGap {
                    clusters.append((s, x - gap))
                    start = nil
                }
            }
        }
        if let s = start { clusters.append((s, bandDark.count - 1)) }
        var out: [(Int, Int)] = []
        for (a0, b0) in clusters {
            let width = b0 - a0
            if width < 10 { continue }
            if width > maxW {
                let k = max(2, Int((Float(width) / Float(splitAt)).rounded()))
                let step = Float(width) / Float(k)
                for j in 0..<k {
                    out.append((Int(Float(a0) + step * Float(j)),
                                Int(Float(a0) + step * Float(j + 1))))
                }
            } else {
                out.append((a0, b0))
            }
        }
        return out
    }

    // MARK: - NCC（朴素滑窗；阶段 3 视性能换积分图/FFT）

    /// 归一化互相关最大值：input 已含 replicate 边界填充。
    /// 积分图求窗口均值/方差（O(1)/窗），交叉项 vDSP 逐行点积。
    static func nccMax(input: GrayImage, templ: GrayImage) -> Float {
        let (iw, ih, ip) = (input.w, input.h, input.p)
        let (tw, th, tp) = (templ.w, templ.h, templ.p)
        if tw <= 0 || th <= 0 || iw < tw || ih < th { return -1 }
        let n = Float(tw * th)
        var tMean: Float = 0
        vDSP_meanv(tp, 1, &tMean, vDSP_Length(tp.count))
        var centered = tp
        var neg = -tMean
        vDSP_vsadd(tp, 1, &neg, &centered, 1, vDSP_Length(tp.count))
        var tSq: Float = 0
        vDSP_svesq(centered, 1, &tSq, vDSP_Length(tp.count))
        let tStd = (tSq / n).squareRoot()
        if tStd < 1e-6 { return -1 }

        let W = iw + 1
        var s = [Float](repeating: 0, count: (ih + 1) * W)
        var s2 = [Float](repeating: 0, count: (ih + 1) * W)
        for y in 0..<ih {
            var rowS: Float = 0, rowS2: Float = 0
            for x in 0..<iw {
                let v = ip[y * iw + x]
                rowS += v
                rowS2 += v * v
                s[(y + 1) * W + x + 1] = s[y * W + x + 1] + rowS
                s2[(y + 1) * W + x + 1] = s2[y * W + x + 1] + rowS2
            }
        }
        func wsum(_ t: [Float], _ y0: Int, _ x0: Int) -> Float {
            let y1 = y0 + th, x1 = x0 + tw
            return t[y1 * W + x1] - t[y0 * W + x1] - t[y1 * W + x0] + t[y0 * W + x0]
        }
        var best: Float = -1
        var dot: Float = 0
        ip.withUnsafeBufferPointer { ib in
            tp.withUnsafeBufferPointer { tb in
                guard let iptr = ib.baseAddress, let tptr = tb.baseAddress else { return }
                for oy in 0...(ih - th) {
                    for ox in 0...(iw - tw) {
                        let wMean = wsum(s, oy, ox) / n
                        let wVar = wsum(s2, oy, ox) / n - wMean * wMean
                        let wStd = max(0, wVar).squareRoot()
                        if wStd < 1e-6 { continue }
                        var cross: Float = 0
                        for r in 0..<th {
                            vDSP_dotpr(iptr + (oy + r) * iw + ox, 1, tptr + r * tw, 1,
                                       &dot, vDSP_Length(tw))
                            cross += dot
                        }
                        let ncc = (cross / n - wMean * tMean) / (wStd * tStd)
                        if ncc > best { best = ncc }
                    }
                }
            }
        }
        return best
    }

    /// replicate 填充
    static func padReplicate(_ g: GrayImage, pad: Int) -> GrayImage {
        let (w, h, p) = (g.w, g.h, g.p)
        let nw = w + 2 * pad, nh = h + 2 * pad
        var out = [Float](repeating: 0, count: nw * nh)
        for y in 0..<nh {
            let sy = min(max(y - pad, 0), h - 1)
            let srow = sy * w, drow = y * nw
            for x in 0..<nw {
                let sx = min(max(x - pad, 0), w - 1)
                out[drow + x] = p[srow + sx]
            }
        }
        return GrayImage(w: nw, h: nh, p: out)
    }

    /// 双线性缩放（任一平面共用）
    static func resize(_ g: GrayImage, width: Int, height: Int) -> GrayImage {
        if g.w == width && g.h == height { return g }
        guard width > 0, height > 0, g.w > 0, g.h > 0 else {
            return GrayImage(w: width, h: height, p: [Float](repeating: 0, count: width * height))
        }
        var out = [Float](repeating: 0, count: width * height)
        let rx = Float(g.w) / Float(width)
        let ry = Float(g.h) / Float(height)
        for y in 0..<height {
            let fy = min(max((Float(y) + 0.5) * ry - 0.5, 0), Float(g.h - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, g.h - 1)
            let dy = fy - Float(y0)
            for x in 0..<width {
                let fx = min(max((Float(x) + 0.5) * rx - 0.5, 0), Float(g.w - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, g.w - 1)
                let dx = fx - Float(x0)
                let v00 = g.p[y0 * g.w + x0], v01 = g.p[y0 * g.w + x1]
                let v10 = g.p[y1 * g.w + x0], v11 = g.p[y1 * g.w + x1]
                out[y * width + x] = v00 * (1 - dx) * (1 - dy) + v01 * dx * (1 - dy)
                    + v10 * (1 - dx) * dy + v11 * dx * dy
            }
        }
        return GrayImage(w: width, h: height, p: out)
    }

    // MARK: - 分类（PC classify 移植）

    /// 裁剪 → 尺度归一 + 平移搜索匹配；分层：字母区定牌点，花色区定花色。
    /// minLH：牌点字母最小行高，低于此判碎片不入账（手牌 8；中央禁用 0 防误杀红J）
    func classify(crop: CropPixels, size: (Int, Int), minLH: Float = 8) -> ClassifyResult {
        var g = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.gray),
                                   width: size.w, height: size.h)
        var rp = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.r),
                                    width: size.w, height: size.h)
        var gp = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.g),
                                    width: size.w, height: size.h)
        var bp = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.b),
                                    width: size.w, height: size.h)
        let k = CardMatcher.trimTopBandCount(g)
        g = CardMatcher.dropRows(g, k)
        rp = CardMatcher.dropRows(rp, k)
        gp = CardMatcher.dropRows(gp, k)
        bp = CardMatcher.dropRows(bp, k)
        let lh = CardMatcher.letterH(g)
        if lh <= minLH { return ClassifyResult(cls: "?", score: -1, star: false) }

        let (W, H) = (g.w, g.h)
        let zy0 = Int(0.05 * Float(H)), zy1 = Int(0.85 * Float(H))
        let zx0 = Int(0.05 * Float(W)), zx1 = Int(0.62 * Float(W))
        // 颜色先验：橙色（伙章/星标）排除出先验，避免徽章把黑牌误判红
        var dark = 0, red = 0
        for y in zy0..<zy1 {
            for x in zx0..<zx1 {
                let i = y * W + x
                let rr = rp.p[i], gg = gp.p[i], bb = bp.p[i]
                let orange = rr > 180 && gg > 80 && gg < 190 && bb < 110
                if orange { continue }
                if g.p[i] < 160 { dark += 1 }
                if rr - bb > 70 && rr > 110 { red += 1 }
            }
        }
        var isRed = false, isBlack = false
        if dark >= 40 {
            let ratio = Float(red) / Float(max(1, dark))
            isRed = ratio > 0.40
            isBlack = ratio < 0.15
        }
        // 星标：pip 区（y 0.42-0.78）橙色占比 > 0.02（徽章在 y~0.85 下方不触发）
        var orangeP = 0
        let py0 = max(Int(0.42 * Float(H)), zy0), py1 = min(Int(0.78 * Float(H)), zy1)
        for y in py0..<py1 {
            for x in zx0..<zx1 {
                let i = y * W + x
                if rp.p[i] > 180, gp.p[i] > 80, gp.p[i] < 190, bp.p[i] < 110 {
                    orangeP += 1
                }
            }
        }
        let star = Float(orangeP) / Float(W * H) > 0.02

        let inp = CardMatcher.padReplicate(g, pad: CardMatcher.pad)
        var perCls: [String: (l: Float, s: Float)] = [:]
        for tpl in handTemplates + centerTemplates {
            for r in CardMatcher.scaleLadder {
                let t = abs(r - 1.0) < 0.02
                    ? tpl.gray
                    : CardMatcher.resize(tpl.gray,
                                         width: Int(Float(tpl.gray.w) * r),
                                         height: Int(Float(tpl.gray.h) * r))
                // 字母区定牌点、花色区定花色（同牌点类字母区同分，花色形状决胜）
                let tl = sub(t, x0: Int(0.04 * Float(t.w)), y0: Int(0.04 * Float(t.h)),
                             x1: Int(0.70 * Float(t.w)), y1: Int(0.50 * Float(t.h)))
                let ts = sub(t, x0: Int(0.04 * Float(t.w)), y0: Int(0.42 * Float(t.h)),
                             x1: Int(0.60 * Float(t.w)), y1: Int(0.88 * Float(t.h)))
                if tl.w >= inp.w || tl.h >= inp.h || ts.w >= inp.w || ts.h >= inp.h { continue }
                let sL = CardMatcher.nccMax(input: inp, templ: tl)
                let sS = CardMatcher.nccMax(input: inp, templ: ts)
                var d = perCls[tpl.cls] ?? (l: -1, s: -1)
                if sL > d.l { d.l = sL; d.s = sS }
                perCls[tpl.cls] = d
            }
        }
        if perCls.isEmpty { return ClassifyResult(cls: "?", score: -1, star: star) }

        // 第一层：牌点（字母区分最高者，容同牌点各类 ±0.06）
        let bestL = perCls.values.map(\.l).max() ?? -1
        let pool = perCls.filter { $0.value.l >= bestL - 0.06 }
        // 第二层：花色（含红/黑先验罚分 -0.50）
        var bestCls = "?"
        var bestScore = -Double.infinity
        for (cls, v) in pool {
            var ss = v.s
            if cls.count == 2 {
                let suit = String(cls.suffix(1))
                if isRed && (suit == "S" || suit == "C") { ss -= 0.50 }
                if isBlack && (suit == "H" || suit == "D") { ss -= 0.50 }
            }
            let total = 0.5 * Double(v.l) + 0.5 * Double(ss)
            if total > bestScore {
                bestScore = total
                bestCls = cls
            }
        }
        return ClassifyResult(cls: bestCls, score: bestScore, star: star)
    }

    private func sub(_ g: GrayImage, x0: Int, y0: Int, x1: Int, y1: Int) -> GrayImage {
        let w = max(0, x1 - x0), h = max(0, y1 - y0)
        guard w > 0, h > 0, x1 <= g.w, y1 <= g.h else {
            return GrayImage(w: max(1, w), h: max(1, h),
                             p: [Float](repeating: 255, count: max(1, w * h)))
        }
        var p = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let src = (y0 + y) * g.w + x0
            p.replaceSubrange(y * w..<y * w + w, with: g.p[src..<src + w])
        }
        return GrayImage(w: w, h: h, p: p)
    }
}
