import SwiftUI

/// 主界面：
///  - 「开始识别」→ 系统屏幕广播，识别全自动（每手出牌弹通知提示）
///  - 牌表显示各牌剩余（对手手里有的牌）；四家最近出牌；出牌顺序
///  - 点牌格为手动兜底：识别不准时点一下扣一张，长按加回
struct ContentView: View {
    @EnvironmentObject var store: CounterStore
    @State private var showHand = false
    @State private var showDeck = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                startButton
                if !store.note.isEmpty {
                    Text(store.note)
                        .font(.caption).foregroundColor(.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !store.diag.isEmpty {
                    Text("诊断 " + store.diag)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Color(white: 0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !store.lowTiles().isEmpty {
                    Text("⚠ 剩 1 张：" + store.lowTiles().map(\.label).joined(separator: " "))
                        .font(.footnote).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if store.pipOn {
                    pipPreview
                }
                seatSection
                remainingGrid
                tapSection
                logSection
            }
            .padding()
        }
        .background(Color(white: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHand) { HandSetupView() }
        .sheet(isPresented: $showDeck) { DeckSetupView() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(store.gameNo) 局").font(.headline).foregroundColor(.white)
                Text("对手共持 \(store.totalRemaining) 张 · 已出 \(store.playSeq) 手 · \(store.deck.name)")
                    .font(.caption2).foregroundColor(.gray)
            }
            Spacer()
            Button {
                if store.activityRunning { store.endActivity() } else { store.startActivity() }
            } label: {
                Text(store.activityRunning ? "灵动岛 开" : "灵动岛 关")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Color.blue.opacity(0.35)))
                    .foregroundColor(.white)
            }
            Button {
                store.togglePip()
            } label: {
                Text(store.pipOn ? "浮窗 开" : "浮窗 关")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.4)))
                    .foregroundColor(.white)
            }
            Button { showHand = true } label: {
                Text("手牌")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Color.indigo.opacity(0.45)))
                    .foregroundColor(.white)
            }
            Button { showDeck = true } label: {
                Text("牌型")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Color.purple.opacity(0.4)))
                    .foregroundColor(.white)
            }
            Button {
                store.newGame()
            } label: {
                Text("开场")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.75)))
                    .foregroundColor(.white)
            }
        }
    }

    private var startButton: some View {
        VStack(spacing: 4) {
            BroadcastPicker()
                .frame(width: 46, height: 46)
            Text("开始识别（选「五十K记牌器」开广播）")
                .font(.footnote.bold()).foregroundColor(.white)
            Text("进游戏出牌即可全自动记牌；每局开始先点「开场」")
                .font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.18)))
    }

    private var pipPreview: some View {
        VStack(spacing: 6) {
            PipPreviewView()
                .frame(maxWidth: .infinity)
                .aspectRatio(640 / 420, contentMode: .fit)
                .background(Color(white: 0.05))
                .cornerRadius(12)
            Text("切到游戏后自动变成悬浮小窗（可拖动缩放），实时显示剩余牌和四家出牌；点小窗上的还原按钮可回到 App")
                .font(.caption2).foregroundColor(.gray)
        }
    }

    private var seatSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("四家最近出牌").font(.caption).foregroundColor(.gray)
            ForEach(Seat.all, id: \.self) { seat in
                HStack {
                    Text(seat).font(.caption.bold()).foregroundColor(.orange).frame(width: 28, alignment: .leading)
                    Text(store.lastBySeat[seat] ?? "—")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.13)))
    }

    private var remainingGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("对手手里剩的牌（每出一张自动减一）").font(.caption).foregroundColor(.gray)
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(PokerRank.displayOrder.dropFirst(row == 0 ? 0 : 7).prefix(7)) { rank in
                        cell(rank)
                    }
                }
            }
        }
    }

    private func cell(_ rank: PokerRank) -> some View {
        let n = store.count(rank)
        return VStack(spacing: 2) {
            Text(rank.label).font(.system(size: 13, weight: .semibold))
            Text("\(n)").font(.system(size: 18, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(n == 0 ? Color(white: 0.25) : Color(white: 0.32), lineWidth: 1))
        .foregroundColor(cellColor(n))
        .contentShape(Rectangle())
        .onTapGesture { store.tap(rank) }
        .onLongPressGesture(minimumDuration: 0.4) { store.addBack(rank) }
    }

    /// 手动兜底行（同牌格可点，识别不准时用）
    private var tapSection: some View {
        Text("识别不准？直接点上面牌格扣牌，长按加回")
            .font(.caption2).foregroundColor(Color(white: 0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellColor(_ n: Int) -> Color {
        switch n {
        case 0: return Color(white: 0.4)
        case 1: return .red
        case 2: return .orange
        default: return .white
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("出牌顺序（最新在上）").font(.caption).foregroundColor(.gray)
            if store.playLog.isEmpty {
                Text("暂无出牌记录；开始识别后自动记录 对/上/我/下 每一手。")
                    .font(.caption2).foregroundColor(Color(white: 0.45))
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.playLog.reversed().prefix(60))) { r in
                        Text("第\(r.seq)手 · \(r.player) · \(r.cards)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.85))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
