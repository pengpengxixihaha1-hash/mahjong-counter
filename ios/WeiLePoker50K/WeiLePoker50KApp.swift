import SwiftUI

@main
struct WeiLePoker50KApp: App {
    @StateObject private var vm = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(vm: vm)
        }
    }
}
