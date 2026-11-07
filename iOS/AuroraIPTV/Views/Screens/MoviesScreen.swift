
import SwiftUI

struct MoviesScreen: View {

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var selectedVod: VodItem?
    @State private var selectionError: String?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Favoriler varsa en üstte "★ Favoriler" kategorisi olarak eklenir.
    private var groups: [CategoryGroup<VodItem>] {
        let favorites = library.favoriteVod()
        if favorites.isEmpty { return appViewModel.vodGroups }
        return [CategoryGroup(name: "★ Favoriler", items: favorites)] + appViewModel.vodGroups
    }

    var body: some View {

        NavigationView {

            ZStack {

                Color.black.ignoresSafeArea()

                if appViewModel.vodItems.isEmpty {

                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("Film bulunmuyor")
                            .foregroundColor(.white)

                        Text("Playlist'lerde VOD/Film içerikleri aranıyor")
                            .foregroundColor(.gray)
                    }

                } else {

                    CategoryBrowser(groups: groups,
                                    searchResults: isSearching ? appViewModel.searchVod(searchText) : nil) { item in
                        let isFavorite = library.isFavorite(LibraryEntry.key(vod: item))
                        Button {
                            select(item)
                        } label: {
                            PosterCard(title: item.name, posterURL: item.posterURL, icon: "film", isFavorite: isFavorite)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                library.toggleFavorite(LibraryEntry(vod: item))
                            } label: {
                                Label(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                                      systemImage: isFavorite ? "star.slash" : "star")
                            }
                        }
                    }
                }

                if let error = selectionError {
                    VStack {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button("Kapat") {
                            selectionError = nil
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("Filmler")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Film ara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SortMenuButton()
                }
            }
            .fullScreenCover(item: $selectedVod) { item in

                if let urlString = item.streamURL,
                   let url = URL(string: urlString) {

                    VideoPlayerView(url: url)

                } else {

                    VStack(spacing: 16) {
                        Text("Yayın adresi bulunamadı")
                            .foregroundColor(.white)

                        Button("Kapat") {
                            selectedVod = nil
                        }
                        .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func select(_ item: VodItem) {
        print("[AuroraIPTV] Film seçildi: \(item.name)")

        guard
            let urlString = item.streamURL,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            selectionError = "Filmin yayın adresi geçersiz veya eksik."
            print("[AuroraIPTV] Geçersiz film URL")
            return
        }

        print("[AuroraIPTV] Film oynatıcıya gönderiliyor")
        library.recordPlay(LibraryEntry(vod: item))
        selectedVod = item
    }
}
