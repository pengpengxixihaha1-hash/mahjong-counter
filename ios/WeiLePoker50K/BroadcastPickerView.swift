import ReplayKit
import SwiftUI

// 系统录屏广播选择器：点击后由用户在系统弹窗里选择「五十K记牌器」开始广播。
struct BroadcastPickerView: UIViewRepresentable {
    var preferredExtension = "com.wl50k.poker50k.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView()
        v.showsMicrophoneButton = false
        v.preferredExtension = preferredExtension
        return v
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
