import CoreVideo
import Foundation

// 屏幕识别器（阶段 1 骨架）：
//   阶段 3 接入路径 —— 用真机样本标定 Layout 后：
//     1. cropHand / cropCenter 里的比例参数按 494 帧 PC 样本同法标定
//     2. glyphClusters 在 ROI 灰度带上聚类 → 逐簇裁剪
//     3. CardMatcher.classify 分类 → CardDetection
//     4. PokerLedger.processFrame 出账 → IPC 写快照
// 当前返回空检出（扩展只做样本采集）。
final class ScreenRecognizer {
    struct Layout {
        // 占位比例：手机竖屏的牌桌几何未知，全部待阶段 2 真机标定
        var handBandTop: CGFloat = 0.85     // 手牌区顶部（相对整屏高）
        var tableTop: CGFloat = 0.06        // 中央出牌区顶部
        var tableBottom: CGFloat = 0.62     // 中央出牌区底部
    }

    var layout = Layout()
    private let matcher = CardMatcher()
    private var ledger = PokerLedger()

    var templatesLoaded: Bool {
        !matcher.handTemplates.isEmpty || !matcher.centerTemplates.isEmpty
    }

    init() {
        matcher.loadTemplates()
    }

    /// 单帧识别 → 检出列表（阶段 3 实现；当前恒为空）
    func process(_ pixelBuffer: CVPixelBuffer) -> (hand: [CardDetection], center: [CardDetection]) {
        // TODO(阶段3): 灰度化 → cropHand/cropCenter → 字形聚簇 → classify → 检出
        return ([], [])
    }
}
