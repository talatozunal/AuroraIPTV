import SwiftUI

@main
struct AuroraIPTVTVApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(appViewModel)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
