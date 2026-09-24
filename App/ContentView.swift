import SwiftUI

/// 主界面：万/筒/条/字 四行牌格。
/// 点一下 = 打出这张牌（剩余 -1 并记入出牌顺序），长按 = 加回（撤销）。
struct ContentView: View {
    @EnvironmentObject var store: CounterStore
    @State private var showHand = false

    var body: some View {
        VStack(spacing: 10) {
            header
            if !store.lowTiles().isEmpty {
                Text("⚠ 剩 1 张：" + store.lowTiles().map(\.label).joined(separator: " "))
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Suit.allCases) { suit in
                suitRow(suit)
            }
            logSection
        }
        .padding()
        .background(Color(white: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHand) { HandSetupView() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(store.gameNo) 局").font(.headline).foregroundColor(.white)
                Text("全场剩 \(store.totalRemaining) 张 · 已出 \(store.playLog.count) 手")
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
            Button { showHand = true } label: {
                Text("手牌")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Color.indigo.opacity(0.45)))
                    .foregroundColor(.white)
            }
            Button {
                store.newGame()
            } label: {
                Text("新一局")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.75)))
                    .foregroundColor(.white)
            }
        }
    }

    private func suitRow(_ suit: Suit) -> some View {
        HStack(spacing: 5) {
            Text(suit.rawValue)
                .font(.caption.bold())
                .foregroundColor(.yellow)
                .frame(width: 20)
            ForEach(Tile.of(suit)) { tile in
                tileCell(tile)
            }
        }
    }

    private func tileCell(_ tile: Tile) -> some View {
        let n = store.count(tile)
        return VStack(spacing: 2) {
            Text(tile.short).font(.system(size: 14, weight: .semibold))
            Text("\(n)").font(.system(size: 19, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(n == 0 ? Color(white: 0.25) : Color(white: 0.32), lineWidth: 1))
        .foregroundColor(cellColor(n))
        .contentShape(Rectangle())
        .onTapGesture { store.tap(tile) }
        .onLongPressGesture(minimumDuration: 0.4) { store.addBack(tile) }
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
            Text("出牌顺序（最新在上）")
                .font(.caption).foregroundColor(.gray)
            if store.playLog.isEmpty {
                Text("打法：打出一张牌后，回 App 点对应牌格一下；点错长按加回。")
                    .font(.caption2).foregroundColor(Color(white: 0.45))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.playLog.reversed().prefix(60))) { r in
                            Text("第\(r.seq)手 · \(r.tile)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(white: 0.85))
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
