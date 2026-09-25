import Foundation
import CoreVideo
import UserNotifications

/// 屏幕识别引擎（运行在广播扩展内）：
/// 帧 → 灰度降采样 → 白色牌块 → 块内角标匹配 → 按位置分区
/// → 状态机（手牌采纳 / 区域对比扣牌）→ 每手发本地通知（横幅 + 数据回传主App）。
final class RecognitionEngine {

    static let shared = RecognitionEngine()

    private let queue = DispatchQueue(label: "jp.engine", qos: .utility)

    // ---- 参数 ----
    private let targetW = 480
    private let frameInterval: CFTimeInterval = 0.45
    private let matchScore: Float = 0.62
    private let topSkip = 0.06          // 顶部 HUD 忽略区
    private let handY = 0.72            // 底部手牌分界
    private let upperY = 0.38           // 上家分界
    private let leftX = 0.40            // 下家 / 右侧分界
    private let rightX = 0.60

    // ---- 状态 ----
    private var deck = DeckPreset.default
    private var remaining = [Int](repeating: 0, count: 14)
    private var hand = [Int](repeating: 0, count: 14)
    private var handTotal = 0
    private var playSeq = 0
    private var gameNo = 1
    private var log: [PlayEntry] = []
    private var lastBySeat: [String: String] = [:]
    private var confirmed: [String: [Int]] = [:]   // 各座位已确认基准
    private var lessStreak: [String: Int] = [:]    // 变少连续帧计数
    private var started = false
    private var handAnnounced = false
    private var idleFrames = 0                     // 全空帧计数（自动判局结束）
    private var lastProcessAt: CFTimeInterval = 0

    private init() {}

    // MARK: - 生命周期

    /// 广播开始：重置为新一局（保留已下发的牌型配置）
    func start() {
        queue.async { [weak self] in self?.reset(gameIncrement: true, note: nil) }
    }

    /// 应用牌型配置（Darwin 通知下发），并重置
    func applyDeck(hex: String) {
        queue.async { [weak self] in
            guard let self, let p = DeckPreset.fromHex(hex) else { return }
            self.deck = p
            self.reset(gameIncrement: false, note: "牌型已同步：\(p.name)")
        }
    }

    /// 主App点开场 / 重置
    func resetGame() {
        queue.async { [weak self] in
            self?.reset(gameIncrement: true, note: "已开始新一局")
        }
    }

    private func reset(gameIncrement: Bool, note: String?) {
        if gameIncrement { gameNo += 1 }
        remaining = Array(repeating: 0, count: 14)
        for r in PokerRank.displayOrder { remaining[r.rawValue] = deck.count(r) }
        hand = [Int](repeating: 0, count: 14)
        handTotal = 0
        playSeq = 0
        log = []
        lastBySeat = [:]
        confirmed = [:]
        lessStreak = [:]
        handAnnounced = false
        idleFrames = 0
        started = true
        if let note { pushSnapshot(note: note) }
    }

    // MARK: - 帧入口

    func feed(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastProcessAt >= frameInterval else { return }
        lastProcessAt = now
        CVPixelBufferRetain(pixelBuffer)
        queue.async { [weak self] in
            defer { CVPixelBufferRelease(pixelBuffer) }
            self?.process(pixelBuffer: pixelBuffer)
        }
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        guard started, let frame = ImgProc.grayDownscale(pixelBuffer, targetW: targetW) else { return }
        let fw = frame.w, fh = frame.h

        // 1) 白色牌块
        let blobs = ImgProc.brightBlobs(frame, threshold: 190, minArea: 300)

        // 2) 块内角标字形匹配
        var hand = [Int](repeating: 0, count: 14)
        var zones: [String: [Int]] = ["对": [Int](repeating: 0, count: 14),
                                      "上": [Int](repeating: 0, count: 14),
                                      "我": [Int](repeating: 0, count: 14),
                                      "下": [Int](repeating: 0, count: 14)]
        let templates = GlyphTemplates.all()
        for b in blobs {
            // 只扫块内顶部条带（角标所在），高度为块的 40%（至少 16px）
            let bandH = max(16, b.h * 2 / 5)
            let marks = ImgProc.inkBlobs(frame, x0: b.x, y0: b.y, x1: b.x + b.w, y1: b.y + bandH)
            for m in marks {
                guard let glyph = ImgProc.normalizedGlyph(frame, blob: m, outW: GlyphTemplates.glyphW, outH: GlyphTemplates.glyphH) else { continue }
                var bestRank: PokerRank?
                var bestScore: Float = 0
                for t in templates {
                    let s = ImgProc.ncc(glyph, t.data)
                    if s > bestScore { bestScore = s; bestRank = t.rank }
                }
                guard let rank = bestRank, bestScore >= matchScore else { continue }
                let cx = Float(m.x + m.w / 2) / Float(fw)
                let cy = Float(m.y + m.h / 2) / Float(fh)
                if cy >= handY {
                    hand[rank.rawValue] += 1
                } else if cy < topSkip {
                    continue // 顶部 HUD
                } else if cx < leftX {
                    zones["下"]![rank.rawValue] += 1
                } else if cx >= rightX {
                    zones["对"]![rank.rawValue] += 1
                } else if cy < upperY {
                    zones["上"]![rank.rawValue] += 1
                } else {
                    zones["我"]![rank.rawValue] += 1
                }
            }
        }

        onFrame(hand: hand, zones: zones)
    }

