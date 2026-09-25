import SwiftUI

@main
struct MahjongCounterApp: App {
    @StateObject private var store = CounterStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    let b = NotificationBridge.shared
                    b.onHandEvent = { counts in store.applyHandEvent(counts) }
                    b.onPlayEvent = { seatIdx, counts in store.applyPlayEvent(seatIdx: seatIdx, counts: counts) }
                    b.onEndGame = { store.applyEndGame() }
                    b.onDiag = { text in store.setDiag(text) }
                    b.activate()
                }
        }
    }
}
