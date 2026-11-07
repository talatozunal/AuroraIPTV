import SwiftUI

struct TVLiveScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var selectedChannel: Channel?
    @Binding var showSearch: Bool

    /// Favoriler ve son izlenenler varsa listenin en üstüne ayrı kategoriler olarak eklenir.
    private var groups: [CategoryGroup<Channel>] {
        var result: [CategoryGroup<Channel>] = []
        let favorites = library.favoriteChannels()
            .filter { !appViewModel.isHiddenAdult(group: $0.group, name: $0.name) }
        if !favorites.isEmpty { result.append(CategoryGroup(name: "★ Favoriler", items: favorites)) }
        let recent = library.historyChannels()
            .filter { !appViewModel.isHiddenAdult(group: $0.group, name: $0.name) }
        if !recent.isEmpty { result.append(CategoryGroup(name: "Son İzlenenler", items: recent)) }
        return result + appViewModel.liveGroups
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                if appViewModel.channels.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tv.inset.filled")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.7))
                        Text(appViewModel.isLoading ? "Yükleniyor…" : "Henüz kanal bulunmuyor")
                            .font(.title2)
                            .foregroundColor(.white)
                        if !appViewModel.isLoading {
                            Text("Ayarlar'dan playlist ekleyin")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    TVCategoryBrowser(groups: groups, itemWidth: 280) { channel in
                        channelCard(channel)
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                TVSearchView(prompt: "Kanal ara",
                             search: { appViewModel.searchChannels($0) },
                             itemWidth: 280) { channel in
                    channelCard(channel)
                }
            }
        }
        .fullScreenCover(item: $selectedChannel) { channel in
            if let urlString = channel.streamURL, let url = URL(string: urlString) {
                TVVideoPlayerView(url: url, isLive: true,
                                   preferVLC: ContentCategorizer.prefersVLC(group: channel.group, name: channel.name))
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func channelCard(_ channel: Channel) -> some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(channel: channel))
        Button {
            play(channel)
        } label: {
            TVChannelCard(channel: channel, isFavorite: isFavorite, width: 280)
        }
        .buttonStyle(.auroraCard)
        .contextMenu {
            Button {
                library.toggleFavorite(LibraryEntry(channel: channel))
            } label: {
                Label(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }

    private func play(_ channel: Channel) {
        guard let urlString = channel.streamURL, URL(string: urlString) != nil else { return }
        library.recordPlay(LibraryEntry(channel: channel))
        selectedChannel = channel
    }
}