    // MARK: - 状态机（与安卓版同逻辑）

    private func onFrame(hand newHand: [Int], zones: [String: [Int]]) {
        let newHandTotal = newHand.reduce(0, +)

        // 手牌采纳：出牌记录开始前，识别到 ≥10 张且比当前多 → 替换
        if playSeq == 0, newHandTotal >= 10, newHandTotal > handTotal {
            hand = newHand
            handTotal = newHandTotal
            remaining = deck.counts
            for r in PokerRank.displayOrder {
                remaining[r.rawValue] = max(0, deck.count(r) - hand[r.rawValue])
            }
            if !handAnnounced {
                handAnnounced = true
                pushSnapshot(note: "识别到手牌 \(newHandTotal) 张")
            }
        }

        // 区域对比：变多 → 立即扣；变少 → 连续两帧一致才重置基准
        var anyEmpty = true
        for seat in Seat.all {
            guard let current = zones[seat] else { continue }
            if current.contains(where: { $0 > 0 }) { anyEmpty = false }
            let lastConfirmed = confirmed[seat] ?? [Int](repeating: 0, count: 14)
            let curTotal = current.reduce(0, +)
            let conTotal = lastConfirmed.reduce(0, +)

            if curTotal < conTotal {
                let streak = (lessStreak[seat] ?? 0) + 1
                lessStreak[seat] = streak
                if streak >= 2 { confirmed[seat] = current }   // 两帧一致 → 重置基准
            } else {
                lessStreak[seat] = 0
                var added = [Int](repeating: 0, count: 14)
                var any = false
                for i in 0..<14 {
                    let d = current[i] - lastConfirmed[i]
                    if d > 0 { added[i] = d; any = true }
                }
                if any {
                    for i in 0..<14 { remaining[i] = max(0, remaining[i] - added[i]) }
                    playSeq += 1
                    let cards = cardsText(added)
                    let rec = PlayEntry(seq: playSeq, player: seat, cards: cards)
                    log.append(rec)
                    if log.count > 60 { log.removeFirst(log.count - 60) }
                    lastBySeat[seat] = cards
                    pushHand(rec)
                }
                confirmed[seat] = current
            }
        }

        // 自动判局结束：全场连续无牌 ~20 秒 → 重置等下一局
        if anyEmpty && newHandTotal == 0 && playSeq > 0 {
            idleFrames += 1
            if idleFrames >= 45 {
                idleFrames = 0
                reset(gameIncrement: true, note: "检测到本局结束，已重置；下一局发牌后自动识别")
            }
        } else if newHandTotal > 0 || !anyEmpty {
            idleFrames = 0
        }
    }

    private func cardsText(_ counts: [Int]) -> String {
        var parts: [String] = []
        for r in PokerRank.displayOrder {
            let n = counts[r.rawValue]
            if n > 0 { parts.append(n > 1 ? "\(r.label)x\(n)" : r.label) }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 通知（显示 + 数据回传主App）

    private func snapshot(note: String) -> CounterSnapshot {
        CounterSnapshot(
            gameNo: gameNo,
            deckHex: deck.hex,
            remaining: remaining,
            hand: hand,
            handTotal: handTotal,
            playSeq: playSeq,
            lastBySeat: lastBySeat,
            log: Array(log.suffix(30)),
            note: note
        )
    }

    private func pushSnapshot(note: String) {
        sendNotification(title: "五十K记牌器", body: note, snapshot: snapshot(note: note), ephemeral: false)
    }

    private func pushHand(_ rec: PlayEntry) {
        // 关键剩余提示：所出牌中第一个 rank 的剩余
        var tip = ""
        for r in PokerRank.displayOrder where rec.cards.contains(r.label) {
            let left = remaining[r.rawValue]
            tip = "｜\(r.label)剩\(left)"
            break
        }
        var extra = ""
        if let best = PokerRank.displayOrder.first(where: { remaining[$0.rawValue] == 1 }) {
            extra = " ⚠\(best.label)剩1"
        }
        let body = "第\(rec.seq)手 · \(rec.player)家出 \(rec.cards)\(tip)\(extra)"
        sendNotification(title: "五十K记牌器 · 第\(gameNo)局", body: body, snapshot: snapshot(note: ""), ephemeral: true)
    }

    private func sendNotification(title: String, body: String, snapshot snap: CounterSnapshot, ephemeral: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let data = try? JSONEncoder().encode(snap) {
            content.userInfo = ["snap": data]
        }
        let id = "jp-\(UUID().uuidString)"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
        if ephemeral {
            // 横幅展示后从通知中心移除，保持列表干净
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                UNUserNotificationCenter.current()
                    .removeDeliveredNotifications(withIdentifiers: [id])
            }
        }
    }
}
