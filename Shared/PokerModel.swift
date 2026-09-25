import Foundation

/// 五十K扑克牌面：14 种牌（王 2 A K Q J 10 9 8 7 6 5 4 3）。
/// 每种牌的张数由牌型档位（DeckPreset）决定。
/// 本文件被主 App / Widget / 广播识别扩展共用，只依赖 Foundation。
enum PokerRank: Int, CaseIterable, Codable, Identifiable {
    case joker = 0   // 王
    case r2 = 1
    case rA = 2
    case rK = 3
    case rQ = 4
    case rJ = 5
    case r10 = 6
    case r9 = 7
    case r8 = 8
    case r7 = 9
    case r6 = 10
    case r5 = 11
    case r4 = 12
    case r3 = 13

    /// 牌面文字（悬浮/通知/界面统一用）
    var label: String {
        switch self {
        case .joker: return "王"
        case .r2: return "2"
        case .rA: return "A"
        case .rK: return "K"
        case .rQ: return "Q"
        case .rJ: return "J"
        case .r10: return "10"
        case .r9: return "9"
        case .r8: return "8"
        case .r7: return "7"
        case .r6: return "6"
        case .r5: return "5"
        case .r4: return "4"
        case .r3: return "3"
        }
    }

    /// 识别引擎使用的墨迹文字（与游戏牌角标一致）
    var glyph: String { label }

    var id: Int { rawValue }

    /// 显示顺序：王 2 A K Q J 10 9 8 7 6 5 4 3（即枚举声明序）
    static let displayOrder: [PokerRank] = allCases
}

/// 牌型档位：一场牌里各种牌各有多少张。
/// 通过 Darwin 通知 "jp.d.<hex>" 传给广播识别扩展（hex = 每牌张数 4bit × 14）。
struct DeckPreset: Codable, Equatable {
    var name: String
    var counts: [Int]   // 按 PokerRank.allCases 顺序，各牌张数（0~15）

    var total: Int { counts.reduce(0, +) }

    func count(_ r: PokerRank) -> Int {
        let i = r.rawValue
        return i < counts.count ? counts[i] : 0
    }

    // ---- 内置档位 ----

    /// 微乐五十K（王6张、普通牌各8张）
    static let wlk50k = DeckPreset(
        name: "微乐五十K（王6·各8）",
        counts: [6] + Array(repeating: 8, count: 13)
    )

    /// 2副牌（王4张、普通牌各8张）
    static let twoDecks = DeckPreset(
        name: "2副牌（王4·各8）",
        counts: [4] + Array(repeating: 8, count: 13)
    )

    /// 3副牌（王6张、普通牌各12张）
    static let threeDecks = DeckPreset(
        name: "3副牌（王6·各12）",
        counts: [6] + Array(repeating: 12, count: 13)
    )

    /// 王4·各8 简版（部分场次王只有4张但普通牌8张同2副牌时不需区分，这里给王2·各4的半副组合用）
    static let oneAndHalf = DeckPreset(
        name: "1.5副牌（王6·各6）",
        counts: [6] + Array(repeating: 6, count: 13)
    )

    static let all: [DeckPreset] = [.wlk50k, .twoDecks, .threeDecks, .oneAndHalf]

    static let `default` = DeckPreset.wlk50k

    /// 编码为 Darwin 通知名后缀：每牌 4bit hex × 14 = 14 个字符
    var hex: String {
        counts.prefix(14).map { String(format: "%x", min(max($0, 0), 15)) }.joined()
    }

    /// 从 "jp.d.<hex>" 后缀解码；失败返回 nil
    static func fromHex(_ hex: String) -> DeckPreset? {
        guard hex.count == 14 else { return nil }
        var counts: [Int] = []
        for ch in hex {
            guard let v = ch.hexDigitValue else { return nil }
            counts.append(v)
        }
        guard counts.contains(where: { $0 > 0 }) else { return nil }
        return DeckPreset(name: "自定义", counts: counts)
    }

    /// 预设档位序号（App→扩展握手时若 hex 通知失败，可用固定名 "jp.p<n>" 选档）
    var presetIndex: Int? { DeckPreset.all.firstIndex(where: { $0 == self }) }
}

/// 出牌记录一条
struct PlayEntry: Codable, Equatable {
    var seq: Int       // 本局第几手
    var player: String // 对 / 上 / 我 / 下 / 手记（手动点牌）
    var cards: String  // 如 "222" "王"
}

/// 四家位置名（与识别分区一致）
enum Seat {
    static let all = ["对", "上", "我", "下"]
}

/// 状态快照（广播扩展通过通知 userInfo 传给主 App 的全量数据）
struct CounterSnapshot: Codable {
    var gameNo: Int = 0
    var deckHex: String = DeckPreset.default.hex
    var remaining: [Int] = []      // 按 PokerRank 序，各牌剩余
    var hand: [Int] = []           // 我的手牌（已从剩余中扣除）
    var handTotal: Int = 0
    var playSeq: Int = 0
    var lastBySeat: [String: String] = [:]  // 座位 -> 最近出牌
    var log: [PlayEntry] = []      // 最近 30 手
    var note: String = ""          // 扩展提示（如"识别到手牌 27 张"）
}
