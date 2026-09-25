import SwiftUI
import AVFoundation
import ReplayKit
import UIKit

@main
struct MainApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - 主界面

struct RootView: View {
    @StateObject private var pip = PiPManager.shared
    @State private var state = GameState.empty()
    @State private var deck = DeckConfig.load()
    @State private var showDeck = false
    @State private var tick: Timer?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // 牌型
                    card(title: "① 牌型配置（本场各牌张数）") {
                        HStack {
                            Text("共 \(deck.total) 张 · 王\(deck.count(.joker)) 其余\(deck.count(.two))/8默认")
                                .font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Button("修改") { showDeck = true }
                                .font(.footnote.bold())
                        }
                    }

                    // 开场
                    card(title: "② 开局") {
                        Button {
                            startGame()
                        } label: {
                            Text("▶ 开场（重置计数，识别到手牌自动校正）")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    // 浮窗
                    card(title: "③ 浮窗（画中画悬浮记牌）") {
                        Button {
                            pip.toggle()
                        } label: {
                            Text(pip.isRunning ? "浮窗 开（点按关闭）" : "浮窗 关（点按开启）")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(pip.isRunning ? .orange : .blue)
                    }

                    // 识别
                    card(title: "④ 开始识别（屏幕广播）") {
                        HStack {
                            BroadcastPicker()
                                .frame(width: 160, height: 40)
                            Spacer()
                            Text("点左侧按钮 → 选「五十K识别」→ 开始广播")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Text("识别中：进游戏打牌，浮窗实时扣牌")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    // 剩余牌
                    card(title: "剩余牌数（出一张少一张）") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                            ForEach(CardRank.displayOrder, id: \.rawValue) { r in
                                VStack(spacing: 2) {
                                    Text(r.rawValue).font(.headline)
                                    Text("\(state.remaining[r.rawValue] ?? deck.count(r))")
                                        .font(.title3.bold())
                                        .foregroundColor(remainingColor(r))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                        Text("合计剩余 \(state.remainingTotal) 张")
                            .font(.footnote).foregroundColor(.secondary)
                    }

                    // 四家出牌
                    card(title: "四家出牌（对=右家 上=上家 我 下=左家）") {
                        ForEach(["对", "上", "我", "下"], id: \.self) { z in
                            HStack {
                                Text(z).font(.headline.bold()).frame(width: 30)
                                Text(state.lastPlays[z] ?? "—")
                                    .font(.body.monospaced())
                                Spacer()
                            }
                        }
                    }

                    // 出牌顺序
                    if !state.playLog.isEmpty {
                        card(title: "出牌顺序记录") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(state.playLog.suffix(18).enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption.monospaced())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // 诊断
                    card(title: "识别诊断（识别不准时把这行发给开发者）") {
                        Text(state.diag.isEmpty ? "尚未开始识别" : state.diag)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("五十K记牌器")
            .background(PiPHostView())
        }
        .onAppear {
            tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                state = GameState.load()
                deck = DeckConfig.load()
            }
        }
        .onDisappear { tick?.invalidate() }
        .sheet(isPresented: $showDeck) { DeckSetupView(deck: $deck) }
    }

    private func remainingColor(_ r: CardRank) -> Color {
        let n = state.remaining[r.rawValue] ?? 0
        if n == 0 { return .gray }
        if r == .joker { return .red }
        return .primary
    }

    private func startGame() {
        var s = GameState.empty()
        for r in CardRank.displayOrder { s.remaining[r.rawValue] = deck.count(r) }
        s.save()
        state = s
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

// MARK: - 牌型设置

struct DeckSetupView: View {
    @Binding var deck: DeckConfig
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [String: Int] = [:]

    var body: some View {
        NavigationView {
            List {
                Section("每种牌的张数") {
                    ForEach(CardRank.displayOrder, id: \.rawValue) { r in
                        Stepper(value: Binding(
                            get: { counts[r.rawValue] ?? 0 },
                            set: { counts[r.rawValue] = min(16, max(0, $0)) }
                        ), in: 0...16) {
                            HStack {
                                Text(r.rawValue).font(.headline).frame(width: 40)
                                Spacer()
                                Text("\(counts[r.rawValue] ?? 0)").font(.title3.bold())
                            }
                        }
                    }
                }
                Section {
                    Button("微乐五十K（王6·其余8）") { preset() }
                    Button("2副牌（王4·其余8）") {
                        for r in CardRank.displayOrder { counts[r.rawValue] = r == .joker ? 4 : 8 }
                    }
                }
            }
            .navigationTitle("牌型设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        deck = DeckConfig(counts: counts)
                        deck.save()
                        dismiss()
                    }
                }
            }
            .onAppear { counts = deck.counts }
        }
    }

    private func preset() {
        for r in CardRank.displayOrder { counts[r.rawValue] = r == .joker ? 6 : 8 }
    }
}

// MARK: - 广播选择按钮

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView()
        v.showsMicrophoneButton = false
        v.preferredExtension = "com.mahjongcounter.app.broadcast"
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - PiP 浮窗（画中画悬浮记牌）

final class PiPManager: NSObject, ObservableObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = PiPManager()

    @Published var isRunning = false

    private var layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var frameIndex: Int64 = 0
    private var feedTimer: Timer?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?

    override init() {
        super.init()
        layer.backgroundColor = UIColor.black.cgColor
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 450)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let src = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: layer,
                playbackDelegate: self
            )
            controller = AVPictureInPictureController(contentSource: src)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    func attach(to view: UIView) {
        layer.removeFromSuperlayer()
        view.layer.addSublayer(layer)
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        keepAliveAudio()
        feedTimer?.invalidate()
        feedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.feedFrame()
        }
        feedFrame()
        controller?.startPictureInPicture()
        isRunning = true
    }

    func stop() {
        controller?.stopPictureInPicture()
        feedTimer?.invalidate()
        feedTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isRunning = false
    }

    /// 静音音频：保证 app 在后台持续运行、浮窗持续刷新
    private func keepAliveAudio() {
        if audioEngine?.isRunning == true { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: UInt32(fmt.sampleRate * 2)) else { return }
            buf.frameLength = buf.frameCapacity // 全零 = 静音
            player.scheduleBuffer(buf, at: nil, options: .loops)
            try engine.start()
            player.play()
            audioEngine = engine
            audioPlayer = player
        } catch {
            // 音频保活失败不致命，浮窗可能退后台后停更
        }
    }

    /// 读状态 → 渲染记牌 UI → 喂帧
    private func feedFrame() {
        guard let controller = controller else { return }
        _ = controller
        let state = GameState.load()
        let image = renderCard(state)
        guard let cg = image.cgImage,
              let pb = pixelBuffer(from: cg) else { return }
        var desc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &desc)
        guard let fd = desc else { return }
        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex), timescale: 2),
            decodeTimeStamp: .invalid
        )
        var sbuf: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pb, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: fd,
            sampleTiming: &timing, sampleBufferOut: &sbuf)
        if let sb = sbuf {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sb)
        }
    }

    /// 渲染浮窗内容（黑底：四家出牌 + 剩余网格）
    private func renderCard(_ state: GameState) -> UIImage {
        let size = CGSize(width: 300, height: 450)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.08, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // 标题
            "剩余牌数".draw(at: CGPoint(x: 10, y: 8), size: 15, color: .white, bold: true)

            // 剩余网格 5 列
            let cols = 5
            let cellW: CGFloat = 56, cellH: CGFloat = 52
            for (i, r) in CardRank.displayOrder.enumerated() {
                let cx = CGFloat(i % cols) * cellW + 10
                let cy = CGFloat(i / cols) * cellH + 32
                let rect = CGRect(x: cx, y: cy, width: cellW - 6, height: cellH - 8)
                UIColor(white: 0.18, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
                r.rawValue.draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 3), size: 13, color: r == .joker ? UIColor.systemRed : .white, bold: true)
                let n = state.remaining[r.rawValue] ?? 0
                "\(n)".draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 22), size: 17, color: n == 0 ? .gray : .systemYellow, bold: true)
            }

            // 四家出牌
            var y: CGFloat = 240
            "最近出牌".draw(at: CGPoint(x: 10, y: y), size: 13, color: .lightGray, bold: true)
            y += 22
            for z in ["对", "上", "我", "下"] {
                z.draw(at: CGPoint(x: 10, y: y), size: 15, color: .cyan, bold: true)
                (state.lastPlays[z] ?? "—").draw(at: CGPoint(x: 38, y: y), size: 14, color: .white, bold: false)
                y += 24
            }

            // 合计
            y += 6
            "合计剩余 \(state.remainingTotal) 张".draw(at: CGPoint(x: 10, y: y), size: 14, color: .systemGreen, bold: true)
        }
    }

    private func pixelBuffer(from cg: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, cg.width, cg.height, kCVPixelFormatType_32BGRA, attrs, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buf, [])
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    // MARK: PiP playback delegate

    func pictureInPictureControllerTimeRange(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(value: 0, timescale: 2),
            duration: CMTime(value: CMTimeValue(frameIndex + 1), timescale: 2)
        )
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // 静态内容，忽略播放/暂停控制
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // 尺寸变化无需处理
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - 绘制小工具

extension String {
    func draw(at point: CGPoint, size: CGFloat, color: UIColor, bold: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.systemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size),
            .foregroundColor: color,
        ]
        NSAttributedString(string: self, attributes: attrs).draw(at: point)
    }
}

// MARK: - PiP 容器视图（把 display layer 挂到 window 上）

struct PiPHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // 放屏幕外但保持渲染（不能 isHidden，否则 layer 不出帧）
        let v = UIView(frame: CGRect(x: -500, y: -500, width: 300, height: 450))
        v.clipsToBounds = true
        PiPManager.shared.attach(to: v)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
