import SwiftUI

/// 牌型设置：选择本场牌各多少张（预设档）。
/// 保存后立即通过 Darwin 通知同步给广播识别扩展。
struct DeckSetupView: View {
    @EnvironmentObject var store: CounterStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("本场牌型：选择各种牌的张数档位")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(DeckPreset.all, id: \.name) { preset in
                    Button {
                        store.setDeck(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("共 \(preset.total) 张 · 王\(preset.count(.joker)) · 2×\(preset.count(.r2)) K×\(preset.count(.rK)) 8×\(preset.count(.r8))")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            Spacer()
                            if preset == store.deck {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(preset == store.deck ? Color.green.opacity(0.15) : Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                }

                Text("说明：识别扩展按当前档位计算剩余牌；换档后重新点「开场」生效。\n微乐五十K一般选第一档（王6·各8）。")
                    .font(.caption2).foregroundColor(Color(white: 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(white: 0.07).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("牌型设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
