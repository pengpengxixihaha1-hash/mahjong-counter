import SwiftUI

@main
struct MahjongCounterApp: App {
    @StateObject private var store = CounterStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationBridge.shared.onSnapshot = { snap in
                        store.applyRemote(snap)
                    }
                    NotificationBridge.shared.activate()
                }
                .onChange(of: scenePhase) { phase in
                    // 从游戏切回时，拉取挂起期间错过的识别快照
                    if phase == .active {
                        NotificationBridge.shared.drainDelivered()
                    }
                }
        }
    }
}
