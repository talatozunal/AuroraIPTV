import SwiftUI
import AVKit
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif
#if canImport(VLCKit)
import VLCKit
#endif

/// Tam ekran oynatıcı. Yerleşik (AVPlayer) motoru kumandanın standart oynatma arayüzüyle,
/// VLC motoru (MKV/AVI/ham TS) basit kumanda komutlarıyla çalışır:
/// ▶︎⏸ duraklat/oynat, ◀︎ ▶︎ 10 sn geri/ileri, Menü: kapat.
struct TVVideoPlayerView: View {
    let url: URL
    var isLive: Bool = false
    var preferVLC: Bool = false

    @ObservedObject private var playerService = PlayerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = playerService.playbackError {
                errorView(error)
            } else {
                playerSurface

                if !playerService.isPlaying {
                    loadingView
                }
            }
        }
        .onExitCommand {
            playerService.stop()
            dismiss()
        }
        .onAppear {
            playerService.play(url: url, isLive: isLive, preferVLC: preferVLC)
        }
        .onDisappear {
            playerService.stop()
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        if playerService.engine == .vlc {
            TVVLCContainerView()
                .ignoresSafeArea()
                .focusable()
                .onPlayPauseCommand {
                    playerService.togglePause()
                }
                .onMoveCommand { direction in
                    guard !isLive else { return }
                    switch direction {
                    case .left: playerService.seek(by: -10)
                    case .right: playerService.seek(by: 10)
                    default: break
                    }
                }
        } else {
            TVPlayerControllerView(player: playerService.player)
                .ignoresSafeArea()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.6)
            Text(playerService.playbackMessage)
                .font(.title3)
                .foregroundColor(.white)
        }
        .padding(40)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 70))
                .foregroundColor(.yellow)

            Text("Video oynatılamadı")
                .font(.title2)
                .foregroundColor(.white)

            Text(error)
                .font(.callout)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)

            HStack(spacing: 40) {
                Button("Tekrar Dene") {
                    playerService.play(url: url, isLive: isLive, preferVLC: preferVLC)
                }
                Button("Kapat") {
                    playerService.stop()
                    dismiss()
                }
            }
        }
        .padding(60)
    }
}

// MARK: - Yerleşik oynatıcı (AVPlayerViewController)

struct TVPlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - VLC yüzeyi (VLCKit eklenmişse)

/// VLCKit eklenmişse VLC görüntüsünü gösterir, eklenmemişse siyah boş alan.
struct TVVLCContainerView: View {
    var body: some View {
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        TVVLCSurfaceView(player: PlayerService.shared.vlcPlayer)
        #else
        Color.black
        #endif
    }
}

#if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
struct TVVLCSurfaceView: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        PlayerService.shared.vlcSurfaceDidAttach()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if (player.drawable as? UIView) !== uiView {
            player.drawable = uiView
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        PlayerService.shared.vlcSurfaceDidDetach()
    }
}
#endif
