import SwiftUI

struct RootView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            LiveTVScreen()
                .tabItem {
                    Label("Canlı TV", systemImage: "tv")
                }
                .tag(0)
            
            MoviesScreen()
                .tabItem {
                    Label("Filmler", systemImage: "film")
                }
                .tag(1)
            
            SeriesScreen()
                .tabItem {
                    Label("Diziler", systemImage: "play.rectangle")
                }
                .tag(2)
            
            LibraryScreen()
                .tabItem {
                    Label("Kütüphane", systemImage: "star")
                }
                .tag(3)

            SettingsScreen()
                .tabItem {
                    Label("Ayarlar", systemImage: "gear")
                }
                .tag(4)
        }
        .accentColor(.blue)
        .task {
            // Reload saved playlists whenever the app starts.
            await appViewModel.loadAllPlaylists()
        }
    }
}


// MARK: - Kütüphane (Favoriler ve Son İzlenenler)

struct LibraryScreen: View {
    @EnvironmentObject var library: LibraryStore
    @State private var mode = 0   // 0: Favoriler, 1: Son İzlenenler
    @State private var playTarget: PlayTarget?

    struct PlayTarget: Identifiable {
        let id = UUID()
        let url: URL
        let isLive: Bool
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        Text("Favoriler").tag(0)
                        Text("Son İzlenenler").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if mode == 0 {
                        favoritesList
                    } else {
                        historyList
                    }
                }
            }
            .navigationTitle("Kütüphane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Temizle") {
                        library.clearHistory()
                    }
                    .opacity(mode == 1 && !library.history.isEmpty ? 1 : 0)
                    .disabled(!(mode == 1 && !library.history.isEmpty))
                }
            }
            .fullScreenCover(item: $playTarget) { target in
                VideoPlayerView(url: target.url, isLive: target.isLive)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Favoriler

    private var favoritesList: some View {
        Group {
            if library.favorites.isEmpty {
                emptyState(icon: "star",
                           title: "Henüz favori yok",
                           message: "Kanallarda yıldıza dokunun; film ve dizilerde afişe uzun basın.")
            } else {
                List {
                    favoriteSection("Canlı TV", kind: .live)
                    favoriteSection("Filmler", kind: .movie)
                    favoriteSection("Diziler", kind: .series)
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func favoriteSection(_ title: String, kind: LibraryKind) -> some View {
        let items = library.favorites.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(header: Text(title).foregroundColor(.gray).textCase(nil)) {
                ForEach(items) { entry in
                    entryRow(entry, showDate: false)
                }
                .onDelete { offsets in
                    library.removeFavorites(ids: offsets.map { items[$0].id })
                }
            }
        }
    }

    // MARK: Son izlenenler

    private var historyList: some View {
        Group {
            if library.history.isEmpty {
                emptyState(icon: "clock",
                           title: "Henüz izleme geçmişi yok",
                           message: "İzlediğiniz kanal, film ve dizi bölümleri burada görünür.")
            } else {
                List {
                    ForEach(library.history) { entry in
                        entryRow(entry, showDate: true)
                    }
                    .onDelete { offsets in
                        let items = library.history
                        library.removeHistory(ids: offsets.map { items[$0].id })
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: Ortak

    @ViewBuilder
    private func entryRow(_ entry: LibraryEntry, showDate: Bool) -> some View {
        if entry.kind == .series, entry.seriesID != nil, entry.account != nil {
            NavigationLink(destination: SeriesDetailScreen(series: entry.asSeries)) {
                LibraryRow(entry: entry, showDate: showDate)
            }
            .listRowBackground(Color.clear)
        } else {
            Button {
                play(entry)
            } label: {
                LibraryRow(entry: entry, showDate: showDate)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }

    private func play(_ entry: LibraryEntry) {
        guard let urlString = entry.streamURL, let url = URL(string: urlString) else { return }
        library.recordPlay(entry)
        playTarget = PlayTarget(url: url, isLive: entry.kind == .live)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 54))
                .foregroundColor(.gray)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct LibraryRow: View {
    let entry: LibraryEntry
    let showDate: Bool

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var isLive: Bool { entry.kind == .live }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if showDate {
            return "\(entry.kind.title) • " + Self.formatter.localizedString(for: entry.date, relativeTo: Date())
        }
        return entry.group ?? entry.kind.title
    }

    private var thumbnail: some View {
        Group {
            if let imageURL = entry.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: isLive ? .fit : .fill)
                } placeholder: {
                    Image(systemName: entry.kind.icon)
                        .foregroundColor(.gray)
                }
            } else {
                Image(systemName: entry.kind.icon)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: isLive ? 60 : 44, height: isLive ? 40 : 62)
        .background(Color.black.opacity(0.3))
        .cornerRadius(4)
        .clipped()
    }
}
