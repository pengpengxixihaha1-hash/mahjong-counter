import Foundation
import ReplayKit

/// Darwin 通知处理（文件级全局函数：C 回调闭包内不可捕获任何上下文）
/// 扩展只接收 App→扩展方向：jp.d.<hex>（牌型）/ jp.reset（开场）/ jp.hello（握手）
/// 扩展自己发出的 jp.h./jp.o./jp.g./jp.f. 不在此处理（忽略）
private func jpDarwinReceived(_ raw: String) {
    let engine = RecognitionEngine.shared
    if raw.hasPrefix("jp.d.") {
        engine.applyDeck(hex: String(raw.dropFirst(5)))
    } else if raw == "jp.reset" {
        engine.resetGame()
    }
    // "jp.hello" 由 App 发出，扩展无需处理（扩展是 hello 的发送方）
}

/// 广播上传扩展入口：系统把屏幕帧送进来，交给识别引擎；
/// 并通过 Darwin 通知接收主 App 下发的牌型配置 / 开场指令。
final class SampleHandler: RPBroadcastSampleHandler {

    private var lastDarwinName = ""
    private var lastDarwinAt = TimeInterval(0)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SampleHandler.installDarwinObserver()
        RecognitionEngine.shared.start()
        // 握手：主 App 若在运行会回发牌型配置
        postDarwin("jp.hello")
    }

    override func broadcastFinished() {
        RecognitionEngine.shared.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        RecognitionEngine.shared.feed(pixelBuffer: pb)
    }

    // MARK: - Darwin 通知（App ↔ 扩展 免签名握手通道）

    private static var observerInstalled = false

    static func installDarwinObserver() {
        guard !observerInstalled else { return }
        observerInstalled = true
        let cb: CFNotificationCallback = { _, _, name, _, _ in
            guard let name else { return }
            jpDarwinReceived(name.rawValue as String)
        }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        // 监听全部 Darwin 通知，回调里过滤 "jp." 前缀（Darwin 无通配订阅）
        CFNotificationCenterAddObserver(center, nil, cb, nil, nil, .deliverImmediately)
        // 固定名兜底（若 name=NULL 全订阅在该系统上不生效）
        CFNotificationCenterAddObserver(center, nil, cb, "jp.reset" as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, nil, cb, "jp.hello" as CFString, nil, .deliverImmediately)
    }

    private func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}
