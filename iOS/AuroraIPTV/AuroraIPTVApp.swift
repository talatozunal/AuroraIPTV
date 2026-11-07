import SwiftUI

@main
struct AuroraIPTVApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var library = LibraryStore()
    @State private var showLaunchScreen = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchScreenView(isActive: $showLaunchScreen)
                } else {
                    RootView()
                        .environmentObject(appViewModel)
                        .environmentObject(library)
                        .preferredColorScheme(.dark)
                }
            }
        }
    }
}
