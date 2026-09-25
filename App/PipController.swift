import AVKit
import AVFoundation
import CoreMedia
import CoreVideo
import CoreText
import SwiftUI
import UIKit

// MARK: - 悬浮窗渲染状态

struct PipState: Equatable {
    var gameNo: Int = 1
    var total: Int = 0
    var seq: Int = 0
    var remaining: [Int] = Array(repeating: 0, count: 14)
    var lastBySeat: [String: String] = [:]
    static let empty = PipState()
}

// MARK: - 画中画悬浮窗控制器
/// iOS 没有系统悬浮窗 API，唯一可行方案 = 画中画（PiP）：
///  1. 把记牌状态渲染成 640x420 视频帧喂给 AVSampleBufferDisplayLayer
///  2. AVPictureInPictureController 在切到游戏时把画面变成可拖动的悬浮小窗
///  3. 静音音频后台保活（UIBackgroundModes=audio），保证游戏内持续刷新
final class PipController: NSObject {

    static let shared = PipController()

    private(set) var running = false
    /// 状态变化回调（主线程），UI 据此刷新按钮
    var onChange: (() -> Void)?
    private var lastState = PipState.empty

    private var layer: AVSampleBufferDisplayLayer?
    private var pip: AVPictureInPictureController?
    private var formatDesc: CMVideoFormatDescription?
    private var frameIdx: Int64 = 0
    private var heartbeat: Timer?
    private var keepAlive: AVAudioPlayer?

    static var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// 预览用：把当前渲染层交给 SwiftUI 宿主 view
    var layerForPreview: CALayer? { layer }

    // MARK: 开关

