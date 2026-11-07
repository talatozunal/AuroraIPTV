import SwiftUI

struct SeriesScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var directSeries: SeriesItem?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Favoriler varsa en üstte "★ Favoriler" kategorisi olarak eklenir.
    private var groups: [CategoryGroup<SeriesItem>] {
        let favorites = library.favoriteSeries()
        if favorites.isEmpty { return appViewModel.seriesGroups }
        return [CategoryGroup(name: "★ Favoriler", items: favorites)] + appViewModel.seriesGroups
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if appViewModel.seriesItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Dizi bulunmuyor")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Playlist'lerde dizi içerikleri aranıyor")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    CategoryBrowser(groups: groups,
                                    searchResults: isSearching ? appViewModel.searchSeries(searchText) : nil) { item in
                        seriesCard(item)
                    }
                }
            }
            .navigationTitle("Diziler")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Dizi ara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SortMenuButton()
                }
            }
            .fullScreenCover(item: $directSeries) { item in
                if let urlString = item.streamURL, let url = URL(string: urlString) {
                    VideoPlayerView(url: url)
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func seriesCard(_ item: SeriesItem) -> some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(series: item))

        Group {
            if item.seriesID != nil, item.account != nil {
                // Xtream: bölüm listesine git
                NavigationLink(destination: SeriesDetailScreen(series: item)) {
                    SeriesCard(item: item, isFavorite: isFavorite)
                }
                .buttonStyle(.plain)
            } else if item.streamURL != nil {
                // M3U: öğe doğrudan oynatılabilir bir bölüm
                Button {
                    library.recordPlay(LibraryEntry(playableSeries: item))
                    directSeries = item
                } label: {
                    SeriesCard(item: item, isFavorite: isFavorite)
                }
                .buttonStyle(.plain)
            } else {
                SeriesCard(item: item, isFavorite: isFavorite)
            }
        }
        .contextMenu {
            Button {
                library.toggleFavorite(LibraryEntry(series: item))
            } label: {
                Label(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }
}

struct SeriesCard: View {
    let item: SeriesItem
    var isFavorite: Bool = false

    var body: some View {
        PosterCard(title: item.name, posterURL: item.posterURL, icon: "play.rectangle", isFavorite: isFavorite)
    }
}

struct SeriesDetailScreen: View {
    @EnvironmentObject var library: LibraryStore
    let series: SeriesItem

    @State private var detail: SeriesDetail?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selectedSeason: Int = 1
    @State private var playingEpisode: Episode?

    private var seasons: [Int] {
        Array(Set((detail?.episodes ?? []).map { $0.season })).sorted()
    }

    private var episodesInSeason: [Episode] {
        (detail?.episodes ?? []).filter { $0.season == selectedSeason }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Bölümler yükleniyor…")
                        .font(.callout)
                        .foregroundColor(.white)
                }
            } else if let errorText = errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(errorText)
                        .font(.callout)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Tekrar Dene") {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            } else if (detail?.episodes ?? []).isEmpty {
                Text("Bu dizi için bölüm bulunamadı")
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(seasons, id: \.self) { season in
                                    Button {
                                        selectedSeason = season
                                    } label: {
                                        Text(season == 0 ? "Özel" : "Sezon \(season)")
                                            .font(.subheadline)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedSeason == season ? Color.blue : Color.gray.opacity(0.3))
                                            .foregroundColor(.white)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(episodesInSeason) { episode in
                                Button {
                                    library.recordPlay(LibraryEntry(episode: episode, series: series))
                                    playingEpisode = episode
                                } label: {
                                    episodeRow(episode)
                                }
                                .buttonStyle(.plain)
                                Divider().background(Color.gray.opacity(0.3))
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                let isFavorite = library.isFavorite(LibraryEntry.key(series: series))
                Button {
                    library.toggleFavorite(LibraryEntry(series: series))
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .blue)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playingEpisode) { episode in
            if let url = URL(string: episode.streamURL) {
                VideoPlayerView(url: url)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let posterURL = series.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(series.name)
                    .font(.headline)
                    .foregroundColor(.white)
                if let year = series.year {
                    Text(year)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if let plot = detail?.plot ?? series.plot {
                    Text(plot)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(6)
                }
            }
        }
        .padding(.horizontal)
    }

    private func episodeRow(_ episode: Episode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.number). \(episode.title)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .contentShape(Rectangle())
    }

    @MainActor
    private func load() async {
        guard let account = series.account, let seriesID = series.seriesID else {
            isLoading = false
            errorText = "Dizi bilgisi eksik."
            return
        }
        isLoading = true
        errorText = nil
        do {
            let result = try await XtreamService.shared.fetchSeriesDetail(account: account, seriesID: seriesID)
            detail = result
            selectedSeason = result.episodes.map { $0.season }.min() ?? 1
        } catch {
            errorText = "Bölümler alınamadı: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
