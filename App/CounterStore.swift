import Foundation
import ActivityKit

/// 记牌核心状态：
///  - 主用：广播扩展自动识别，通过 Darwin 事件回传（jp.h 手牌 / jp.o 出牌 / jp.f 局结束）
///  - 兜底：手动点牌（识别不准时用），点一下扣一张记一手。
@MainActor
final class CounterStore: ObservableObject {

    @Published private(set) var remaining: [Int] = DeckPreset.default.counts
    @Published private(set) var hand: [Int] = [Int](repeating: 0, count: 14)
    @Published private(set) var handTotal = 0
    @Published private(set) var playLog: [PlayEntry] = []
    @Published private(set) var lastBySeat: [String: String] = [:]
    @Published private(set) var gameNo = 1
    @Published private(set) var playSeq = 0
    @Published private(set) var note = ""
    /// 识别诊断（扩展每约2秒回传：牌块数/手牌数/四区计数）
    @Published private(set) var diag = ""
    @Published var activityRunning = false
    /// 画中画悬浮窗开关（切到游戏后自动变成可拖动小窗）
    @Published var pipOn = false

    /// 当前牌型（发给扩展）
    @Published private(set) var deck: DeckPreset

    private let defaults: UserDefaults
    private static let keyState = "pk_counter_state_v1"
    private static let keyDeck = "pk_deck_hex"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let hex = defaults.string(forKey: Self.keyDeck),
           let p = DeckPreset.fromHex(hex) {
            deck = p
        } else {
            deck = .default
        }
        remaining = deck.counts
        load()
        activityRunning = !Activity<CounterActivityAttributes>.activities.isEmpty
    }

    var totalRemaining: Int { remaining.reduce(0, +) }

    func count(_ r: PokerRank) -> Int { remaining[r.rawValue] }

    func handCount(_ r: PokerRank) -> Int { hand[r.rawValue] }

    func lowTiles() -> [PokerRank] {
        PokerRank.displayOrder.filter { count($0) == 1 }
    }

    // MARK: - 广播识别事件接入（Darwin 通道）

    /// 扩展识别到手牌：剩余 = 牌型总数 - 手牌
    func applyHandEvent(_ counts: [Int]) {
        guard playSeq == 0 else { return }   // 已记出牌后不再改动手牌基数
        hand = counts
        handTotal = counts.reduce(0, +)
        remaining = deck.counts
        for r in PokerRank.displayOrder {
            remaining[r.rawValue] = max(0, deck.count(r) - hand[r.rawValue])
        }
        note = "识别到手牌 \(handTotal) 张"
        save()
        syncActivity()
        refreshPip()
    }

    /// 扩展识别到一手出牌：扣减对应牌数
    func applyPlayEvent(seatIdx: Int, counts: [Int]) {
        guard seatIdx >= 0, seatIdx < Seat.all.count, counts.count == 14 else { return }
        let seat = Seat.all[seatIdx]
        for i in 0..<14 where counts[i] > 0 {
            remaining[i] = max(0, remaining[i] - counts[i])
        }
        playSeq += 1
        let cards = cardsText(counts)
        playLog.append(PlayEntry(seq: playSeq, player: seat, cards: cards))
        lastBySeat[seat] = cards
        note = "第\(playSeq)手 · \(seat)家出 \(cards)"
        save()
        syncActivity()
        refreshPip()
    }

    /// 扩展自动判局结束：换局重置
    func applyEndGame() {
        gameNo += 1
        remaining = deck.counts
        hand = [Int](repeating: 0, count: 14)
        handTotal = 0
        playLog = []
        playSeq = 0
        lastBySeat = [:]
        note = "检测到本局结束，已换局；发牌后自动识别新手牌"
        save()
        syncActivity()
        refreshPip()
    }

    /// 更新诊断文本
    func setDiag(_ text: String) {
        diag = text
    }

    // MARK: - 画中画悬浮窗

    /// 把当前状态推给悬浮窗渲染（每帧 = 一张最新牌表）
    func refreshPip() {
        PipController.shared.push(PipState(
            gameNo: gameNo,
            total: totalRemaining,
            seq: playSeq,
            remaining: remaining,
            lastBySeat: lastBySeat
        ))
    }

    /// 开 / 关悬浮窗
    func togglePip() {
        if pipOn {
            PipController.shared.stop()
        } else {
            PipController.shared.onChange = { [weak self] in
                guard let self else { return }
                if self.pipOn != PipController.shared.running { self.pipOn = PipController.shared.running }
            }
            PipController.shared.start()
            pipOn = PipController.shared.running
            refreshPip()
        }
    }

    // MARK: - 手动点牌（兜底）

    /// 打出一张牌：剩余 -1，记入出牌顺序
    func tap(_ r: PokerRank) {
        let cur = count(r)
        guard cur > 0 else { return }
        remaining[r.rawValue] = cur - 1
        playSeq += 1
        playLog.append(PlayEntry(seq: playSeq, player: "手记", cards: r.label))
        lastBySeat["手记"] = r.label
        save()
        syncActivity()
        refreshPip()
    }

    /// 回滚：多扣了 +1，撤销最后一条对应记录
    func addBack(_ r: PokerRank) {
        remaining[r.rawValue] = min(count(r) + 1, deck.count(r))
        if let idx = playLog.lastIndex(where: { $0.player == "手记" && $0.cards == r.label }) {
            playLog.remove(at: idx)
            playSeq = playLog.last?.seq ?? 0
        }
        save()
        syncActivity()
        refreshPip()
    }

    // MARK: - 开场 / 牌型

    /// 手动设置开局手牌：剩余 = 牌型总数 - 手牌
    func applyHand(_ counts: [Int: Int]) {
        var h = [Int](repeating: 0, count: 14)
        for (k, v) in counts where k >= 0 && k < 14 { h[k] = v }
        hand = h
        handTotal = h.reduce(0, +)
        remaining = deck.counts
        for r in PokerRank.displayOrder {
            remaining[r.rawValue] = max(0, deck.count(r) - h[r.rawValue])
        }
        save()
        syncActivity()
        refreshPip()
    }

    /// 开场按钮：重置本局，并把牌型 + 开场指令发给广播扩展
    func newGame() {
        gameNo += 1
        remaining = deck.counts
        hand = [Int](repeating: 0, count: 14)
        handTotal = 0
        playLog = []
        playSeq = 0
        lastBySeat = [:]
        note = "已开始第 \(gameNo) 局"
        NotificationBridge.shared.sendDeck(deck.hex)
        NotificationBridge.shared.sendReset()
        save()
        startActivity()
        refreshPip()
    }

    func setDeck(_ p: DeckPreset) {
        deck = p
        defaults.set(p.hex, forKey: Self.keyDeck)
        remaining = deck.counts
        NotificationBridge.shared.sendDeck(p.hex)
        save()
        syncActivity()
        refreshPip()
    }

    // MARK: - 持久化

    private struct Saved: Codable {
        var remaining: [Int]
        var hand: [Int]
        var handTotal: Int
        var playLog: [PlayEntry]
        var lastBySeat: [String: String]
        var gameNo: Int
        var playSeq: Int
    }

    private func save() {
        let s = Saved(remaining: remaining, hand: hand, handTotal: handTotal,
                      playLog: playLog, lastBySeat: lastBySeat, gameNo: gameNo, playSeq: playSeq)
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Self.keyState)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: Self.keyState),
           let s = try? JSONDecoder().decode(Saved.self, from: data),
           s.remaining.count == 14 {
            remaining = s.remaining
            hand = s.hand
            handTotal = s.handTotal
            playLog = s.playLog
            lastBySeat = s.lastBySeat
            gameNo = s.gameNo
            playSeq = s.playSeq
        } else {
            remaining = deck.counts
        }
    }

    // MARK: - 灵动岛 / 锁屏

    private func makeState() -> CounterActivityAttributes.ContentState {
        let low = lowTiles().map(\.label).joined(separator: " ")
        let last = playLog.last
        return .init(
            gameNo: gameNo,
            totalRemaining: totalRemaining,
            lastPlay: last.map { "\($0.player): \($0.cards)" } ?? "—",
            lastSeq: last?.seq ?? 0,
            lowTiles: low.isEmpty ? "" : "⚠ 剩1张：\(low)"
        )
    }

    func startActivity() {
        endActivity()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity<CounterActivityAttributes>.request(
                attributes: CounterActivityAttributes(),
                content: .init(state: makeState(), staleDate: nil)
            )
            activityRunning = true
        } catch {
            activityRunning = false
        }
    }

    func endActivity() {
        for a in Activity<CounterActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        activityRunning = false
    }

    private func syncActivity() {
        guard let a = Activity<CounterActivityAttributes>.activities.first else { return }
        let state = makeState()
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }
}