    func start() {
        guard Self.supported, !running else { return }
        let l = AVSampleBufferDisplayLayer()
        l.videoGravity = .resizeAspect
        l.frame = CGRect(x: 0, y: 0, width: 640, height: 420)
        l.backgroundColor = UIColor(red: 0.055, green: 0.067, blue: 0.086, alpha: 1).cgColor
        guard let src = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: l, playbackDelegate: self),
              let p = AVPictureInPictureController(contentSource: src) else { return }
        p.canStartPictureInPictureAutomaticallyFromInline = true
        p.delegate = self
        layer = l
        pip = p
        running = true
        startKeepAlive()
        push(lastState)   // 立即出第一帧
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.push(self.lastState) }
        }
        notifyChange()
    }

    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        keepAlive?.stop(); keepAlive = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        pip?.stopPictureInPicture()
        layer?.flush()
        pip = nil; layer = nil
        running = false
        notifyChange()
    }

    private func notifyChange() {
        if Thread.isMainThread { onChange?() } else { DispatchQueue.main.async { self.onChange?() } }
    }

    // MARK: 喂帧

    /// 状态变化时调用；渲染与 enqueue 线程安全
    func push(_ s: PipState) {
        lastState = s
        guard running, let l = layer else { return }
        guard let pb = render(s) else { return }
        if formatDesc == nil {
            var fd: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fd)
            formatDesc = fd
        }
        guard let fd = formatDesc else { return }
        frameIdx += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: CMTime(value: CMTimeValue(frameIdx), timescale: 10),
            decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pb, formatDescription: fd,
            sampleTiming: &timing, sampleBufferOut: &sb)
        guard let sb else { return }
        CMSetAttachment(sb, key: kCMSampleAttachmentKey_DisplayImmediately as CFString, value: kCFBooleanTrue, attachmentMode: 1)
        l.enqueue(sb)
    }

    // MARK: 渲染（640x420，原点左下）

    private func render(_ s: PipState) -> CVPixelBuffer? {
        let w = 640, h = 420
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb),
              let ctx = CGContext(
                  data: base, width: w, height: h, bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        // 背景
        ctx.setFillColor(red: 0.055, green: 0.067, blue: 0.086, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // 顶部：局数 / 总剩余 / 手数
        drawText(ctx, "第\(s.gameNo)局 · 剩\(s.total)张 · \(s.seq)手",
                 rect: CGRect(x: 16, y: h - 46, width: w - 32, height: 34),
                 size: 22, bold: true, color: .systemGreen)

        // 牌表两行，每行 7 列（王 2 A K Q J 10 / 9 8 7 6 5 4 3）
        let order = PokerRank.displayOrder
        let cellW = CGFloat(w) / 7.0
        for row in 0..<2 {
            let yTop = CGFloat(h) - 180 - CGFloat(row) * 102
            for col in 0..<7 {
                let r = order[row * 7 + col]
                let x = CGFloat(col) * cellW
                let n = s.remaining[r.rawValue]
                let numColor: UIColor = n == 0 ? UIColor(white: 0.42, alpha: 1)
                    : (n == 1 ? .systemRed : (n == 2 ? .systemOrange : .white))
                drawText(ctx, r.label,
                         rect: CGRect(x: x, y: yTop + 48, width: cellW, height: 26),
                         size: 19, bold: true, color: UIColor(white: 0.75, alpha: 1), centered: true)
                drawText(ctx, "\(n)",
                         rect: CGRect(x: x, y: yTop, width: cellW, height: 44),
                         size: 30, bold: true, color: numColor, centered: true)
            }
        }

        // 四家最近出牌（对 上 / 我 下）
        for (i, seat) in Seat.all.enumerated() {
            let col = i % 2, row = i / 2
            let x = CGFloat(col) * (CGFloat(w) / 2) + 16
            let y = CGFloat(96) - CGFloat(row) * 38
            drawText(ctx, "\(seat): \(s.lastBySeat[seat] ?? "—")",
                     rect: CGRect(x: x, y: y, width: CGFloat(w) / 2 - 24, height: 30),
                     size: 17, bold: false, color: .systemOrange)
        }

        drawText(ctx, "微乐五十K · 出牌自动扣减",
                 rect: CGRect(x: 16, y: 10, width: w - 32, height: 22),
                 size: 13, bold: false, color: UIColor(white: 0.5, alpha: 1))
        return pb
    }

    /// CoreText 画字
    private func drawText(_ ctx: CGContext, _ text: String, rect: CGRect, size: CGFloat, bold: Bool, color: UIColor, centered: Bool = false) {
        guard !text.isEmpty else { return }
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color
        ]))
        ctx.saveGState()
        var pos = CGPoint(x: rect.minX, y: rect.minY + (rect.height - font.lineHeight) / 2)
        if centered {
            let tw = CTLineGetTypographicBounds(line, nil, nil, nil)
            pos.x += max(0, (rect.width - CGFloat(tw)) / 2)
        }
        ctx.textPosition = pos
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: 静音音频后台保活

    private func startKeepAlive() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: Self.silentWav()) else { return }
        p.numberOfLoops = -1
        p.volume = 0.01
        p.play()
        keepAlive = p
    }

    /// 生成 1 秒静音 wav（避免往工程里塞资源文件）
    private static func silentWav() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let sampleRate = 8000, seconds = 1
            var data = Data()
            func add(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
            func add16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
            data.append("RIFF".data(using: .ascii)!); add(UInt32(36 + sampleRate * seconds * 2))
            data.append("WAVE".data(using: .ascii)!)
            data.append("fmt ".data(using: .ascii)!); add(16); add16(1); add16(1)
            add(UInt32(sampleRate)); add(UInt32(sampleRate * 2)); add16(2); add16(16)
            data.append("data".data(using: .ascii)!); add(UInt32(sampleRate * seconds * 2))
            data.append(Data(repeating: 0, count: sampleRate * seconds * 2))
            try? data.write(to: url)
        }
        return url
    }
}

// MARK: - PiP 代理

extension PipController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        // 切到游戏后系统会自动进入此状态，浮窗出现在游戏上方
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {}
}

// MARK: - PiP 播放代理（静态画面：不响应播放控制）

extension PipController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: 3600, timescale: 1))
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { false }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - SwiftUI 预览

struct PipPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> PipLayerView { PipLayerView() }
    func updateUIView(_ v: PipLayerView, context: Context) {
        if let l = PipController.shared.layerForPreview {
            v.attach(l)
        }
    }
}

/// 承载 AVSampleBufferDisplayLayer（PiP 要求 layer 在窗口层级内，前台为内嵌预览，切后台自动变浮窗）
final class PipLayerView: UIView {
    override static var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    private var attached: CALayer?
    func attach(_ l: CALayer) {
        guard attached !== l else { return }
        attached?.removeFromSuperlayer()
        l.frame = bounds
        layer.addSublayer(l)
        attached = l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        attached?.frame = bounds
        CATransaction.commit()
    }
}
