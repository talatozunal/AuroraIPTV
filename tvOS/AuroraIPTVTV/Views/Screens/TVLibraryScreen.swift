import SwiftUI

/// Kütüphane: Favoriler ve Son İzlenenler.
/// Bir kaydı kaldırmak için üzerine uzun basın (Select tuşunu basılı tutun).
struct TVLibraryScreen: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var mode = 0   // 0: Favoriler, 1: Son İzlenenler
    @State private var playTarget: PlayTarget?

    struct PlayTarget: Identifiable {
        let id = UUID()
        let url: URL
        let isLive: Bool
        var preferVLC: Bool = false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                VStack(spacing: 24) {
                    HStack(spacing: 40) {
                        Picker("", selection: $mode) {
                            Text("Favoriler").tag(0)
                            Text("Son İzlenenler").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 700)

                        if mode == 1 && !visibleHistory.isEmpty {
                            Button("Geçmişi Temizle") {
                                library.clearHistory()
                            }
                        }
                    }
                    .padding(.top, 20)

                    if mode == 0 {
                        favoritesContent
                    } else {
                        historyContent
                    }
                }
            }
            .fullScreenCover(item: $playTarget) { target in
                TVVideoPlayerView(url: target.url, isLive: target.isLive, preferVLC: target.preferVLC)
            }
        }
    }

    private var visibleFavorites: [LibraryEntry] {
        library.favorites.filter { !appViewModel.shouldHide($0) }
    }

    private var visibleHistory: [LibraryEntry] {
        library.history.filter { !appViewModel.shouldHide($0) }
    }

    // MARK: Favoriler

    @ViewBuilder
    private var favoritesContent: some View {
        if visibleFavorites.isEmpty {
            emptyState(icon: "star",
                       title: "Henüz favori yok",
                       message: "Kanal, film veya dizi kartına uzun basıp \"Favorilere Ekle\"yi seçin.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    favoriteSection("Canlı TV", kind: .live)
                    favoriteSection("Filmler", kind: .movie)
                    favoriteSection("Diziler", kind: .series)
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private func favoriteSection(_ title: String, kind: LibraryKind) -> some View {
        let items = visibleFavorites.filter { $0.kind == kind }
        if !items.isEmpty {
            Text(title)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 20)
            ForEach(items) { entry in
                entryRow(entry, showDate: false)
                    .contextMenu {
                        Button(role: .destructive) {
                            library.removeFavorites(ids: [entry.id])
                        } label: {
                            Label("Favorilerden Çıkar", systemImage: "star.slash")
                        }
                    }
            }
        }
    }

    // MARK: Son izlenenler

    @ViewBuilder
    private var historyContent: some View {
        if visibleHistory.isEmpty {
            emptyState(icon: "clock",
                       title: "Henüz izleme geçmişi yok",
                       message: "İzlediğiniz kanal, film ve dizi bölümleri burada görünür.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(visibleHistory) { entry in
                        entryRow(entry, showDate: true)
                            .contextMenu {
                                Button(role: .destructive) {
                                    library.removeHistory(ids: [entry.id])
                                } label: {
                                    Label("Geçmişten Sil", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: Ortak

    @ViewBuilder
    private func entryRow(_ entry: LibraryEntry, showDate: Bool) -> some View {
        if entry.kind == .series, entry.seriesID != nil, entry.account != nil {
            NavigationLink {
                TVSeriesDetailScreen(series: entry.asSeries)
            } label: {
                TVLibraryRow(entry: entry, showDate: showDate)
            }
            .buttonStyle(.auroraCard)
        } else {
            Button {
                play(entry)
            } label: {
                TVLibraryRow(entry: entry, showDate: showDate)
            }
            .buttonStyle(.auroraCard)
        }
    }

    private func play(_ entry: LibraryEntry) {
        guard let urlString = entry.streamURL, let url = URL(string: urlString) else { return }
        library.recordPlay(entry)
        playTarget = PlayTarget(url: url,
                                isLive: entry.kind == .live,
                                preferVLC: entry.kind == .live && ContentCategorizer.prefersVLC(group: entry.group, name: entry.name))
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.7))
            Text(title)
                .font(.title2)
                .foregroundColor(.white)
            Text(message)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct TVLibraryRow: View {
    let entry: LibraryEntry
    let showDate: Bool

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var isLive: Bool { entry.kind == .live }

    var body: some View {
        HStack(spacing: 24) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.callout)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                Image(systemName: entry.kind.icon)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: isLive ? 140 : 80, height: isLive ? 80 : 120)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
