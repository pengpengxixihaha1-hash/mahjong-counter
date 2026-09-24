import Foundation
import ActivityKit

struct PlayRecord: Codable, Identifiable {
    let seq: Int
    let tile: String
    var id: Int { seq }
}

/// 记牌核心状态：34 种牌各 4 张，点牌即扣并记入出牌顺序。
/// 手动记牌模式：打出一手牌后回到 App 点对应牌格一下。
@MainActor
final class CounterStore: ObservableObject {
    static let perTile = 4

    @Published private(set) var remaining: [Int: Int] = [:]
    @Published private(set) var hand: [Int: Int] = [:]
    @Published private(set) var playLog: [PlayRecord] = []
    @Published private(set) var gameNo = 1
    @Published var activityRunning = false

    private let defaults: UserDefaults
    private static let keyState = "mj_counter_state_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        activityRunning = !Activity<CounterActivityAttributes>.activities.isEmpty
    }

    var totalRemaining: Int { remaining.values.reduce(0, +) }

    func count(_ t: Tile) -> Int { remaining[t.id] ?? 0 }

    func lowTiles() -> [Tile] { Tile.all.filter { count($0) == 1 } }

    /// 打出一张牌：剩余 -1，记入出牌顺序
    func tap(_ t: Tile) {
        let cur = count(t)
        guard cur > 0 else { return }
        remaining[t.id] = cur - 1
        playLog.append(PlayRecord(seq: playLog.count + 1, tile: t.label))
        save()
        syncActivity()
    }

    /// 回滚：多扣了 +1，并撤销最后一条对应记录
    func addBack(_ t: Tile) {
        remaining[t.id] = min((remaining[t.id] ?? 0) + 1, Self.perTile)
        if let idx = playLog.lastIndex(where: { $0.tile == t.label }) {
            playLog.remove(at: idx)
        }
        save()
        syncActivity()
    }

    /// 新一局：剩余恢复为 每种4张 - 手牌，清空出牌顺序
    func newGame() {
        gameNo += 1
        rebuild()
        playLog = []
        save()
        startActivity()
    }

    /// 设置开局手牌（庄 14 张 / 闲 13 张），剩余 = 每种 4 张 - 手牌
    func applyHand(_ h: [Int: Int]) {
        hand = h.filter { $0.value > 0 }
        rebuild()
        save()
        syncActivity()
    }

    func clearHand() {
        hand = [:]
        rebuild()
        save()
        syncActivity()
    }

    private func rebuild() {
        var r: [Int: Int] = [:]
        for t in Tile.all { r[t.id] = Self.perTile - (hand[t.id] ?? 0) }
        remaining = r
    }

    // MARK: - 持久化（杀掉 App 不丢数据）

    private struct Saved: Codable {
        var remaining: [Int: Int]
        var hand: [Int: Int]
        var playLog: [PlayRecord]
        var gameNo: Int
    }

    private func save() {
        let s = Saved(remaining: remaining, hand: hand, playLog: playLog, gameNo: gameNo)
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Self.keyState)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: Self.keyState),
           let s = try? JSONDecoder().decode(Saved.self, from: data) {
            remaining = s.remaining
            hand = s.hand
            playLog = s.playLog
            gameNo = s.gameNo
        } else {
            gameNo = 1
            rebuild()
        }
    }

    // MARK: - 灵动岛 / 锁屏实时活动

    private func makeState() -> CounterActivityAttributes.ContentState {
        let low = lowTiles().map(\.label).joined(separator: " ")
        let last = playLog.last
        return .init(
            gameNo: gameNo,
            totalRemaining: totalRemaining,
            lastPlay: last?.tile ?? "—",
            lastSeq: last?.seq ?? 0,
            lowTiles: low.isEmpty ? "" : "⚠ 剩1张：\(low)"
        )
    }

    /// 开启实时活动（新一局时自动开；也可在主界面手动开关）
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
            Task { await a.end(.init(state: makeState(), staleDate: nil), dismissalPolicy: .immediate) }
        }
        activityRunning = false
    }

    /// 点牌后把最新状态推到灵动岛
    private func syncActivity() {
        guard let a = Activity<CounterActivityAttributes>.activities.first else { return }
        let state = makeState()
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }
}
