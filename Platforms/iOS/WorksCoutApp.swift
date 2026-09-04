import SwiftUI
import WorksCoutCore

/// WORKS(c)OUT — the job search app, split out of Family Appily so the two
/// share no code, no containers, no signing identity and no data.
@main
struct WorksCoutApp: App {
    var body: some Scene {
        WindowGroup {
            WorksCoutRootTabView()
        }
    }
}
