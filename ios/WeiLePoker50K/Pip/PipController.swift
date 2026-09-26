import AVFoundation
import AVKit
import CoreMedia
import UIKit

// PiP 画中画浮窗：AVSampleBufferDisplayLayer + AVPictureInPictureController（iOS 15+）。
// 主 App 每 0.1s 把浮窗 UI 渲染成帧入队；需静音音频保活（见 AudioKeepAlive）。
final class PipController: NSObject, ObservableObject {
    @Published private(set) var pipActive = false
    @Published private(set) var pipPossible = false

    let overlayView = CounterOverlayView(frame: CGRect(origin: .zero, size: CounterOverlayView.canvasSize))
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private let renderer = BufferRenderer()
    private var timer: Timer?

    /// 挂载 displayLayer 到某个可见视图层级（内嵌预览），并初始化 PiP 控制器
    func setup(in container: UIView) {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = container.bounds
        container.layer.addSublayer(displayLayer)

        if let tb = try? CMTimebase(sourceClock: CMClock.hostTimeClock) {
            displayLayer.controlTimebase = tb
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        pip = controller
        pipPossible = controller.isPictureInPicturePossible

        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pipPossible = controller.isPictureInPicturePossible
        }
        startRenderLoop()
    }

    func startPip() {
        enqueueFrame()
        pip?.startPictureInPicture()
    }

    func stopPip() {
        pip?.stopPictureInPicture()
    }

    private func startRenderLoop() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.enqueueFrame()
        }
    }

    private func enqueueFrame() {
        guard let pb = renderer.render(view: overlayView) else { return }
        let pts = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        if let tb = displayLayer.controlTimebase {
            CMTimebaseSetTime(tb, time: pts)
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        guard let fmt else { return }
        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil, imageBuffer: pb, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sb)
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        if let sb, displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sb)
        }
    }
}

extension PipController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in self?.pipActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in self?.pipActive = false }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.pipActive = false }
    }
}

extension PipController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
}
