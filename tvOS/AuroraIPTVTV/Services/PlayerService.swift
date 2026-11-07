import Foundation
import AVFoundation
import AVKit
import Combine

// VLCKit eklenirse (SPM: koombea/vlckit-spm veya CocoaPods: MobileVLCKit) otomatik devreye girer.
// Eklenmezse proje yine derlenir; sadece MKV/AVI/ham TS gibi biçimler oynatılamaz.
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif
#if canImport(VLCKit)
import VLCKit
#endif

enum PlaybackEngine {
    case avPlayer
    case vlc
}

/// IPTV adreslerini oynatıcı için uygun hale getirir.
enum StreamURLResolver {
    /// iOS'un yerleşik oynatıcısının açabildiği uzantılar
    static let nativeExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8", "mp3", "aac", "m4a", "wav"]
    /// Bunlar canlı yayın değil, dosya (VOD) kabul edilir
    static let fileExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg"]

    /// `/live/user/pass/123.ts` veya `/user/pass/123` biçimindeki Xtream canlı adresini `.m3u8` (HLS) adresine çevirir.
    static func hlsVariant(of url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parts = comps.path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return nil }

        let ext = (last as NSString).pathExtension.lowercased()
        let stem = (last as NSString).deletingPathExtension
        guard !stem.isEmpty, stem.allSatisfy({ $0.isNumber }), ext.isEmpty || ext == "ts" else { return nil }

        if parts.first == "movie" || parts.first == "series" { return nil }
        if parts.first == "live" {
            guard parts.count == 4 else { return nil }
        } else if parts.count == 3 {
            parts.insert("live", at: 0)
        } else {
            return nil
        }

        parts[parts.count - 1] = stem + ".m3u8"
        comps.path = "/" + parts.joined(separator: "/")
        return comps.url
    }

    /// `/live/user/pass/123.m3u8` adresini ham MPEG-TS (`.ts`) adresine çevirir.
    /// UHD/HEVC gibi bazı kanallar için sağlayıcı HLS üretmez; yalnızca `.ts` verir (VLC ile oynatılır).
    static func tsVariant(of url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parts = comps.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts.first == "live", let last = parts.last else { return nil }
        let ext = (last as NSString).pathExtension.lowercased()
        let stem = (last as NSString).deletingPathExtension
        guard ext == "m3u8", !stem.isEmpty, stem.allSatisfy({ $0.isNumber }) else { return nil }
        parts[parts.count - 1] = stem + ".ts"
        comps.path = "/" + parts.joined(separator: "/")
        return comps.url
    }
}

final class PlayerService: ObservableObject {

    static let shared = PlayerService()

    static var vlcAvailable: Bool {
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        return true
        #else
        return false
        #endif
    }

    let player = AVPlayer()

    @Published var engine: PlaybackEngine = .avPlayer
    @Published var isPlaying = false
    @Published var playbackMessage = "Bağlantı kuruluyor…"
    @Published var playbackError: String?

    private struct Candidate {
        let url: URL
        let engine: PlaybackEngine
        let label: String
    }

    private var candidates: [Candidate] = []
    private var candidateIndex = -1
    private var generation = 0
    private var currentURL: URL?
    private var preferVLC = false
    private var failures: [String] = []
    private var isLive = false
    private var watchdog: DispatchWorkItem?

    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []

    #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
    let vlcPlayer = VLCMediaPlayer()
    private let vlcDelegate = VLCStateDelegate()
    private var vlcPendingMedia: VLCMedia?
    private var vlcSurfaceAttached = false
    #endif

    private init() {
        observePlayer()
        setupAudioSession()
        print("[AuroraIPTV] VLC kullanılabilir mi: \(Self.vlcAvailable)")
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        vlcDelegate.onState = { [weak self] state in self?.handleVLCState(state) }
        vlcPlayer.delegate = vlcDelegate
        #endif
    }

