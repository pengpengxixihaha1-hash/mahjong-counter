import SwiftUI

@main
struct MahjongCounterApp: App {
    @StateObject private var store = CounterStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
