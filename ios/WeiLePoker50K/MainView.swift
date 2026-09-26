import SwiftUI
import UIKit

@MainActor
final class MainViewModel: ObservableObject {
    @Published var snapshot = IPC.Snapshot.empty
    @Published var sampleCount = 0
    @Published var collecting = IPC.collecting
    @Published var showExporter = false
    @Published var exportDir: URL?
    @Published var toast = ""

    let pip = PipController()

    private var pollTimer: Timer?

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    private func poll() {
        snapshot = IPC.read()
        sampleCount = IPC.sampleFiles().count
    }

    func toggleCollecting(_ on: Bool) {
        IPC.collecting = on
        collecting = on
    }

    /// 浮窗预览挂载后调用（保证 displayLayer 在视图层级里）
    func attachPreview(_ container: UIView) {
        pip.setup(in: container)
    }

    func startPip() {
        AudioKeepAlive.start()
        pip.startPip()
    }

    func stopPip() {
        pip.stopPip()
        AudioKeepAlive.stop()
    }

    func exportSamples() {
        guard let dir = IPC.copySamplesToDocuments() else {
            toast = "没有可导出的样本"
            return
        }
        exportDir = dir
        showExporter = true
    }

    func newGameFlagAck() {
        snapshot.newGame = false
    }
}

struct MainView: View {
    @StateObject var vm: MainViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    statusCard
                    controlsCard
                    sampleCard
                    hintCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("五十K记牌器")
            .onAppear { vm.start() }
            .onTapGesture { hideKeyboard() }
            .sheet(isPresented: $vm.showExporter) {
                if let dir = vm.exportDir {
                    SampleExportView(dirURL: dir)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // 浮窗预览（displayLayer 必须挂在可见层级上，PiP 才能启动）
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("浮窗预览（PiP 启动后悬浮于游戏上方）")
                .font(.footnote)
                .foregroundColor(.secondary)
            OverlayPreviewContainer(vm: vm)
                .frame(width: CounterOverlayView.canvasSize.width / 2,
                       height: CounterOverlayView.canvasSize.height / 2)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("状态").font(.headline)
                Spacer()
                if vm.snapshot.newGame {
                    Text("新一局，已重置").font(.caption).foregroundColor(.green)
                }
            }
            Text(vm.snapshot.status)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !vm.snapshot.seats.isEmpty {
                let m = vm.snapshot.main
                let order = CounterOverlayView.order
                let labels = CounterOverlayView.label
                Text("主条 " + order.map { "\((labels[$0] ?? $0))\(m[$0].map(String.init) ?? "-")" }.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                ForEach(vm.snapshot.seats, id: \.name) { s in
                    Text("\(s.name) 剩 \(s.left)" + (s.cards.isEmpty ? "" : "  \(s.cards)"))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var controlsCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("样本采集模式").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.collecting },
                    set: { vm.toggleCollecting($0) }))
                    .labelsHidden()
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("① 开始录屏广播").font(.subheadline.weight(.medium))
                    Text("弹窗里选择「五十K记牌器」，再切到微乐打牌")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                BroadcastPickerView()
                    .frame(width: 60, height: 60)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("② 启动浮窗").font(.subheadline.weight(.medium))
                    Text(vm.pip.pipActive ? "浮窗运行中，可拖到角落" : "画中画小窗，浮在微乐上方")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(vm.pip.pipActive ? "停止浮窗" : "启动浮窗") {
                    if vm.pip.pipActive {
                        vm.stopPip()
                    } else {
                        vm.startPip()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.pip.pipPossible && !vm.pip.pipActive)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("识别样本").font(.headline)
                Spacer()
                Text("\(vm.sampleCount) 帧").font(.caption).foregroundColor(.secondary)
            }
            Text("阶段 1 仅采集对局帧样本，用于制作手机版识别模板；识别功能在样本标定后开启。")
                .font(.caption).foregroundColor(.secondary)
            Button("导出样本（复制到文件 / 文件共享）") { vm.exportSamples() }
                .buttonStyle(.bordered)
                .disabled(vm.sampleCount == 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("使用顺序").font(.headline)
            Text("① 打开「样本采集模式」→ ② 点录屏按钮开始广播 → ③ 切到微乐打一局 → ④ 回这里导出样本发给电脑 → ⑤ （模板制作后）启动浮窗看剩余牌数")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// SwiftUI 包 UIKit 容器：挂载 overlayView + displayLayer
private struct OverlayPreviewContainer: UIViewRepresentable {
    let vm: MainViewModel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.addSubview(vm.pip.overlayView)
        vm.pip.overlayView.frame = CGRect(origin: .zero, size: CounterOverlayView.canvasSize)
        vm.attachPreview(v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
