import Accelerate
import CoreGraphics
import Foundation
import ImageIO

// 牌面模板匹配引擎 —— 手机版（牌点-only，不分花色）。
// 参数与 recognize_phone.py --device 回归验证版逐项对齐（17 样本 16 帧逐字节一致）：
//   · 手牌：平均模板（每点 1 张）+ 单尺度 1.0 + pad10 + accept 0.60 + minLH 30
//   · 中央：两级匹配 —— 平均模板全阶梯选 top-3 候选牌点（各记最优尺度），
//     再用候选牌点的全量模板在其 ±1 尺度邻域精配 + accept 0.55 + minLH 12
// NCC：积分图求窗口均值/方差，交叉项 vDSP_imgfir 一次算出整张相关图（真机性能关键）。
struct GrayImage {
    var w: Int
    var h: Int
    var p: [Float]   // 行主序 0-255
}

/// 裁剪像素：灰度（全幅 0-255）。牌点-only 不需要颜色平面，
/// 红色字形旗标只在整幅列投影（glyph 掩码）时用。
struct CropPixels {
    var w: Int
    var h: Int
    var gray: [Float]
}

final class CardMatcher {
    struct Template {
        let cls: String
        let name: String
        let gray: GrayImage
    }

    struct ClassifyResult {
        let cls: String
        let score: Double
    }

    /// 归一化尺寸：与 recognize_phone.py 一致（手牌 56x150 / 中央 44x96）
    static let handSize = (w: 56, h: 150)
    static let centerSize = (w: 44, h: 96)
    /// 固定尺度阶梯：中央牌面渲染尺度随张数/遮挡变化
    static let ladder: [Float] = [0.5, 0.6, 0.75, 0.9, 1.0, 1.15, 1.3]
    static let pad = 10

    private(set) var handTemplates: [Template] = []       // H_ 前缀：手牌平均模板
    private(set) var centerTemplates: [Template] = []     // C_ 前缀：中央全量模板
    private(set) var centerAvgTemplates: [Template] = []  // A_ 前缀：中央平均模板（短名单）

    // MARK: - 模板加载（bundle 根目录 H_*/C_*/A_*.png；兼容 Templates/ 子目录）

    func loadTemplates(bundle: Bundle = .main) {
        handTemplates = load(prefix: "H_", size: Self.handSize, bundle: bundle)
        centerTemplates = load(prefix: "C_", size: Self.centerSize, bundle: bundle)
        centerAvgTemplates = load(prefix: "A_", size: Self.centerSize, bundle: bundle)
    }

