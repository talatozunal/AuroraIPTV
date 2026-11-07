import SwiftUI

struct LiveTVScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var library: LibraryStore
    @State private var selectedChannel: Channel?
    @State private var selectedGroup: String = "Tümü"
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Favoriler varsa en üstte "★ Favoriler" kategorisi olarak eklenir.
    private var groups: [CategoryGroup<Channel>] {
        let favorites = library.favoriteChannels()
        if favorites.isEmpty { return appViewModel.liveGroups }
        return [CategoryGroup(name: "★ Favoriler", items: favorites)] + appViewModel.liveGroups
    }

    private var names: [String] {
        ["Tümü"] + groups.map { $0.name }
    }

    private var counts: [String: Int] {
        var result: [String: Int] = ["Tümü": appViewModel.channels.count]
        for group in groups { result[group.name] = group.items.count }
        return result
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Canlı TV")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Kanal ara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SortMenuButton()
                }
            }
            .fullScreenCover(item: $selectedChannel) { channel in
                if let urlString = channel.streamURL, let url = URL(string: urlString) {
                    VideoPlayerView(url: url, isLive: true)
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        if appViewModel.channels.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "tv.inset.filled")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("Henüz kanal bulunmuyor")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Ayarlar'dan playlist ekleyin")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        } else if isSearching {
            searchResultsView
        } else {
            VStack(spacing: 0) {
                CategoryChipBar(names: names, counts: counts, selected: $selectedGroup)

                if let group = groups.first(where: { $0.name == selectedGroup }) {
                    List(group.items) { channel in
                        row(for: channel)
                    }
                    .listStyle(.plain)
                } else {
                    // Tümü: kategoriler başlıklı bölümler halinde (favoriler ve TR başta)
                    List {
                        ForEach(groups) { group in
                            Section(header: sectionHeader(group)) {
                                ForEach(group.items) { channel in
                                    row(for: channel)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var searchResultsView: some View {
        let results = appViewModel.searchChannels(searchText)
        return Group {
            if results.isEmpty {
                VStack {
                    Text("Sonuç bulunamadı")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 60)
                    Spacer()
                }
            } else {
                List {
                    Section(header: Text("\(results.count) sonuç").foregroundColor(.gray).textCase(nil)) {
                        ForEach(results) { channel in
                            row(for: channel)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func row(for channel: Channel) -> some View {
        ChannelRow(channel: channel) {
            if let urlString = channel.streamURL, URL(string: urlString) != nil {
                library.recordPlay(LibraryEntry(channel: channel))
                selectedChannel = channel
            }
        }
        .listRowBackground(Color.clear)
    }

    private func sectionHeader(_ group: CategoryGroup<Channel>) -> some View {
        Button {
            selectedGroup = group.name
        } label: {
            HStack {
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(group.items.count)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .textCase(nil)
        }
    }
}
