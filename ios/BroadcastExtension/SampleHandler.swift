import CoreMedia
import CoreVideo
import ReplayKit
import UniformTypeIdentifiers
import UIKit

// 录屏广播入口：系统每帧回调 process()。
// 阶段 2（识别版）：~2fps 节奏 + 静态帧跳过 → ScreenRecognizer 识别 →
// PokerLedger 出账 → IPC 写快照给主 App 浮窗显示。
// 样本采集模式仍可同时开启（存帧供发回电脑校准）。
//
// 内存红线：Broadcast Extension 约 50MB，逐帧 autoreleasepool，JPEG 直写磁盘，
// 绝不缓存整帧序列；识别中间平面在 autoreleasepool 内即建即用。
final class SampleHandler: RPBroadcastSampleHandler {
    private var frameIndex = 0
    private var lastPTS = TimeInterval(0)
    private var savedCount = 0
    private var frameInterval: TimeInterval = 0.45   // ~2fps
    private let softwareContext = CIContext(options: [.useSoftwareRenderer: true])

    private let recognizer = ScreenRecognizer()
    private var ledger = PokerLedger()
    private var lastFingerprint: [UInt8]?
    private var lastAnalyzedPTS = TimeInterval(-10)
    // 最近一次识别结果（周期状态推送时保留主条/分账，避免被空快照覆盖）
    private var lastMain: [String: Int] = [:]
    private var lastSeats: [IPC.Snapshot.Seat] = []
    private var lastNewGame = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        IPC.ensureSamplesDir()
        push(status: recognizer.templatesLoaded ? "广播已开始，识别就绪" : "广播已开始（模板缺失）")
    }

    override func broadcastPaused() {
        push(status: "已暂停")
    }

    override func broadcastResumed() {
        push(status: "已恢复")
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
            analyzeIfNeeded(pixelBuffer, pts: pts)
        }
    }

    // MARK: - 识别 + 出账

    private func analyzeIfNeeded(_ pixelBuffer: CVPixelBuffer, pts: TimeInterval) {
        guard recognizer.templatesLoaded else { return }
        // 静态帧跳过：画面指纹 L1 差小于阈值且未到 2s 强制刷新则直接复用上次结果
        let fp = recognizer.fingerprint(pixelBuffer)
        var changed = true
        if let fp, let last = lastFingerprint, fp.count == last.count {
            var d = 0
            for i in 0..<fp.count {
                d += abs(Int(fp[i]) - Int(last[i]))
            }
            changed = d > 800
        } else if fp == nil {
            return   // 竖屏帧：不识别也不刷新指纹
        }
        guard changed || pts - lastAnalyzedPTS >= 2.0 else { return }
        lastFingerprint = fp
        lastAnalyzedPTS = pts

        guard let dets = recognizer.process(pixelBuffer) else { return }
        let result = ledger.processFrame(handDets: dets.hand, centerDets: dets.center)
        let seen = ledger.seen(hand: result.hand)
        lastMain = ledger.mainBar(seen: seen)
        lastSeats = ledger.seatDisp.map {
            IPC.Snapshot.Seat(name: $0.name, left: $0.left, cards: $0.cards)
        }
        lastNewGame = result.newGame
        write(status: result.newGame ? "新一局，已重置" : "实时识别中")
    }

    // MARK: - JPEG 采样（校准用）

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
        lastMain = [:]
        lastSeats = []
        lastNewGame = false
        write(status: status)
    }

    private func write(status: String) {
        IPC.write(IPC.Snapshot(
            status: status,
            collecting: IPC.collecting,
            sampleCount: savedCount,
            newGame: lastNewGame,
            main: lastMain,
            seats: lastSeats))
    }
}
