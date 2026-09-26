import CoreMedia
import ReplayKit
import UniformTypeIdentifiers
import UIKit

// 录屏广播入口：系统每帧回调 process()。
// 阶段 1（样本采集版）：降频 ~2fps，把对局帧存进 App Group 容器，供导出制作手机版模板。
// 阶段 3（识别版）：ScreenRecognizer 接入真机模板后，识别结果经 PokerLedger 出账，
// 通过 IPC 写快照给主 App 浮窗显示。
//
// 内存红线：Broadcast Extension 约 50MB，逐帧 autoreleasepool，JPEG 直写磁盘，
// 绝不缓存整帧序列。
final class SampleHandler: RPBroadcastSampleHandler {
    private var frameIndex = 0
    private var lastPTS = TimeInterval(0)
    private var savedCount = 0
    private var frameInterval: TimeInterval = 0.45   // ~2fps
    private let softwareContext = CIContext(options: [.useSoftwareRenderer: true])

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        IPC.ensureSamplesDir()
        push(status: "广播已开始")
    }

    override func broadcastPaused() {
        push(status: "已暂停")
    }

    override func broadcastResumed() {
        push(status: "广播已恢复")
    }

    override func broadcastFinished() {
        push(status: "广播结束，共采集 \(savedCount) 帧")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard pts.isFinite, pts - lastPTS >= frameInterval else { return }
        lastPTS = pts

        autoreleasepool {
            frameIndex += 1
            let collecting = IPC.collecting
            if collecting, savedCount < IPC.maxSamples,
               let dir = IPC.samplesDir,
               let jpg = encodeJPEG(pixelBuffer) {
                let name = String(format: "frame_%04d.jpg", frameIndex)
                try? jpg.write(to: dir.appendingPathComponent(name), options: .atomic)
                savedCount += 1
            }
            if frameIndex % 10 == 0 {
                push(status: collecting
                     ? "样本采集中 \(savedCount)/\(IPC.maxSamples) 帧"
                     : "采集已关闭")
            }
        }
    }

    /// 屏幕帧 → JPEG（软件渲染，避免扩展内 GPU 上下文开销与内存峰值）
    private func encodeJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = softwareContext.createCGImage(ci, from: ci.extent) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func push(status: String) {
        IPC.write(IPC.Snapshot(
            status: status,
            collecting: IPC.collecting,
            sampleCount: savedCount,
            newGame: false,
            main: [:],
            seats: []))
    }
}
