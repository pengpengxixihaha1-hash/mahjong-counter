import Foundation
import ActivityKit

/// 记牌核心状态：
///  - 主用：广播扩展自动识别，每手牌通过本地通知把全量快照发回来 → [applyRemote]
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
    @Published var activityRunning = false

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

    // MARK: - 广播识别数据接入

    /// 应用扩展发来的全量快照
    func applyRemote(_ snap: CounterSnapshot) {
        if snap.remaining.count == 14 { remaining = snap.remaining }
        if snap.hand.count == 14 { hand = snap.hand }
        handTotal = snap.handTotal
        playSeq = snap.playSeq
        if !snap.log.isEmpty { playLog = snap.log }
        lastBySeat = snap.lastBySeat
        gameNo = max(gameNo, snap.gameNo)
        note = snap.note
        if let p = DeckPreset.fromHex(snap.deckHex) { deck = p }
        save()
        syncActivity()
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
    }

    func setDeck(_ p: DeckPreset) {
        deck = p
        defaults.set(p.hex, forKey: Self.keyDeck)
        remaining = deck.counts
        NotificationBridge.shared.sendDeck(p.hex)
        save()
        syncActivity()
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
