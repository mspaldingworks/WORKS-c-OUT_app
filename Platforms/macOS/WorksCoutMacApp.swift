import SwiftUI
import WorksCoutCore

@main
struct WorksCoutMacApp: App {
    var body: some Scene {
        WindowGroup {
            WorksCoutMacRootView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands { SidebarCommands() }
    }
}