    private func setupAudioSession() {
        #if os(iOS) || os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AuroraIPTV] Audio error: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Genel API

    /// preferVLC: UHD/4K/HEVC gibi kanallarda önce VLC (ham TS) denenir.
    func play(url: URL, isLive: Bool = false, preferVLC: Bool = false) {
        DispatchQueue.main.async {
            self.startPlayback(url: url, isLive: isLive, preferVLC: preferVLC)
        }
    }

    func stop() {
        generation += 1
        cancelWatchdog()
        teardownCurrent()
        isPlaying = false
        playbackError = nil
        playbackMessage = "Durduruldu"
        currentURL = nil
        candidates = []
        candidateIndex = -1
    }

    func togglePause() {
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        if engine == .vlc {
            if vlcPlayer.isPlaying { vlcPlayer.pause() } else { vlcPlayer.play() }
        }
        #endif
    }

    func seek(by seconds: Int) {
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        if engine == .vlc {
            if seconds >= 0 { vlcPlayer.jumpForward(Int32(seconds)) } else { vlcPlayer.jumpBackward(Int32(-seconds)) }
        }
        #endif
    }

    // MARK: - Akış

    private func startPlayback(url: URL, isLive: Bool, preferVLC: Bool) {
        generation += 1
        cancelWatchdog()
        teardownCurrent()

        playbackError = nil
        playbackMessage = "Bağlantı kuruluyor…"
        isPlaying = false
        currentURL = url
        failures = []
        self.preferVLC = preferVLC

        let ext = url.pathExtension.lowercased()
        self.isLive = isLive && !StreamURLResolver.fileExtensions.contains(ext)
        candidates = buildCandidates(for: url)
        candidateIndex = -1

        print("[AuroraIPTV] URL: \(url.absoluteString)")
        print("[AuroraIPTV] Denenecek yöntemler: \(candidates.map { "\($0.label): \($0.url.absoluteString)" })")
        tryNextCandidate()
    }

    private func buildCandidates(for url: URL) -> [Candidate] {
        let ext = url.pathExtension.lowercased()
        var list: [Candidate] = []

        if isLive {
            let hls: URL? = (ext == "m3u8") ? url : StreamURLResolver.hlsVariant(of: url)
            let ts: URL? = StreamURLResolver.tsVariant(of: url)

            if let hls = hls {
                if preferVLC && Self.vlcAvailable {
                    // UHD/4K/HEVC: önce ham TS ile VLC, olmazsa HLS
                    list.append(Candidate(url: ts ?? url, engine: .vlc, label: "VLC (TS)"))
                    list.append(Candidate(url: hls, engine: .avPlayer, label: "HLS"))
                } else {
                    list.append(Candidate(url: hls, engine: .avPlayer, label: "HLS"))
                    if Self.vlcAvailable {
                        // HLS açılmazsa ham TS (sağlayıcı bazı kanallar için HLS üretmez)
                        list.append(Candidate(url: ts ?? url, engine: .vlc, label: ts != nil ? "VLC (TS)" : "VLC"))
                        if ts != nil { list.append(Candidate(url: hls, engine: .vlc, label: "VLC (HLS)")) }
                    }
                }
            } else if Self.vlcAvailable {
                list.append(Candidate(url: url, engine: .vlc, label: "VLC"))
                list.append(Candidate(url: url, engine: .avPlayer, label: "AVPlayer"))
            } else {
                list.append(Candidate(url: url, engine: .avPlayer, label: "AVPlayer"))
            }
        } else {
            if StreamURLResolver.nativeExtensions.contains(ext) || ext.isEmpty {
                list.append(Candidate(url: url, engine: .avPlayer, label: "AVPlayer"))
                if Self.vlcAvailable { list.append(Candidate(url: url, engine: .vlc, label: "VLC")) }
            } else if Self.vlcAvailable {
                list.append(Candidate(url: url, engine: .vlc, label: "VLC"))
            } else {
                // VLC yok: yine de deneriz, başarısız olursa açıklayıcı hata gösteririz.
                list.append(Candidate(url: url, engine: .avPlayer, label: "AVPlayer"))
            }
        }
        return list
    }

    private func tryNextCandidate() {
        candidateIndex += 1
        guard candidateIndex < candidates.count else { return }
        generation += 1
        let gen = generation
        let candidate = candidates[candidateIndex]

        cancelWatchdog()
        teardownCurrent()
        playbackMessage = "Bağlantı kuruluyor… (\(candidate.label))"
        print("[AuroraIPTV] DENEME \(candidateIndex + 1)/\(candidates.count): \(candidate.label) \(candidate.url.absoluteString)")

        switch candidate.engine {
        case .avPlayer: startAV(candidate, generation: gen)
        case .vlc: startVLC(candidate)
        }

        // Hata vermeden sonsuza kadar siyah ekranda kalmayı önler
        let timeout: TimeInterval = candidate.engine == .vlc ? 25 : (isLive ? 20 : 30)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == gen, !self.isPlaying else { return }
            self.handleFailure("Yayın \(Int(timeout)) saniyede başlamadı (zaman aşımı).", generation: gen)
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func handleFailure(_ description: String, generation gen: Int) {
        guard gen == generation else { return }
        print("[AuroraIPTV] BAŞARISIZ: \(description)")
        cancelWatchdog()
        if candidateIndex >= 0, candidateIndex < candidates.count {
            failures.append("\(candidates[candidateIndex].label): \(description)")
        }
        if candidateIndex + 1 < candidates.count {
            tryNextCandidate()
        } else {
            teardownCurrent()
            isPlaying = false
            var message = friendlyError(description)
            if failures.count > 1 {
                message += "\n\nDenenen yöntemler:\n" + failures.map { "• " + $0 }.joined(separator: "\n")
            }
            playbackError = message
            playbackMessage = "Hata"
        }
    }

    private func friendlyError(_ description: String) -> String {
        let ext = currentURL?.pathExtension.lowercased() ?? ""
        if !Self.vlcAvailable {
            if !isLive, !ext.isEmpty, !StreamURLResolver.nativeExtensions.contains(ext) {
                return "Bu dosya biçimi (.\(ext)) iOS'un yerleşik oynatıcısıyla açılamıyor. Projeye VLCKit paketini ekleyin (README'ye bakın).\n\n\(description)"
            }
            if isLive {
                return "Canlı yayın HLS (.m3u8) olarak açılamadı. Sağlayıcınız m3u8 çıkışını desteklemiyor olabilir; VLCKit eklenirse .ts yayınlar da oynar.\n\n\(description)"
            }
        }
        return description
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func teardownCurrent() {
        itemStatusObservation = nil
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        vlcPendingMedia = nil
        if vlcPlayer.isPlaying || vlcPlayer.media != nil { vlcPlayer.stop() }
        #endif
    }

    // MARK: - AVPlayer

    private func observePlayer() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self, self.engine == .avPlayer else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.cancelWatchdog()
                    self.playbackMessage = "Yayın oynatılıyor"
                    self.playbackError = nil
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    if self.playbackError == nil { self.playbackMessage = "Video bekleniyor / yükleniyor…" }
                case .paused:
                    self.isPlaying = false
                @unknown default:
                    break
                }
            }
        }
    }

    private func startAV(_ candidate: Candidate, generation gen: Int) {
        engine = .avPlayer

        let headers: [String: String] = [
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
            "Accept": "*/*"
        ]
        let asset = AVURLAsset(url: candidate.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        if !isLive { item.preferredForwardBufferDuration = 20 }

        player.replaceCurrentItem(with: item)
        observeItem(item, generation: gen)
        player.play()
    }

    private func observeItem(_ item: AVPlayerItem, generation gen: Int) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == gen else { return }
                switch item.status {
                case .readyToPlay:
                    self.playbackMessage = "Video hazır"
                    self.player.play()
                    print("[AuroraIPTV] ITEM READY")
                case .failed:
                    let error = item.error as NSError?
                    let message = error?.localizedDescription ?? "Video açılamadı"
                    print("========== AURORA VIDEO ERROR ==========")
                    print("Desc: \(message)")
                    print("Domain: \(error?.domain ?? "-") Code: \(error?.code ?? -1)")
                    if let userInfo = error?.userInfo { print("UserInfo: \(userInfo)") }
                    print("========================================")
                    self.printErrorLog(item)
                    self.handleFailure(message, generation: gen)
                case .unknown:
                    self.playbackMessage = "Video bilgisi alınıyor…"
                @unknown default:
                    break
                }
            }
        }

        let failedToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            guard let self = self else { return }
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.printErrorLog(item)
            self.handleFailure(err?.localizedDescription ?? "Oynatma hatası", generation: gen)
        }

        let stalledToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            guard let self = self, self.playbackError == nil else { return }
            self.playbackMessage = "Yayın takıldı; veri bekleniyor…"
        }

        let errLogToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
            self?.printErrorLog(item)
        }

        notificationTokens = [failedToken, stalledToken, errLogToken]
    }

    private func printErrorLog(_ item: AVPlayerItem) {
        guard let events = item.errorLog()?.events, !events.isEmpty else { return }
        for e in events {
            print("[AuroraIPTV][ERRLOG] domain:\(e.errorDomain) code:\(e.errorStatusCode) comment:\(e.errorComment ?? "-") uri:\(e.uri ?? "-")")
        }
    }

    // MARK: - VLC (isteğe bağlı)

    private func startVLC(_ candidate: Candidate) {
        engine = .vlc
        #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
        let media = VLCMedia(url: candidate.url)
        media.addOption(":network-caching=1500")
        media.addOption(":http-user-agent=VLC/3.0.18 LibVLC/3.0.18")
        vlcPendingMedia = media
        if vlcSurfaceAttached { startPendingVLC() }   // aksi halde yüzey hazır olunca başlar
        #else
        handleFailure("VLC bu projede yok.", generation: generation)
        #endif
    }

    #if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
    /// VLCSurfaceView oluşturulduğunda çağrılır
    func vlcSurfaceDidAttach() {
        DispatchQueue.main.async {
            self.vlcSurfaceAttached = true
            self.startPendingVLC()
        }
    }

    func vlcSurfaceDidDetach() {
        DispatchQueue.main.async { self.vlcSurfaceAttached = false }
    }

    private func startPendingVLC() {
        guard let media = vlcPendingMedia else { return }
        vlcPendingMedia = nil
        vlcPlayer.media = media
        vlcPlayer.play()
    }

    private func handleVLCState(_ state: VLCMediaPlayerState) {
        DispatchQueue.main.async {
            guard self.engine == .vlc else { return }
            switch state {
            case .playing:
                self.isPlaying = true
                self.cancelWatchdog()
                self.playbackMessage = "Yayın oynatılıyor"
                self.playbackError = nil
            case .buffering, .opening:
                if !self.isPlaying { self.playbackMessage = "Tamponlanıyor…" }
            case .error:
                self.handleFailure("VLC bu yayını oynatamadı.", generation: self.generation)
            case .paused:
                self.isPlaying = false
            default:
                break
            }
        }
    }
    #endif
}

#if canImport(MobileVLCKit) || canImport(VLCKitSPM) || canImport(VLCKit)
final class VLCStateDelegate: NSObject, VLCMediaPlayerDelegate {
    var onState: ((VLCMediaPlayerState) -> Void)?

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        onState?(player.state)
    }
}
#endif
