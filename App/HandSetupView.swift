import SwiftUI

/// 开局手牌录入：庄家 14 张 / 闲家 13 张。
/// 设置后剩余 = 每种 4 张 - 手牌；出牌过程在主界面继续点扣。
struct HandSetupView: View {
    @EnvironmentObject var store: CounterStore
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [Int: Int] = [:]

    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("开局发完牌后，把你的手牌点进来：点一下 +1，长按 -1")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Suit.allCases) { suit in
                    HStack(spacing: 5) {
                        Text(suit.rawValue)
                            .font(.caption.bold()).foregroundColor(.yellow)
                            .frame(width: 20)
                        ForEach(Tile.of(suit)) { tile in
                            cell(tile)
                        }
                    }
                }
                HStack {
                    Text("合计 \(total) 张").font(.headline).foregroundColor(.white)
                    Spacer()
                    Button("清空") { counts = [:] }
                        .font(.caption).foregroundColor(.orange)
                    Button("确定") {
                        store.applyHand(counts)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(white: 0.07).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("设置手牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { counts = store.hand }
        }
    }

    private func cell(_ tile: Tile) -> some View {
        let n = counts[tile.id] ?? 0
        return VStack(spacing: 2) {
            Text(tile.short).font(.system(size: 14, weight: .semibold))
            Text("\(n)").font(.system(size: 18, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 8).fill(n > 0 ? Color.blue.opacity(0.35) : Color(white: 0.16)))
        .foregroundColor(n > 0 ? .white : Color(white: 0.6))
        .contentShape(Rectangle())
        .onTapGesture {
            let cur = counts[tile.id] ?? 0
            if cur < 4 { counts[tile.id] = cur + 1 }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            let cur = counts[tile.id] ?? 0
            if cur > 0 { counts[tile.id] = cur - 1 }
        }
    }
}
