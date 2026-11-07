import SwiftUI

/// Kendi üst çubuğumuz: sekmeler solda, sıralama ve arama simgesi sağda, aynı hizada.
struct TVRootView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var selectedTab = 0
    @State private var showLiveSearch = false
    @State private var showMoviesSearch = false
    @State private var showSeriesSearch = false

    private struct TabInfo {
        let title: String
        let icon: String
    }

    private let tabs: [TabInfo] = [
        TabInfo(title: "Canlı TV", icon: "tv"),
        TabInfo(title: "Filmler", icon: "film"),
        TabInfo(title: "Diziler", icon: "play.rectangle"),
        TabInfo(title: "Kütüphane", icon: "star"),
        TabInfo(title: "Ayarlar", icon: "gearshape")
    ]

    /// Sıralama ve arama yalnızca Canlı TV / Filmler / Diziler sekmelerinde görünür.
    private var isBrowseTab: Bool { selectedTab <= 2 }

    private var searchOpen: Bool {
        switch selectedTab {
        case 0: return showLiveSearch
        case 1: return showMoviesSearch
        default: return showSeriesSearch
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .task {
            // Açılışta kayıtlı playlist'leri yükle
            if appViewModel.playlistSources.contains(where: { $0.enabled }) {
                await appViewModel.loadAllPlaylists()
            }
        }
    }

    // MARK: Üst çubuk

    private var header: some View {
        HStack(spacing: 14) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    selectedTab = index
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.callout)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(selectedTab == index ? Color.white.opacity(0.28) : Color.clear)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))
            }

            Spacer()

            if isBrowseTab {
                Button {
                    appViewModel.sortMode = appViewModel.sortMode.next
                } label: {
                    Label(appViewModel.sortMode.shortTitle, systemImage: "arrow.up.arrow.down")
                        .font(.callout)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(AuroraTheme.chipFill)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))

                if !searchOpen {
                    Button {
                        openSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.callout)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(AuroraTheme.chipFill)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(AuroraPillButtonStyle(cornerRadius: 40))
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .focusSection()
    }

    private func openSearch() {
        switch selectedTab {
        case 0: showLiveSearch = true
        case 1: showMoviesSearch = true
        default: showSeriesSearch = true
        }
    }

    // MARK: İçerik

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case 0: TVLiveScreen(showSearch: $showLiveSearch)
        case 1: TVMoviesScreen(showSearch: $showMoviesSearch)
        case 2: TVSeriesScreen(showSearch: $showSeriesSearch)
        case 3: TVLibraryScreen()
        default: TVSettingsScreen()
        }
    }
}
