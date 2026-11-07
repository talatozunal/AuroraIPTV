import SwiftUI

struct TVSeriesScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var directSeries: SeriesItem?
    @Binding var showSearch: Bool

    /// Favoriler varsa en üstte "★ Favoriler" kategorisi olarak eklenir.
    private var groups: [CategoryGroup<SeriesItem>] {
        let favorites = library.favoriteSeries()
            .filter { !appViewModel.isHiddenAdult(group: $0.group, name: nil) }
        if favorites.isEmpty { return appViewModel.seriesGroups }
        return [CategoryGroup(name: "★ Favoriler", items: favorites)] + appViewModel.seriesGroups
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                if appViewModel.seriesItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.7))
                        Text(appViewModel.isLoading ? "Yükleniyor…" : "Dizi bulunmuyor")
                            .font(.title2)
                            .foregroundColor(.white)
                        if !appViewModel.isLoading {
                            Text("Diziler için Xtream Codes hesabı ekleyin ya da dizi içeren bir M3U kullanın")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    TVCategoryBrowser(groups: groups, itemWidth: 200) { item in
                        seriesCard(item)
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                TVSearchView(prompt: "Dizi ara",
                             search: { appViewModel.searchSeries($0) },
                             itemWidth: 200) { item in
                    seriesCard(item)
                }
            }
        }
        .fullScreenCover(item: $directSeries) { item in
            if let urlString = item.streamURL, let url = URL(string: urlString) {
                TVVideoPlayerView(url: url)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func seriesCard(_ item: SeriesItem) -> some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(series: item))

        Group {
            if item.seriesID != nil, item.account != nil {
                // Xtream: sezon / bölüm listesine git
                NavigationLink {
                    TVSeriesDetailScreen(series: item)
                } label: {
                    TVPosterCard(title: item.name, posterURL: item.posterURL, icon: "play.rectangle", isFavorite: isFavorite, width: 200)
                }
                .buttonStyle(.auroraCard)
            } else if item.streamURL != nil {
                // M3U: öğe doğrudan oynatılabilir bir bölüm
                Button {
                    library.recordPlay(LibraryEntry(playableSeries: item))
                    directSeries = item
                } label: {
                    TVPosterCard(title: item.name, posterURL: item.posterURL, icon: "play.rectangle", isFavorite: isFavorite, width: 200)
                }
                .buttonStyle(.auroraCard)
            } else {
                TVPosterCard(title: item.name, posterURL: item.posterURL, icon: "play.rectangle", isFavorite: isFavorite, width: 200)
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

// MARK: - Dizi ayrıntısı (sezon / bölümler)

struct TVSeriesDetailScreen: View {
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
            Color.clear

            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.6)
                    Text("Bölümler yükleniyor…")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            } else if let errorText = errorText {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.yellow)
                    Text(errorText)
                        .font(.title3)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1000)
                    Button {
                        Task { await load() }
                    } label: {
                        Text("Tekrar Dene")
                            .font(.callout)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(AuroraTheme.chipFill)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))
                }
            } else if (detail?.episodes ?? []).isEmpty {
                Text("Bu dizi için bölüm bulunamadı")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        header

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(seasons, id: \.self) { season in
                                    Button {
                                        selectedSeason = season
                                    } label: {
                                        Text(season == 0 ? "Özel" : "Sezon \(season)")
                                            .font(.callout)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 12)
                                            .background(selectedSeason == season ? AuroraTheme.accent : AuroraTheme.chipFill)
                                            .foregroundColor(selectedSeason == season ? AuroraTheme.onAccent : .white)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        .focusSection()

                        LazyVStack(spacing: 16) {
                            ForEach(episodesInSeason) { episode in
                                Button {
                                    library.recordPlay(LibraryEntry(episode: episode, series: series))
                                    playingEpisode = episode
                                } label: {
                                    episodeRow(episode)
                                }
                                .buttonStyle(.auroraCard)
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playingEpisode) { episode in
            if let url = URL(string: episode.streamURL) {
                TVVideoPlayerView(url: url)
            } else {
                Color.clear
            }
        }
    }

    private var header: some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(series: series))

        return HStack(alignment: .top, spacing: 40) {
            if let posterURL = series.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    AuroraTheme.chipFill
                }
                .frame(width: 240, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(series.name)
                    .font(.title2)
                    .foregroundColor(.white)
                if let year = series.year {
                    Text(year)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.7))
                }
                if let plot = detail?.plot ?? series.plot {
                    Text(plot)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(6)
                }
                Button {
                    library.toggleFavorite(LibraryEntry(series: series))
                } label: {
                    Label(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                          systemImage: isFavorite ? "star.fill" : "star")
                        .font(.callout)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(AuroraTheme.chipFill)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(AuroraTheme.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(episode.number). \(episode.title)")
                    .font(.callout)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
