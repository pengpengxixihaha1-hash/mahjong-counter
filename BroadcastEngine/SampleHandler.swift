import Foundation
import ReplayKit
import UserNotifications

/// 广播上传扩展入口：系统把屏幕帧送进来，交给识别引擎；
/// 并通过 Darwin 通知接收主 App 下发的牌型配置 / 开场指令。
final class SampleHandler: RPBroadcastSampleHandler {

    private var lastDarwinName = ""
    private var lastDarwinAt = TimeInterval(0)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SampleHandler.installDarwinObserver()
        RecognitionEngine.shared.start()
        // 握手：主 App 若在前台会回发牌型配置
        postDarwin("jp.hello")
        notifyOnce(title: "五十K记牌器", body: "识别已开始：回到游戏正常出牌，每手出牌会弹通知提示")
    }

    override func broadcastFinished() {
        notifyOnce(title: "五十K记牌器", body: "识别已停止。下一局请在 App 里点「开始识别」")
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
            handleDarwin(name.rawValue as String)
        }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        // 监听全部 Darwin 通知，回调里过滤 "jp." 前缀（Darwin 无通配订阅）
        CFNotificationCenterAddObserver(center, nil, cb, nil, nil, .deliverImmediately)
        // 固定名兜底（若 name=NULL 全订阅在该系统上不生效）
        CFNotificationCenterAddObserver(center, nil, cb, "jp.reset" as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, nil, cb, "jp.hello" as CFString, nil, .deliverImmediately)
    }

    static func handleDarwin(_ raw: String) {
        let engine = RecognitionEngine.shared
        if raw.hasPrefix("jp.d.") {
            engine.applyDeck(hex: String(raw.dropFirst(5)))
        } else if raw == "jp.reset" || raw.hasPrefix("jp.p") {
            if raw.hasPrefix("jp.p"), let idx = Int(raw.dropFirst(4)),
               idx >= 0, idx < DeckPreset.all.count {
                engine.applyDeck(hex: DeckPreset.all[idx].hex)
            }
            engine.resetGame()
        }
        // "jp.hello" 由 App 发出，扩展无需处理（扩展是 hello 的发送方）
    }

    private func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }

    private func notifyOnce(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: "jp-sys-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
