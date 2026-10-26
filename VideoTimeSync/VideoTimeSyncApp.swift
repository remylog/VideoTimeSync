import SwiftUI

@main
struct VideoTimeSyncApp: App {
    var body: some Scene {
        WindowGroup("動画日時同期ツール") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