    private func load(prefix: String, size: (w: Int, h: Int), bundle: Bundle) -> [Template] {
        var urls = bundle.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
        if urls.isEmpty {
            urls = bundle.urls(forResourcesWithExtension: "png", subdirectory: "Templates") ?? []
        }
        var out: [Template] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { continue }
            let rest = name.dropFirst(prefix.count)
            let cls: String
            if let us = rest.lastIndex(of: "_") {
                cls = String(rest[..<us])
            } else {
                cls = String(rest)
            }
            guard !cls.isEmpty, let img = CardMatcher.loadGray(url, width: size.w, height: size.h) else { continue }
            out.append(Template(cls: cls, name: name, gray: img))
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

    // MARK: - 几何

    /// 牌点字形行高：从顶部起数首个连续暗行段（阈值 3 列暗 / 全零行断），
    /// 与 recognize_phone.py classify() 的 lh 逐行一致。
    static func letterH(_ g: GrayImage) -> Float {
        let (w, h, p) = (g.w, g.h, g.p)
        let x0 = Int(0.1 * Float(w)), x1 = Int(0.7 * Float(w))
        guard x1 > x0, h > 0 else { return 0 }
        var lh = 0
        for y in 0..<h {
            var dark = 0
            let row = y * w
            for x in x0..<x1 where p[row + x] < 150 { dark += 1 }
            if dark >= 3 {
                lh += 1
            } else if lh > 0 && dark == 0 {
                break
            }
        }
        return Float(lh)
    }

    /// 列投影聚簇：merge_gap 内合并；超宽簇按 split_at 等分（簇宽 > split_w 才分）
    static func glyphClusters(bandDark: [Int], mergeGap: Int, minW: Int,
                              splitW: Int = 0, splitAt: Int = 0) -> [(Int, Int)] {
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
                    if x - gap - s >= minW { clusters.append((s, x - gap)) }
                    start = nil
                }
            }
        }
        if let s = start, bandDark.count - 1 - s >= minW {
            clusters.append((s, bandDark.count - 1))
        }
        guard splitW > 0 else { return clusters }
        var out: [(Int, Int)] = []
        for (a0, b0) in clusters {
            let width = b0 - a0
            if width > splitW {
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

    // MARK: - NCC（积分图 + vDSP_imgfir 交叉项）

    /// 每个 crop 建一次（含 replicate 填充 + 积分图），逐模板复用。
    struct NCCContext {
        let inp: GrayImage
        private var s: [Float]
        private var s2: [Float]
        private let W: Int

        init(gray: GrayImage, pad: Int) {
            let (w, h, p) = (gray.w, gray.h, gray.p)
            let nw = w + 2 * pad, nh = h + 2 * pad
            var buf = [Float](repeating: 0, count: nw * nh)
            for y in 0..<nh {
                let sy = min(max(y - pad, 0), h - 1)
                let srow = sy * w, drow = y * nw
                for x in 0..<nw {
                    let sx = min(max(x - pad, 0), w - 1)
                    buf[drow + x] = p[srow + sx]
                }
            }
            inp = GrayImage(w: nw, h: nh, p: buf)
            W = nw + 1
            s = [Float](repeating: 0, count: (nh + 1) * W)
            s2 = s
            for y in 0..<nh {
                var rowS: Float = 0, rowS2: Float = 0
                let row = y * nw
                for x in 0..<nw {
                    let v = inp.p[row + x]
                    rowS += v
                    rowS2 += v * v
                    s[(y + 1) * W + x + 1] = s[y * W + x + 1] + rowS
                    s2[(y + 1) * W + x + 1] = s2[y * W + x + 1] + rowS2
                }
            }
        }

        func wsum(_ t: [Float], _ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> Float {
            t[y1 * W + x1] - t[y0 * W + x1] - t[y1 * W + x0] + t[y0 * W + x0]
        }

        /// 模板在填充输入上的最大归一化互相关
        func nccMax(_ templ: GrayImage) -> Float {
            let (tw, th) = (templ.w, templ.h)
            let (iw, ih) = (inp.w, inp.h)
            if tw <= 0 || th <= 0 || iw < tw || ih < th { return -1 }
            let n = Float(tw * th)
            var tMean: Float = 0
            vDSP_meanv(templ.p, 1, &tMean, vDSP_Length(templ.p.count))
            var centered = templ.p
            var neg = -tMean
            vDSP_vsadd(templ.p, 1, &neg, &centered, 1, vDSP_Length(templ.p.count))
            var tSq: Float = 0
            vDSP_svesq(centered, 1, &tSq, vDSP_Length(templ.p.count))
            let tStd = (tSq / n).squareRoot()
            if tStd < 1e-6 { return -1 }

            let OW = iw - tw + 1, OH = ih - th + 1
            var cross = [Float](repeating: 0, count: OW * OH)
            // vDSP_imgfir 参数语义：M=行数、N=列数（A/F 均行主序），
            // 输出 C 为 (M-P+1) 行 × (N-Q+1) 列 → cross[oy * OW + ox]
            vDSP_imgfir(inp.p, vDSP_Length(ih), vDSP_Length(iw), templ.p,
                        vDSP_Length(th), vDSP_Length(tw), &cross)
            var best: Float = -1
            for oy in 0..<OH {
                for ox in 0..<OW {
                    let wMean = wsum(s, oy, ox, oy + th, ox + tw) / n
                    let wVar = wsum(s2, oy, ox, oy + th, ox + tw) / n - wMean * wMean
                    let wStd = max(0, wVar).squareRoot()
                    if wStd < 1e-6 { continue }
                    let ncc = (cross[oy * OW + ox] / n - wMean * tMean) / (wStd * tStd)
                    if ncc > best { best = ncc }
                }
            }
            return best
        }
    }

    /// 双线性缩放
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

    /// 模板按尺度缩放（1.0 直接返回）
    private static func scaled(_ t: GrayImage, _ sc: Float) -> GrayImage {
        if abs(sc - 1.0) < 0.02 { return t }
        return resize(t, width: Int(Float(t.w) * sc), height: Int(Float(t.h) * sc))
    }

    // MARK: - 分类

    /// 通用分类（归一化 + 补边平移搜索 NCC，牌点-only 取全类最高分）。
    /// 手牌用：ladder [1.0]，accept 0.60，minLH 30（150 高空间）。
    func classifyHand(_ crop: CropPixels, accept: Double, minLH: Float) -> ClassifyResult {
        classify(crop, size: Self.handSize, accept: accept, minLH: minLH,
                 ladder: [1.0], tpls: handTemplates)
    }

    /// 中央两级匹配（与 recognize_phone.py classify_two_stage 一致）：
    /// 阶段1 平均模板全阶梯 → top-3 候选牌点（各记最优尺度）；
    /// 阶段2 候选牌点的全量模板在其 ±1 尺度邻域精配。accept 0.55，minLH 12。
    func classifyCenter(_ crop: CropPixels, accept: Double, minLH: Float) -> ClassifyResult {
        let g = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.gray),
                                   width: Self.centerSize.w, height: Self.centerSize.h)
        let lh = CardMatcher.letterH(g)
        if lh < minLH { return ClassifyResult(cls: "?", score: -1) }
        let ctx = NCCContext(gray: g, pad: Self.pad)

        var perRank: [String: (score: Float, scale: Float)] = [:]
        for tpl in centerAvgTemplates {
            var b: Float = -1, bsc: Float = 1.0
            for sc in Self.ladder {
                let s = ctx.nccMax(CardMatcher.scaled(tpl.gray, sc))
                if s > b { b = s; bsc = sc }
            }
            if b > (perRank[tpl.cls]?.score ?? -2) {
                perRank[tpl.cls] = (b, bsc)
            }
        }
        let top3 = perRank.sorted { $0.value.score > $1.value.score }.prefix(3).map(\.key)
        var bestCls = "?", bestS: Float = -1
        for rank in top3 {
            guard let hit = perRank[rank],
                  let i0 = Self.ladder.firstIndex(of: hit.scale) else { continue }
            let sub = Self.ladder[max(0, i0 - 1):min(Self.ladder.count, i0 + 2)]
            for tpl in centerTemplates where tpl.cls == rank {
                for sc in sub {
                    let s = ctx.nccMax(CardMatcher.scaled(tpl.gray, sc))
                    if s > bestS { bestS = s; bestCls = tpl.cls }
                }
            }
        }
        if bestS < Float(accept) {
            return ClassifyResult(cls: "?", score: Double(bestS))
        }
        return ClassifyResult(cls: bestCls, score: Double(bestS))
    }

    private func classify(_ crop: CropPixels, size: (w: Int, h: Int), accept: Double,
                          minLH: Float, ladder: [Float], tpls: [Template]) -> ClassifyResult {
        let g = CardMatcher.resize(GrayImage(w: crop.w, h: crop.h, p: crop.gray),
                                   width: size.w, height: size.h)
        let lh = CardMatcher.letterH(g)
        if lh < minLH { return ClassifyResult(cls: "?", score: -1) }
        let ctx = NCCContext(gray: g, pad: Self.pad)
        var bestCls = "?", bestS: Float = -1
        for tpl in tpls {
            for sc in ladder {
                let t = CardMatcher.scaled(tpl.gray, sc)
                if t.w >= ctx.inp.w || t.h >= ctx.inp.h { continue }
                let s = ctx.nccMax(t)
                if s > bestS {
                    bestS = s
                    bestCls = tpl.cls
                }
            }
        }
        if bestS < Float(accept) {
            return ClassifyResult(cls: "?", score: Double(bestS))
        }
        return ClassifyResult(cls: bestCls, score: Double(bestS))
    }
}
