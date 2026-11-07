// PlayerVCRepresentable.swift
// AuroraIPTV
//
// AVPlayerViewController (yerleşik oynatıcı) ve isteğe bağlı VLC yüzeyi.

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

struct PlayerVCRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

/// VLCKit eklenmişse VLC görüntüsünü gösterir, eklenmemişse siyah boş alan.
struct VLCContainerView: View {
    var body: some View {
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        VLCSurfaceView(player: PlayerService.shared.vlcPlayer)
        #else
        Color.black
        #endif
    }
}

#if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
struct VLCSurfaceView: UIViewRepresentable {
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
