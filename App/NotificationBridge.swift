import Foundation
import SwiftUI
import ReplayKit
import UserNotifications

/// Darwin 回调（文件级全局函数：C 回调闭包内不可捕获任何上下文）
private func jpAppDarwinReceived(_ raw: String) {
    DispatchQueue.main.async {
        NotificationBridge.shared.handle(raw)
    }
}

/// App ↔ 广播扩展 桥：
///  - 扩展通过 Darwin 通知名回传事件（免费签名无 App Groups 的唯一可靠跨进程通道）：
///      jp.h.<hex14>                          手牌识别结果
///      jp.o.<seatIdx><hex14>                 一手出牌（seat: 0对 1上 2我 3下）
///      jp.f                                  扩展自动判局结束
///      jp.g.<b2><h2><d2><s2><w2><x2>         诊断摘要
///  - 监听扩展握手（Darwin "jp.hello"）→ 回发当前牌型配置
///  - 发送牌型 / 开场指令（Darwin 通知）
final class NotificationBridge: NSObject {

    static let shared = NotificationBridge()

    /// 事件回调（主线程）
    var onHandEvent: ((_ counts: [Int]) -> Void)?
    var onPlayEvent: ((_ seatIdx: Int, _ counts: [Int]) -> Void)?
    var onEndGame: (() -> Void)?
    var onDiag: ((_ text: String) -> Void)?

    /// 当前牌型 hex（由 CounterStore 更新，握手时回发给扩展）
    var currentDeckHex: String = DeckPreset.default.hex

    func activate() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
        installDarwinObserver()
    }

    // MARK: - 事件分发

    func handle(_ raw: String) {
        if raw.hasPrefix("jp.h.") {
            if let counts = [Int].fromJpHex(String(raw.dropFirst(5))) {
                onHandEvent?(counts)
            }
        } else if raw.hasPrefix("jp.o.") {
            let body = raw.dropFirst(5)
            guard let first = body.first, let seatIdx = first.wholeNumberValue,
                  seatIdx >= 0, seatIdx < Seat.all.count,
                  let counts = [Int].fromJpHex(String(body.dropFirst())) else { return }
            onPlayEvent?(seatIdx, counts)
        } else if raw == "jp.f" {
            onEndGame?()
        } else if raw == "jp.hello" {
            replyHello()   // 扩展广播启动 → 回发当前牌型
        } else if raw.hasPrefix("jp.g.") {
            let body = String(raw.dropFirst(5))
            guard body.count == 12 else { return }
            let vals: [String.SubSequence] = [body[body.index(body.startIndex, offsetBy: 0)..<body.index(body.startIndex, offsetBy: 2)],
                                              body[body.index(body.startIndex, offsetBy: 2)..<body.index(body.startIndex, offsetBy: 4)],
                                              body[body.index(body.startIndex, offsetBy: 4)..<body.index(body.startIndex, offsetBy: 6)],
                                              body[body.index(body.startIndex, offsetBy: 6)..<body.index(body.startIndex, offsetBy: 8)],
                                              body[body.index(body.startIndex, offsetBy: 8)..<body.index(body.startIndex, offsetBy: 10)],
                                              body[body.index(body.startIndex, offsetBy: 10)..<body.index(body.startIndex, offsetBy: 12)]]
            let nums = vals.compactMap { Int($0) }
            guard nums.count == 6 else { return }
            let text = String(format: "块%02d 手%02d｜对%02d 上%02d 我%02d 下%02d", nums[0], nums[1], nums[2], nums[3], nums[4], nums[5])
            onDiag?(text)
        }
    }

    // MARK: - Darwin 通知

    private func installDarwinObserver() {
        let cb: CFNotificationCallback = { _, _, name, _, _ in
            guard let name else { return }
            let raw = name.rawValue as String
            guard raw.hasPrefix("jp.") else { return }
            jpAppDarwinReceived(raw)
        }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, cb, nil, nil, .deliverImmediately)
        // 固定名兜底（若全订阅在该系统上不生效）
        for n in ["jp.hello", "jp.reset"] {
            CFNotificationCenterAddObserver(center, nil, cb, n as CFString, nil, .deliverImmediately)
        }
    }

    /// 扩展广播启动握手到达 → 回发当前牌型（主线程）
    func replyHello() {
        post("jp.d." + currentDeckHex)
    }

    /// 下发牌型：名字 "jp.d.<hex>"
    func sendDeck(_ hex: String) {
        currentDeckHex = hex
        post("jp.d." + hex)
    }

    /// 开场 / 重置（发给扩展）
    func sendReset() {
        post("jp.reset")
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// 「开始识别」按钮：调起系统屏幕广播选择器（选择本 App 即开始识别）
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView()
        v.showsMicrophoneButton = false
        v.preferredExtension = "com.mahjongcounter.app.broadcast"
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
