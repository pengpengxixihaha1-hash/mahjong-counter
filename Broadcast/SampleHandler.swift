import ReplayKit
import UIKit

// MARK: - 广播扩展入口：收屏 → 识别 → 写共享状态

class SampleHandler: RPSampleBufferHandler {

    override func process(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        Engine.shared.handle(sampleBuffer)
    }

    override func finishBroadcastWithError(_ error: Error) {
        // 用户手动停止广播属正常结束
        finishBroadcastSuccessfully()
    }
}

// MARK: - 识别引擎

final class Engine {
    static let shared = Engine()

    private let queue = DispatchQueue(label: "engine.process", qos: .utility)
    private var lastProcessAt = Date.distantPast

    // 状态机
    private var handBaseline: [String: Int] = [:]          // 我的手牌基准
    private var zoneBaseline: [String: [String: Int]] = [:]// 出牌区基准
    private var zoneShrink: [String: Int] = [:]            // 变少连续帧计数
    private var handStreak: [String: Int] = [:]            // 手牌候选连续帧

    func handle(_ sb: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessAt) >= 0.45 else { return }
        lastProcessAt = now
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        queue.async { self.process(pb) }
    }

    // MARK: 帧处理

    private func process(_ pb: CVPixelBuffer) {
        let deck = DeckConfig.load()
        var state = GameState.load()

        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!

        // 降采样灰度（目标宽 540）
        let tw = min(540, w)
        let sx = Float(w) / Float(tw)
        let th = max(1, Int(Float(h) / sx))
        var gray = [UInt8](repeating: 0, count: tw * th)
        for y in 0..<th {
            let sy = min(h - 1, Int(Float(y) * sx))
            let row = base.advanced(by: sy * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<tw {
                let sxx = min(w - 1, Int(Float(x) * sx))
                let o = sxx * 4 // BGRA
                let g = (Int(row[o]) * 299 + Int(row[o + 1]) * 587 + Int(row[o + 2]) * 114) / 1000
                gray[y * tw + x] = UInt8(g)
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        // 白色牌块检测
        let cards = findCards(gray, w: tw, h: th)
        state.frames += 1

        // 角标识别 + 分区
        var byZone: [String: [String: Int]] = [:]
        var debugCards = 0
        for c in cards {
            guard let rank = matchCorner(gray, w: tw, h: th, rect: c) else { continue }
            debugCards += 1
            let zone = zoneOf(cx: c.x + c.w / 2, cy: c.y + c.h / 2, w: tw, h: th)
            byZone[zone, default: [:]][rank.rawValue, default: 0] += 1
        }

        // —— 开局：手牌自动采纳（连续 2 帧一致，且总数足够大）——
        let hand = byZone["手"] ?? [:]
        let handTotal = hand.values.reduce(0, +)
        if !state.started {
            if handTotal >= 18 {
                handStreak[hashOf(hand), default: 0] += 1
                if handStreak[hashOf(hand)]! >= 2 {
                    // 采纳手牌：剩余 = 配置 - 手牌
                    var rem = deck.counts
                    for (r, n) in hand { rem[r] = max(0, (rem[r] ?? 0) - n) }
                    state.remaining = rem
                    state.started = true
                    state.handText = textOf(hand)
                    handBaseline = hand
                    zoneBaseline = [:]
                    zoneShrink = [:]
                    state.playLog.append("— 开局 · 手牌\(handTotal)张 —")
                }
            } else {
                handStreak.removeAll()
            }
        } else {
            // 手牌基准微校正：数量显著变化（摸牌）时更新文本
            if handTotal > 0 && hashOf(hand) != hashOf(handBaseline) && abs(handTotal - handBaseline.values.reduce(0,+)) >= 3 {
                state.handText = textOf(hand)
                handBaseline = hand
            }
        }

        // —— 出牌区对比扣牌 ——
        for zone in ["对", "上", "我", "下"] {
            let cur = byZone[zone] ?? [:]
            let base = zoneBaseline[zone] ?? [:]
            let curTotal = cur.values.reduce(0, +)
            let baseTotal = base.values.reduce(0, +)

            if curTotal > baseTotal {
                // 区域牌变多 → 出牌，立即扣
                var diff: [String: Int] = [:]
                for (r, n) in cur {
                    let d = n - (base[r] ?? 0)
                    if d > 0 { diff[r] = d }
                }
                for (r, n) in diff {
                    state.remaining[r, default: 0] = max(0, (state.remaining[r] ?? 0) - n)
                }
                let txt = textOf(diff)
                state.lastPlays[zone] = txt
                state.playLog.append("\(zone)出 \(txt)")
                if state.playLog.count > 80 { state.playLog.removeFirst(state.playLog.count - 80) }
                zoneBaseline[zone] = cur
                zoneShrink[zone] = 0
            } else if curTotal < baseTotal {
                // 变少 → 连续 2 帧一致才重置基准（防动画/光效误判）
                zoneShrink[zone, default: 0] += 1
                if zoneShrink[zone]! >= 2 {
                    zoneBaseline[zone] = cur
                    zoneShrink[zone] = 0
                }
            } else {
                zoneShrink[zone] = 0
            }
        }

        // 诊断
        let dTxt = byZone["对"]?.values.reduce(0,+) ?? 0
        let uTxt = byZone["上"]?.values.reduce(0,+) ?? 0
        let mTxt = byZone["我"]?.values.reduce(0,+) ?? 0
        let xTxt = byZone["下"]?.values.reduce(0,+) ?? 0
        state.diag = "块\(cards.count) 牌\(debugCards) | 对\(dTxt) 上\(uTxt) 我\(mTxt) 下\(xTxt) 手\(handTotal)"

        state.save()
    }

    // MARK: 分区（比例可依诊断迭代）

    private func zoneOf(cx: Int, cy: Int, w: Int, h: Int) -> String {
        let fx = Float(cx) / Float(w), fy = Float(cy) / Float(h)
        if fy > 0.80 { return "手" }
        if fx < 0.25 { return "下" }       // 左家 = 下
        if fx > 0.75 { return "对" }       // 右家 = 对
        if fy > 0.52 { return "我" }       // 手牌上方中央 = 我出的牌
        return "上"                         // 中上部 = 上家
    }

    // MARK: 白色牌块连通域

    private struct Rect { var x: Int, y: Int, w: Int, h: Int }

    private func findCards(_ gray: [UInt8], w: Int, h: Int) -> [Rect] {
        let tw = w, th = h
        var visited = [Bool](repeating: false, count: tw * th)
        var result: [Rect] = []
        var stack: [Int] = []
        let threshold: UInt8 = 205

        for start in 0..<(tw * th) {
            if visited[start] || gray[start] < threshold { continue }
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            var minX = tw, maxX = 0, minY = th, maxY = 0, cnt = 0
            while let p = stack.popLast() {
                let px = p % tw, py = p / tw
                cnt += 1
                if px < minX { minX = px }; if px > maxX { maxX = px }
                if py < minY { minY = py }; if py > maxY { maxY = py }
                // 4 邻域
                if px > 0 { let q = p - 1; if !visited[q] && gray[q] >= threshold { visited[q] = true; stack.append(q) } }
                if px < tw - 1 { let q = p + 1; if !visited[q] && gray[q] >= threshold { visited[q] = true; stack.append(q) } }
                if py > 0 { let q = p - tw; if !visited[q] && gray[q] >= threshold { visited[q] = true; stack.append(q) } }
                if py < th - 1 { let q = p + tw; if !visited[q] && gray[q] >= threshold { visited[q] = true; stack.append(q) } }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            let fill = Float(cnt) / Float(bw * bh)
            // 牌块形状过滤：宽高比与填充率（叠放多张时宽会更大，放宽）
            let ratio = Float(bh) / Float(bw)
            if bw >= 12, bh >= 20, cnt > 120, fill > 0.55, ratio > 0.9, ratio < 2.6 {
                result.append(Rect(x: minX, y: minY, w: bw, h: bh))
                if result.count > 60 { break }
            }
        }
        return result
    }

    // MARK: 角标匹配（块内左上区域 → 12x18 网格 → 字形模板打分）

    private func matchCorner(_ gray: [UInt8], w: Int, h: Int, rect: Rect) -> CardRank? {
        // 角标区域：块左上 55% 宽 × 32% 高
        let cw = max(6, rect.w * 55 / 100)
        let ch = max(8, rect.h * 32 / 100)
        let ox = rect.x + rect.w * 8 / 100
        let oy = rect.y + rect.h * 6 / 100
        if ox + cw >= w || oy + ch >= h { return nil }

        // 黑字迹网格
        let GW = 12, GH = 18
        var grid = [Float](repeating: 0, count: GW * GH)
        var dark = 0
        for gy in 0..<GH {
            for gx in 0..<GW {
                let px = ox + gx * cw / GW
                let py = oy + gy * ch / GH
                let v = Int(gray[py * w + px])
                if v < 165 { grid[gy * GW + gx] = 1; dark += 1 }
            }
        }
        let darkRatio = Float(dark) / Float(GW * GH)
        if darkRatio < 0.04 || darkRatio > 0.65 { return nil } // 没有字迹 / 全黑不是角标

        // 与模板求重合率（IOU 近似）
        var best: (CardRank, Float)?
        for (rank, tpl) in Glyphs.templates {
            var inter: Float = 0
            var union = 0
            for i in 0..<grid.count {
                let a = grid[i], b = tpl[i]
                if a > 0 && b > 0 { inter += 1 }
                if a > 0 || b > 0 { union += 1 }
            }
            let iou = union > 0 ? inter / Float(union) : 0
            if best == nil || iou > best!.1 { best = (rank, iou) }
        }
        guard let hit = best, hit.1 > 0.30 else { return nil }
        return hit.0
    }

    // MARK: 工具

    private func countMap(_ list: [CardRank]) -> [String: Int] {
        var m: [String: Int] = [:]
        for r in list { m[r.rawValue, default: 0] += 1 }
        return m
    }

    private func hashOf(_ m: [String: Int]) -> String {
        m.sorted { $0.key < $1.key }.map { "\($0.key)\($0.value)" }.joined(separator: ",")
    }

    private func textOf(_ m: [String: Int]) -> String {
        CardRank.displayOrder.compactMap { r -> String? in
            guard let n = m[r.rawValue], n > 0 else { return nil }
            return n > 1 ? "\(r.rawValue)\(n)" : r.rawValue
        }.joined(separator: " ")
    }
}

// MARK: - 字形模板（系统字体渲染，扩展进程内生成一次）

enum Glyphs {
    static let templates: [CardRank: [Float]] = {
        let GW = 12, GH = 18
        var out: [CardRank: [Float]] = [:]
        let labels: [CardRank: String] = [
            .joker: "王", .two: "2", .ace: "A", .king: "K", .queen: "Q", .jack: "J",
            .ten: "10", .nine: "9", .eight: "8", .seven: "7", .six: "6",
            .five: "5", .four: "4", .three: "3",
        ]
        for (rank, label) in labels {
            let size = CGSize(width: 96, height: 128)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 88, weight: .bold),
                    .foregroundColor: UIColor.black,
                ]
                let s = NSAttributedString(string: label, attributes: attrs)
                let b = s.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
                s.draw(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
            }
            guard let cg = img.cgImage else { continue }
            // 采样到 12x18 网格
            var tpl = [Float](repeating: 0, count: GW * GH)
            let cw = cg.width / GW, chh = cg.height / GH
            var any = false
            for gy in 0..<GH {
                for gx in 0..<GW {
                    guard let data = cg.dataProvider?.data,
                          let ptr = CFDataGetBytePtr(data) else { continue }
                    let bpp = cg.bitsPerPixel / 8
                    let sx = min(cg.width - 1, gx * cw + cw / 2)
                    let sy = min(cg.height - 1, gy * chh + chh / 2)
                    let o = sy * cg.bytesPerRow + sx * bpp
                    let r = Int(ptr[o]), g = Int(ptr[o + 1]), bl = Int(ptr[o + 2])
                    let gray = (r * 299 + g * 587 + bl * 114) / 1000
                    if gray < 150 { tpl[gy * GW + gx] = 1; any = true }
                }
            }
            if any { out[rank] = tpl }
        }
        return out
    }()
}
