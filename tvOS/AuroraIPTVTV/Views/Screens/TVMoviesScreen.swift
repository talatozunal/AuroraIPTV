import SwiftUI

struct TVMoviesScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var selectedVod: VodItem?
    @State private var selectionError: String?
    @Binding var showSearch: Bool

    /// Favoriler ve son izlenenler varsa listenin en üstüne ayrı kategoriler olarak eklenir.
    private var groups: [CategoryGroup<VodItem>] {
        var result: [CategoryGroup<VodItem>] = []
        let favorites = library.favoriteVod()
            .filter { !appViewModel.isHiddenAdult(group: $0.group, name: nil) }
        if !favorites.isEmpty { result.append(CategoryGroup(name: "★ Favoriler", items: favorites)) }
        let recent = library.historyVod()
            .filter { !appViewModel.isHiddenAdult(group: $0.group, name: nil) }
        if !recent.isEmpty { result.append(CategoryGroup(name: "Son İzlenenler", items: recent)) }
        return result + appViewModel.vodGroups
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                if appViewModel.vodItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "film")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.7))
                        Text(appViewModel.isLoading ? "Yükleniyor…" : "Film bulunmuyor")
                            .font(.title2)
                            .foregroundColor(.white)
                        if !appViewModel.isLoading {
                            Text("Filmler için Xtream Codes hesabı ekleyin ya da film içeren bir M3U kullanın")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    TVCategoryBrowser(groups: groups, itemWidth: 200) { item in
                        movieCard(item)
                    }
                }

                if let error = selectionError {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.white)
                            .padding(24)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(16)
                            .padding(.bottom, 60)
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                TVSearchView(prompt: "Film ara",
                             search: { appViewModel.searchVod($0) },
                             itemWidth: 200) { item in
                    movieCard(item)
                }
            }
        }
        .fullScreenCover(item: $selectedVod) { item in
            if let urlString = item.streamURL, let url = URL(string: urlString) {
                TVVideoPlayerView(url: url)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func movieCard(_ item: VodItem) -> some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(vod: item))
        Button {
            select(item)
        } label: {
            TVPosterCard(title: item.name, posterURL: item.posterURL, icon: "film", isFavorite: isFavorite, width: 200)
        }
        .buttonStyle(.auroraCard)
        .contextMenu {
            Button {
                library.toggleFavorite(LibraryEntry(vod: item))
            } label: {
                Label(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }

    private func select(_ item: VodItem) {
        guard
            let urlString = item.streamURL,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            selectionError = "Filmin yayın adresi geçersiz veya eksik."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { selectionError = nil }
            return
        }
        library.recordPlay(LibraryEntry(vod: item))
        selectedVod = item
    }
}
