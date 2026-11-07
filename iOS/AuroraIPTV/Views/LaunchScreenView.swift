import SwiftUI
import AVKit

struct LaunchScreenView: View {
    @Binding var isActive: Bool
    @State private var player = AVPlayer()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear {
                    if let url = Bundle.main.url(forResource: "launcherScreen", withExtension: "mp4") {
                        player.replaceCurrentItem(with: AVPlayerItem(url: url))
                        player.play()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation {
                            isActive = false
                        }
                    }
                }
        }
    }
}
