import Foundation

/// 五十K扑克的 14 种牌面
enum CardRank: String, CaseIterable, Codable {
    case joker = "王"
    case two = "2", ace = "A", king = "K", queen = "Q", jack = "J"
    case ten = "10", nine = "9", eight = "8", seven = "7"
    case six = "6", five = "5", four = "4", three = "3"

    /// 浮窗显示顺序：王 2 A K Q J 10 9 8 7 6 5 4 3
    static let displayOrder: [CardRank] = [
        .joker, .two, .ace, .king, .queen, .jack,
        .ten, .nine, .eight, .seven, .six, .five, .four, .three,
    ]
}

/// 牌型配置：每种牌在整场牌里的张数（如微乐五十K：王6、其余各8）
struct DeckConfig: Codable, Equatable {
    var counts: [String: Int]

    static let appGroupId = "group.com.mahjongcounter.shared"
    static let storeKey = "deckConfig"

    static var defaults: [String: Int] {
        var d: [String: Int] = [:]
        for r in CardRank.displayOrder { d[r.rawValue] = r == .joker ? 6 : 8 }
        return d
    }

    static func load() -> DeckConfig {
        let u = UserDefaults(suiteName: appGroupId)
        if let data = u?.data(forKey: storeKey),
           let c = try? JSONDecoder().decode(DeckConfig.self, from: data) {
            return c
        }
        return DeckConfig(counts: defaults)
    }

    func save() {
        let u = UserDefaults(suiteName: DeckConfig.appGroupId)
        u?.set(try? JSONEncoder().encode(self), forKey: DeckConfig.storeKey)
    }

    var total: Int { counts.values.reduce(0, +) }
    func count(_ r: CardRank) -> Int { counts[r.rawValue] ?? 0 }
}

/// 游戏实时状态（广播扩展写、主 App 读、浮窗渲染）
struct GameState: Codable {
    var remaining: [String: Int]        // 每种牌剩余张数
    var lastPlays: [String: String]     // 对/上/我/下 -> 最近一次出牌
    var playLog: [String]               // 出牌顺序
    var handText: String                // 我的手牌（识别文本）
    var diag: String                    // 诊断信息
    var started: Bool
    var frames: Int

    static let storeKey = "gameState"

    static func empty() -> GameState {
        var s = GameState(remaining: [:], lastPlays: [:], playLog: [], handText: "", diag: "", started: false, frames: 0)
        for r in CardRank.displayOrder { s.remaining[r.rawValue] = 0 }
        return s
    }

    static func load() -> GameState {
        let u = UserDefaults(suiteName: DeckConfig.appGroupId)
        if let data = u?.data(forKey: storeKey),
           let s = try? JSONDecoder().decode(GameState.self, from: data) {
            return s
        }
        return empty()
    }

    func save() {
        let u = UserDefaults(suiteName: DeckConfig.appGroupId)
        u?.set(try? JSONEncoder().encode(self), forKey: GameState.storeKey)
    }

    /// 剩余总数（对手+我手牌之外的口径：配置总数 - 已打出）
    var remainingTotal: Int { remaining.values.reduce(0, +) }
}
