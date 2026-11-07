import SwiftUI

struct ChannelRow: View {
    @EnvironmentObject var library: LibraryStore
    let channel: Channel
    let action: () -> Void

    var body: some View {
        let isFavorite = library.isFavorite(LibraryEntry.key(channel: channel))

        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: "tv")
                                .foregroundColor(.gray)
                        }
                        .frame(width: 60, height: 40)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(4)
                    } else {
                        Image(systemName: "tv")
                            .foregroundColor(.gray)
                            .frame(width: 60, height: 40)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(4)
                    }

                    Text(channel.name)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button {
                library.toggleFavorite(LibraryEntry(channel: channel))
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

// MARK: - Kategori bileşenleri

/// Yatay kaydırılan kategori çubuğu (adet göstergeli).
struct CategoryChipBar: View {
    let names: [String]
    let counts: [String: Int]
    @Binding var selected: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            selected = name
                        } label: {
                            HStack(spacing: 6) {
                                Text(name)
                                if let count = counts[name] {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .opacity(0.7)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected == name ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                        }
                        .id(name)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .onChange(of: selected) { value in
                withAnimation { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }
}

struct PosterCard: View {
    let title: String
    let posterURL: String?
    let icon: String
    var isFavorite: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(2/3, contentMode: .fit)

                if let posterURL = posterURL, let url = URL(string: posterURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: icon)
                            .foregroundColor(.gray)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(5)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Circle())
                        .padding(4)
                }
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
    }
}

/// Üst çubuktaki sıralama menüsü (Önerilen / A → Z / Z → A).
struct SortMenuButton: View {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        Menu {
            Picker("Sıralama", selection: $appViewModel.sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}

/// Film ve diziler için: "Tümü" seçiliyken her kategori yatay bir satır olarak görünür,
/// bir kategori seçilince o kategorinin tamamı ızgarada açılır. Arama yapılıyorsa sonuçlar ızgarada gösterilir.
struct CategoryBrowser<Item: Identifiable, Card: View>: View {
    let groups: [CategoryGroup<Item>]
    let searchResults: [Item]?
    let card: (Item) -> Card
    @State private var selected = "Tümü"

    init(groups: [CategoryGroup<Item>], searchResults: [Item]? = nil, @ViewBuilder card: @escaping (Item) -> Card) {
        self.groups = groups
        self.searchResults = searchResults
        self.card = card
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var names: [String] {
        ["Tümü"] + groups.map { $0.name }
    }

    private var counts: [String: Int] {
        var result: [String: Int] = ["Tümü": groups.reduce(0) { $0 + $1.items.count }]
        for group in groups { result[group.name] = group.items.count }
        return result
    }

    var body: some View {
        if let results = searchResults {
            searchView(results)
        } else {
            browseView
        }
    }

    private func searchView(_ results: [Item]) -> some View {
        ScrollView {
            if results.isEmpty {
                Text("Sonuç bulunamadı")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(results.count) sonuç")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { item in
                            card(item)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 12)
            }
        }
    }

    private var browseView: some View {
        VStack(spacing: 0) {
            CategoryChipBar(names: names, counts: counts, selected: $selected)

            if let group = groups.first(where: { $0.name == selected }) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(group.items) { item in
                            card(item)
                        }
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(groups) { group in
                            row(for: group)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func row(for group: CategoryGroup<Item>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selected = group.name
            } label: {
                HStack {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("\(group.items.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("Tümünü gör")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(group.items.prefix(20))) { item in
                        card(item)
                            .frame(width: 110)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
