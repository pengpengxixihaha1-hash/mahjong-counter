import Foundation
import SwiftUI
import ReplayKit
import UserNotifications

/// Darwin 回调（文件级全局函数：C 回调闭包内不可捕获任何上下文）
private func jpHelloArrived() {
    DispatchQueue.main.async {
        NotificationBridge.shared.replyHello()
    }
}

/// App ↔ 广播扩展 桥：
///  - 接收扩展发来的本地通知（userInfo 内含全量快照）→ 回调刷新界面
///  - 监听扩展握手（Darwin "jp.hello"）→ 回发当前牌型配置
///  - 发送牌型 / 开场指令（Darwin 通知，免签名跨进程通道）
final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationBridge()

    /// 收到扩展快照（主线程回调）
    var onSnapshot: ((CounterSnapshot) -> Void)?

    /// 当前牌型 hex（由 CounterStore 更新，握手时回发给扩展）
    var currentDeckHex: String = DeckPreset.default.hex

    func activate() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
        installDarwinObserver()
    }

    /// 回到前台时调用：拉取错过的快照通知（App 挂起期间扩展发的）
    func drainDelivered() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifs in
            var best: CounterSnapshot?
            var ids: [String] = []
            for n in notifs {
                ids.append(n.request.identifier)
                if let data = n.request.content.userInfo["snap"] as? Data,
                   let snap = try? JSONDecoder().decode(CounterSnapshot.self, from: data) {
                    if best == nil || snap.playSeq >= (best?.playSeq ?? 0) { best = snap }
                }
            }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            if let best {
                DispatchQueue.main.async { self.onSnapshot?(best) }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if let snap = decode(notification) {
            onSnapshot?(snap)
        }
        return [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let snap = decode(response.notification) {
            onSnapshot?(snap)
        }
    }

    private func decode(_ n: UNNotification) -> CounterSnapshot? {
        guard let data = n.request.content.userInfo["snap"] as? Data else { return nil }
        return try? JSONDecoder().decode(CounterSnapshot.self, from: data)
    }

    // MARK: - Darwin 通知

    private func installDarwinObserver() {
        let cb: CFNotificationCallback = { _, _, name, _, _ in
            guard let name, (name.rawValue as String) == "jp.hello" else { return }
            jpHelloArrived()
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil, cb,
            "jp.hello" as CFString, nil, .deliverImmediately)
    }

    /// 扩展广播启动握手到达 → 回发当前牌型（主线程）
    func replyHello() {
        post("jp.d." + currentDeckHex)
    }

    /// 下发牌型：名字 "jp.d.<hex>"（扩展全订阅后过滤前缀）
    func sendDeck(_ hex: String) {
        currentDeckHex = hex
        post("jp.d." + hex)
    }

    /// 开场 / 重置
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
