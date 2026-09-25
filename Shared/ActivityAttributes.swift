import Foundation
import ActivityKit

/// 灵动岛 / 锁屏实时活动的数据定义（主 App 与 Widget 扩展共用）。
/// 注意：广播识别扩展不引用本文件（ActivityKit 不得进入扩展）。
struct CounterActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var gameNo: Int          // 第几局
        var totalRemaining: Int  // 全场剩余张数
        var lastPlay: String     // 最近打出的牌（含座位）
        var lastSeq: Int         // 第几手
        var lowTiles: String     // 剩 1 张的牌提示
    }
}
