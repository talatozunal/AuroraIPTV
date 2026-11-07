import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let url: URL
    var isLive: Bool = false

    @ObservedObject private var playerService = PlayerService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if playerService.engine == .vlc {
                VLCContainerView()
                    .ignoresSafeArea()
            } else {
                PlayerVCRepresentable(player: playerService.player)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                playerService.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.trailing, 16)
            .padding(.top, 50)
            .zIndex(1000)
        }
        .overlay(alignment: .bottom) {
            if let error = playerService.playbackError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)

                    Text("Video oynatılamadı")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Tekrar Dene") {
                        playerService.play(url: url, isLive: isLive)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                    if !PlayerService.vlcAvailable, let vlcURL = URL(string: "vlc://" + url.absoluteString) {
                        Button("VLC uygulamasında aç") {
                            openURL(vlcURL)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9))
                .padding(.bottom, 40)
            } else if !playerService.isPlaying {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text(playerService.playbackMessage)
                        .font(.callout)
                        .foregroundColor(.white)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9))
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .bottom) {
            // VLC motorunda yerleşik kontrol olmadığı için basit kontroller
            if playerService.engine == .vlc, playerService.isPlaying, playerService.playbackError == nil {
                HStack(spacing: 36) {
                    if !isLive {
                        controlButton("gobackward.10") { playerService.seek(by: -10) }
                    }
                    controlButton("playpause.fill") { playerService.togglePause() }
                    if !isLive {
                        controlButton("goforward.10") { playerService.seek(by: 10) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            playerService.play(url: url, isLive: isLive)
        }
        .onDisappear {
            playerService.stop()
        }
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
