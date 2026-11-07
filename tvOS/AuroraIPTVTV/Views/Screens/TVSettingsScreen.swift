import SwiftUI

struct TVSettingsScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var showAddSheet = false
    @State private var newType: PlaylistSource.SourceType = .m3u
    @State private var newPlaylistName = ""
    @State private var newPlaylistURL = ""
    @State private var xtreamServer = ""
    @State private var xtreamUser = ""
    @State private var xtreamPass = ""

    @State private var showInfoSheet = false
    @State private var dialogSource: PlaylistSource?
    @State private var showSourceDialog = false

    var body: some View {
        NavigationStack {
            Form {
                playlistSection
                refreshSection
                contentSection
                infoSection
                errorSection
            }
            .sheet(isPresented: $showAddSheet) {
                addPlaylistSheet
            }
            .sheet(isPresented: $showInfoSheet) {
                infoSheet
            }
            .confirmationDialog(dialogSource?.name ?? "Playlist",
                                isPresented: $showSourceDialog,
                                titleVisibility: .visible) {
                if let source = dialogSource {
                    Button("Yenile") {
                        Task { await appViewModel.loadPlaylist(source: source) }
                    }
                    Button(source.enabled ? "Devre Dışı Bırak" : "Etkinleştir") {
                        appViewModel.setEnabled(!source.enabled, for: source.id)
                    }
                    Button("Kaldır", role: .destructive) {
                        if let index = appViewModel.playlistSources.firstIndex(where: { $0.id == source.id }) {
                            appViewModel.removePlaylist(at: IndexSet([index]))
                        }
                    }
                }
                Button("Vazgeç", role: .cancel) { }
            }
        }
    }

    // MARK: Bölümler

    /// M3U ve Xtream tek listede; tür her satırda rozetle görünür. Satıra basınca işlem menüsü açılır.
    private var playlistSection: some View {
        Section("Playlistler") {
            if appViewModel.playlistSources.isEmpty {
                Text("Henüz playlist eklenmemiş")
                    .foregroundColor(.secondary)
            } else {
                ForEach(appViewModel.playlistSources) { source in
                    Button {
                        dialogSource = source
                        showSourceDialog = true
                    } label: {
                        TVPlaylistRow(source: source)
                    }
                }
            }

            Button {
                showAddSheet = true
            } label: {
                Label("Playlist Ekle", systemImage: "plus.circle.fill")
            }
        }
    }

    private var refreshSection: some View {
        Section {
            Button {
                Task { await appViewModel.loadAllPlaylists() }
            } label: {
                HStack {
                    Spacer()
                    if appViewModel.isLoading && appViewModel.loadingSourceID == nil {
                        ProgressView()
                    } else {
                        Label("Tümünü Yenile", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Spacer()
                }
            }
            .disabled(appViewModel.isLoading || appViewModel.playlistSources.isEmpty)

            if appViewModel.isLoading {
                Button(role: .destructive) {
                    appViewModel.stopAllLoading()
                } label: {
                    HStack {
                        Spacer()
                        Label("Yüklemeyi Durdur", systemImage: "stop.circle.fill")
                        Spacer()
                    }
                }
            }
        }
    }

    /// Yetişkin içerik filtresi
    private var contentSection: some View {
        Section {
            Toggle(isOn: $appViewModel.hideAdult) {
                Label("Yetişkin içeriği gizle", systemImage: "eye.slash")
            }
        } footer: {
            Text("Kategori, kanal veya film adında 18+, adult, xxx gibi ifadeler geçen içerikleri listelerden, aramadan ve favorilerden gizler.")
        }
    }

    /// Bilgi metni ekrana sığmadığı için satır içinde açılmaz; seçince ayrı bir sayfada açılır.
    private var infoSection: some View {
        Section {
            Button {
                showInfoSheet = true
            } label: {
                HStack {
                    Label("Bilgi", systemImage: "info.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
        }
    }

    private var infoSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label("Bilgi", systemImage: "info.circle")
                    .font(.title2)
                    .foregroundColor(.white)

                // Metinler odaklanabilir: metin uzarsa kumanda ile aşağı kaydırılabilir.
                infoParagraph("Bu uygulama herhangi bir ücret talep etmemektedir. Geliştirme aşamasındadır.")
                infoParagraph("Uygulama içerisinde önceden tanımlı veya barındırılan herhangi bir kanal listesi bulunmamaktadır. Kullanıcılar kendi M3U veya Xtream Codes bilgilerini eklemek zorundadır.")
                infoParagraph("Sürüm 1.0.0   •   Yıl: 2026   •   Sorumlu: Talat Özünal", dimmed: true)
                infoParagraph("Hata ve bilgilendirmeler için iletişim: ozunaltalat@gmail.com", dimmed: true)

                Button("Kapat") {
                    showInfoSheet = false
                }
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 60)
        }
    }

    private func infoParagraph(_ text: String, dimmed: Bool = false) -> some View {
        Button {
        } label: {
            Text(text)
                .font(.callout)
                .foregroundColor(dimmed ? Color.white.opacity(0.75) : .white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .buttonStyle(AuroraPillButtonStyle(cornerRadius: 14))
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = appViewModel.errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
            }
        }
    }

    // MARK: Tek ekleme ekranı (M3U veya Xtream seçilir)

    private var canAdd: Bool {
        switch newType {
        case .m3u:
            return !newPlaylistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .xtream:
            return !xtreamServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !xtreamUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !xtreamPass.isEmpty
        }
    }

    private var addPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $newType) {
                        Text("M3U").tag(PlaylistSource.SourceType.m3u)
                        Text("Xtream Codes").tag(PlaylistSource.SourceType.xtream)
                    }
                    .pickerStyle(.segmented)
                }

                if newType == .m3u {
                    Section("M3U Bilgileri") {
                        TextField("İsim (opsiyonel)", text: $newPlaylistName)
                        TextField("M3U URL", text: $newPlaylistURL)
                    }
                } else {
                    Section("Xtream Codes Bilgileri") {
                        TextField("İsim (opsiyonel)", text: $newPlaylistName)
                        TextField("Sunucu (http://sunucu.com:8080)", text: $xtreamServer)
                        TextField("Kullanıcı Adı", text: $xtreamUser)
                        SecureField("Şifre", text: $xtreamPass)
                    }
                }

                Section {
                    Button {
                        addPlaylist()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Ekle", systemImage: "plus.circle.fill")
                            Spacer()
                        }
                    }
                    .disabled(!canAdd)

                    Button(role: .cancel) {
                        showAddSheet = false
                        resetForm()
                    } label: {
                        HStack {
                            Spacer()
                            Text("İptal")
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func addPlaylist() {
        switch newType {
        case .m3u:
            appViewModel.addM3UPlaylist(name: newPlaylistName, url: newPlaylistURL)
        case .xtream:
            appViewModel.addXtreamPlaylist(name: newPlaylistName, serverURL: xtreamServer, username: xtreamUser, password: xtreamPass)
        }
        showAddSheet = false
        resetForm()
        // Yalnızca yeni eklenen playlist yüklenir; diğerleri yeniden indirilmez.
        if let added = appViewModel.playlistSources.last {
            Task { await appViewModel.loadPlaylist(source: added) }
        }
    }

    private func resetForm() {
        newPlaylistName = ""
        newPlaylistURL = ""
        xtreamServer = ""
        xtreamUser = ""
        xtreamPass = ""
    }
}

struct TVPlaylistRow: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let source: PlaylistSource

    private var isXtream: Bool { source.type == .xtream }
    private var accent: Color { isXtream ? .orange : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(source.name.isEmpty ? (isXtream ? "İsimsiz Xtream" : "İsimsiz M3U") : source.name)
                    .font(.callout)
                Text(isXtream ? "Xtream" : "M3U")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.25))
                    .foregroundColor(accent)
                    .clipShape(Capsule())
                Spacer()
            }

            Text(isXtream ? "\(source.serverURL) • \(source.username)" : source.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if appViewModel.isLoading && appViewModel.loadingSourceID == source.id {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Yükleniyor…")
                        .font(.caption)
                        .foregroundColor(accent)
                }
            } else if !source.enabled {
                Text("Devre dışı (seçip \"Etkinleştir\" deyin)")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let status = appViewModel.sourceStatus[source.id] {
                Text(status.text)
                    .font(.caption)
                    .foregroundColor(status.isError ? .red : .green)
                    .lineLimit(4)
            } else {
                Text("Henüz yüklenmedi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
