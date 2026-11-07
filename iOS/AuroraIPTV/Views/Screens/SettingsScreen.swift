import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var showAddSheet = false
    @State private var infoExpanded = false
    @State private var newType: PlaylistSource.SourceType = .m3u
    @State private var newPlaylistName = ""
    @State private var newPlaylistURL = ""
    @State private var xtreamServer = ""
    @State private var xtreamUser = ""
    @State private var xtreamPass = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                settingsList
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
                    .foregroundColor(.white)
            }
            .sheet(isPresented: $showAddSheet) {
                addPlaylistSheet
            }
        }
        .navigationViewStyle(.stack)
    }

    private var settingsList: some View {
        List {
            playlistSection
            generalSection
            statsSection
            infoSection
            errorSection
        }
        .scrollContentBackground(.hidden)
    }

    /// M3U ve Xtream tek listede; tür her satırda rozetle görünür.
    private var playlistSection: some View {
        Section(header: Text("Playlistler").foregroundColor(.gray)) {
            if appViewModel.playlistSources.isEmpty {
                Text("Henüz playlist eklenmemiş")
                    .font(.footnote)
                    .foregroundColor(.gray)
            } else {
                ForEach(appViewModel.playlistSources) { source in
                    PlaylistRow(source: source)
                }
                .onDelete { indexSet in
                    appViewModel.removePlaylist(at: indexSet)
                }
            }
            Button(action: { showAddSheet = true }) {
                Label("Playlist Ekle", systemImage: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private var generalSection: some View {
        Section {
            Button(action: {
                Task { await appViewModel.loadAllPlaylists() }
            }) {
                HStack {
                    Spacer()
                    if appViewModel.isLoading && appViewModel.loadingSourceID == nil {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Label("Tümünü Yenile", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
            .disabled(appViewModel.isLoading || appViewModel.playlistSources.isEmpty)

            if appViewModel.isLoading {
                Button(action: {
                    appViewModel.stopAllLoading()
                }) {
                    HStack {
                        Spacer()
                        Label("Yüklemeyi Durdur", systemImage: "stop.circle.fill")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
        }
    }

    private var statsSection: some View {
        Section(header: Text("İstatistik").foregroundColor(.gray)) {
            StatRow(title: "Canlı Kanallar", value: "\(appViewModel.channels.count)")
            StatRow(title: "Filmler", value: "\(appViewModel.vodItems.count)")
            StatRow(title: "Diziler", value: "\(appViewModel.seriesItems.count)")
            StatRow(title: "Sürüm", value: "1.0.0")
        }
    }

    /// Bilgi bölümü varsayılan olarak kapalı; dokununca açılır.
    private var infoSection: some View {
        Section {
            DisclosureGroup(isExpanded: $infoExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bu uygulama herhangi bir ücret talep etmemektedir. Geliştirme aşamasındadır.")
                        .font(.footnote)
                        .foregroundColor(.white)
                    Text("Uygulama içerisinde önceden tanımlı veya barındırılan herhangi bir kanal listesi bulunmamaktadır. Kullanıcılar kendi M3U veya Xtream Codes bilgilerini eklemek zorundadır.")
                        .font(.footnote)
                        .foregroundColor(.white)
                    Text("Yıl: 2026")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Text("Sorumlu: Talat Özünal")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Button(action: openEmail) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Hata ve Bilgilendirmeler için İletişim")
                        }
                        .font(.footnote)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("Bilgi", systemImage: "info.circle")
                    .foregroundColor(.white)
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let error = appViewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Tek ekleme ekranı (M3U veya Xtream seçilir)

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
        NavigationView {
            Form {
                Section {
                    Picker("Tür", selection: $newType) {
                        Text("M3U").tag(PlaylistSource.SourceType.m3u)
                        Text("Xtream Codes").tag(PlaylistSource.SourceType.xtream)
                    }
                    .pickerStyle(.segmented)
                }

                if newType == .m3u {
                    Section(header: Text("M3U Bilgileri"), footer: Text("Doğrudan M3U dosyası veren bağlantıyı yapıştırın.")) {
                        TextField("İsim (opsiyonel)", text: $newPlaylistName)
                            .autocorrectionDisabled()
                        TextField("M3U URL", text: $newPlaylistURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                } else {
                    Section(header: Text("Xtream Codes Bilgileri"), footer: Text("Film ve diziler yalnızca Xtream hesaplarında tam çalışır.")) {
                        TextField("İsim (opsiyonel)", text: $newPlaylistName)
                            .autocorrectionDisabled()
                        TextField("Server URL (http://sunucu.com:8080)", text: $xtreamServer)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                        TextField("Kullanıcı Adı", text: $xtreamUser)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        SecureField("Şifre", text: $xtreamPass)
                    }
                }
            }
            .navigationTitle("Playlist Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") {
                        showAddSheet = false
                        resetForm()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ekle") {
                        addPlaylist()
                    }
                    .disabled(!canAdd)
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

    private func openEmail() {
        if let url = URL(string: "mailto:ozunaltalat@gmail.com?subject=Aurora%20IPTV%20Destek%20%2F%20Hata%20Bildirimi") {
            UIApplication.shared.open(url)
        }
    }
}

struct PlaylistRow: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let source: PlaylistSource

    private var isXtream: Bool { source.type == .xtream }
    private var accent: Color { isXtream ? .orange : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(source.name.isEmpty ? (isXtream ? "İsimsiz Xtream" : "İsimsiz M3U") : source.name)
                            .foregroundColor(.white)
                            .font(.subheadline)
                        Text(isXtream ? "Xtream" : "M3U")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.25))
                            .foregroundColor(accent)
                            .clipShape(Capsule())
                    }
                    Text(isXtream ? "\(source.serverURL) • \(source.username)" : source.url)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button {
                        Task { await appViewModel.loadPlaylist(source: source) }
                    } label: {
                        Label("Yenile", systemImage: "arrow.clockwise")
                    }
                    Button {
                        appViewModel.setEnabled(!source.enabled, for: source.id)
                    } label: {
                        Label(source.enabled ? "Devre Dışı Bırak" : "Etkinleştir",
                              systemImage: source.enabled ? "eye.slash" : "eye")
                    }
                    Button(role: .destructive) {
                        if let index = appViewModel.playlistSources.firstIndex(where: { $0.id == source.id }) {
                            appViewModel.removePlaylist(at: IndexSet([index]))
                        }
                    } label: {
                        Label("Kaldır", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                        .font(.title3)
                }
            }
            HStack {
                if appViewModel.isLoading && appViewModel.loadingSourceID == source.id {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accent))
                        .scaleEffect(0.8)
                    Text("Yükleniyor...")
                        .font(.caption2)
                        .foregroundColor(accent)
                } else if !source.enabled {
                    Text("Devre dışı (⋯ menüsünden etkinleştirin)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if let status = appViewModel.sourceStatus[source.id] {
                    Text(status.text)
                        .font(.caption2)
                        .foregroundColor(status.isError ? .red : .green)
                        .lineLimit(4)
                } else {
                    Text("Henüz yüklenmedi")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
        }
    }
}
