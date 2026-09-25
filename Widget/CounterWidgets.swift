import WidgetKit
import SwiftUI
import ActivityKit

@main
struct CounterWidgetBundle: WidgetBundle {
    var body: some Widget {
        CounterLiveActivity()
    }
}

/// 灵动岛 / 锁屏实时活动：显示当前局数、全场剩余张数、最近出牌、剩 1 张提醒。
/// 数据来源：广播扩展识别 → 通知回传主 App → 主 App 推送更新
/// （App 在后台被挂起时更新会延迟，回到 App 刷新）。
struct CounterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CounterActivityAttributes.self) { context in
            lockScreenView(context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("第\(context.state.gameNo)局")
                            .font(.caption2).foregroundColor(.yellow)
                        Text("剩 \(context.state.totalRemaining)")
                            .font(.title3.bold()).foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("最近出")
                            .font(.caption2).foregroundColor(.gray)
                        Text("\(context.state.lastSeq)手 \(context.state.lastPlay)")
                            .font(.headline).foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        if !context.state.lowTiles.isEmpty {
                            Text(context.state.lowTiles)
                                .font(.caption).foregroundColor(.orange)
                        } else {
                            Text("识别中每手出牌自动更新")
                                .font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
            } compactLeading: {
                Text("记").font(.caption.bold()).foregroundColor(.yellow)
            } compactTrailing: {
                Text("\(context.state.totalRemaining)")
                    .font(.caption.bold()).foregroundColor(.white)
            } minimal: {
                Text("\(context.state.totalRemaining)")
                    .font(.caption2.bold()).foregroundColor(.white)
            }
        }
    }

    private func lockScreenView(_ s: CounterActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("五十K记牌器 · 第\(s.gameNo)局")
                    .font(.caption).foregroundColor(.yellow)
                Spacer()
                Text("全场剩 \(s.totalRemaining) 张")
                    .font(.caption.bold()).foregroundColor(.white)
            }
            HStack {
                Text("最近出牌：第\(s.lastSeq)手 \(s.lastPlay)")
                    .font(.footnote).foregroundColor(.white)
                Spacer()
                if !s.lowTiles.isEmpty {
                    Text(s.lowTiles).font(.caption).foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
