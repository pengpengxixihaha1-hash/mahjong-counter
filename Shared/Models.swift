import Foundation
import ActivityKit

/// 花色
enum Suit: String, CaseIterable, Codable, Identifiable {
    case wan = "万"
    case tong = "筒"
    case tiao = "条"
    case zi = "字"

    var id: String { rawValue }
}

/// 一张麻将牌（共 34 种，每种 4 张）
struct Tile: Codable, Hashable, Identifiable {
    let id: Int        // 全局序号 0~33
    let label: String  // 完整名：1万 / 东
    let short: String  // 牌格短名：1 / 东（花色由行首标签说明）
    let suit: Suit

    static let all: [Tile] = {
        var tiles: [Tile] = []
        var id = 0
        for n in 1...9 { tiles.append(Tile(id: id, label: "\(n)万", short: "\(n)", suit: .wan)); id += 1 }
        for n in 1...9 { tiles.append(Tile(id: id, label: "\(n)筒", short: "\(n)", suit: .tong)); id += 1 }
        for n in 1...9 { tiles.append(Tile(id: id, label: "\(n)条", short: "\(n)", suit: .tiao)); id += 1 }
        for l in ["东", "南", "西", "北", "中", "发", "白"] {
            tiles.append(Tile(id: id, label: l, short: l, suit: .zi))
            id += 1
        }
        return tiles
    }()

    static func of(_ suit: Suit) -> [Tile] { all.filter { $0.suit == suit } }
}

/// 灵动岛 / 锁屏实时活动的数据定义（主 App 与 Widget 扩展共用）
struct CounterActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var gameNo: Int          // 第几局
        var totalRemaining: Int  // 全场剩余张数
        var lastPlay: String     // 最近打出的牌
        var lastSeq: Int         // 第几手
        var lowTiles: String     // 剩 1 张的牌提示
    }
}
