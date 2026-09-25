import SwiftUI

/// 开局手牌录入：把你的手牌点进来（+1 / 长按-1），
/// 剩余 = 牌型总数 - 手牌；广播识别成功后会被自动识别结果覆盖。
struct HandSetupView: View {
    @EnvironmentObject var store: CounterStore
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [Int: Int] = [:]

    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("发完牌后，把你的手牌点进来：点一下 +1，长按 -1\n（开着广播时会自动识别，也可不填）")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(PokerRank.displayOrder.dropFirst(row == 0 ? 0 : 7).prefix(7)) { rank in
                            cell(rank)
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
            .onAppear {
                counts = [:]
                for r in PokerRank.displayOrder where store.handCount(r) > 0 {
                    counts[r.rawValue] = store.handCount(r)
                }
            }
        }
    }

    private func cell(_ rank: PokerRank) -> some View {
        let n = counts[rank.rawValue] ?? 0
        return VStack(spacing: 2) {
            Text(rank.label).font(.system(size: 13, weight: .semibold))
            Text("\(n)").font(.system(size: 18, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 8).fill(n > 0 ? Color.blue.opacity(0.35) : Color(white: 0.16)))
        .foregroundColor(n > 0 ? .white : Color(white: 0.6))
        .contentShape(Rectangle())
        .onTapGesture {
            let cur = counts[rank.rawValue] ?? 0
            if cur < store.deck.count(rank) { counts[rank.rawValue] = cur + 1 }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            let cur = counts[rank.rawValue] ?? 0
            if cur > 0 { counts[rank.rawValue] = cur - 1 }
        }
    }
}
