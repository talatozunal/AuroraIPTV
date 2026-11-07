import SwiftUI

// MARK: - Aurora teması

/// Aurora (kuzey ışıkları) teması: koyu siyah yerine canlı mavi-turkuaz-mor geçişli arka plan.
enum AuroraTheme {
    static let accent = Color(red: 0.36, green: 0.92, blue: 0.78)      // nane yeşili vurgu
    static let onAccent = Color(red: 0.04, green: 0.15, blue: 0.28)    // vurgu üstündeki koyu yazı
    static let cardFill = Color.white.opacity(0.16)
    static let chipFill = Color.white.opacity(0.14)
}

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.22, blue: 0.50),
                         Color(red: 0.05, green: 0.46, blue: 0.58),
                         Color(red: 0.36, green: 0.24, blue: 0.66)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            // Yumuşak aurora ışımaları
            RadialGradient(colors: [Color(red: 0.25, green: 0.95, blue: 0.65).opacity(0.38), .clear],
                           center: .topLeading, startRadius: 40, endRadius: 1000)
            RadialGradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.80).opacity(0.28), .clear],
                           center: .bottomTrailing, startRadius: 40, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Odak (focus) stilleri

/// Sistemin beyaz odak plakası yerine: vurgu renkli çerçeve + hafif büyüme + gölge.
/// Yazı renkleri odakta değişmez, bu yüzden beyaz yazılar her zaman okunur.
struct AuroraCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuroraCardBody(configuration: configuration)
    }

    private struct AuroraCardBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isFocused ? Color.white.opacity(0.20) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isFocused ? AuroraTheme.accent : Color.clear, lineWidth: 4)
                )
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .shadow(color: Color.black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Sekme, kategori satırı, sıralama/arama gibi hap biçimli düğmeler için.
struct AuroraPillButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        AuroraPillBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct AuroraPillBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat

        var body: some View {
            configuration.label
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isFocused ? Color.white.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isFocused ? Color.white : Color.clear, lineWidth: 3)
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .shadow(color: Color.black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 5)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

extension ButtonStyle where Self == AuroraCardButtonStyle {
    static var auroraCard: AuroraCardButtonStyle { AuroraCardButtonStyle() }
}

// MARK: - Kartlar

/// Canlı kanal kartı (16:9 logo alanı + kanal adı)
struct TVChannelCard: View {
    let channel: Channel
    var isFavorite: Bool = false
    var width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AuroraTheme.cardFill)

                if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(20)
                } else {
                    Image(systemName: "tv")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    TVFavoriteBadge()
                }
            }

            Text(channel.name)
                .font(.callout)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// Film ve dizi afişi (2:3)
struct TVPosterCard: View {
    let title: String
    let posterURL: String?
    let icon: String
    var isFavorite: Bool = false
    var width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AuroraTheme.cardFill)

                if let posterURL = posterURL, let url = URL(string: posterURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: icon)
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    TVFavoriteBadge()
                }
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .topLeading)
        }
    }
}

struct TVFavoriteBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.callout)
            .foregroundColor(.yellow)
            .padding(8)
            .background(Color.black.opacity(0.7))
            .clipShape(Circle())
            .padding(8)
    }
}

// MARK: - Dikey kategori tarayıcı

/// Solda dikey kategori listesi (bölüm başlıklı), sağda seçili kategorinin kanal/afiş ızgarası.
/// Sıralama ve arama düğmeleri ekranın üst çubuğunda (TVRootView) yer alır.
struct TVCategoryBrowser<Item: Identifiable, Card: View>: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let groups: [CategoryGroup<Item>]
    let itemWidth: CGFloat
    let card: (Item) -> Card
    @State private var selected = "Tümü"

    init(groups: [CategoryGroup<Item>],
         itemWidth: CGFloat,
         @ViewBuilder card: @escaping (Item) -> Card) {
        self.groups = groups
        self.itemWidth = itemWidth
        self.card = card
    }

    private var totalCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            content
        }
    }

    // MARK: Kategori listesi (dikey)

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                sidebarRow("Tümü", count: totalCount)

                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if let section = group.section,
                       section != (index > 0 ? groups[index - 1].section : nil) {
                        Text(section.uppercased(with: Locale(identifier: "tr_TR")))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.leading, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 4)
                    }
                    sidebarRow(group.name, count: group.items.count)
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, 20)
            .padding(.vertical, 20)
        }
        .frame(width: 480)
        .focusSection()
    }

    private func sidebarRow(_ name: String, count: Int) -> some View {
        Button {
            selected = name
        } label: {
            HStack {
                Text(name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(count)")
                    .font(.caption)
                    .opacity(0.7)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == name ? AuroraTheme.accent : AuroraTheme.chipFill)
            .foregroundColor(selected == name ? AuroraTheme.onAccent : .white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(AuroraPillButtonStyle(cornerRadius: 12))
    }

    // MARK: İçerik (dikey ızgara)

    @ViewBuilder
    private var content: some View {
        let selectedGroup = groups.first(where: { $0.name == selected })
        let items: [Item] = selectedGroup?.items ?? groups.flatMap { $0.items }
        let title = selectedGroup?.name ?? "Tümü"

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(title) • \(items.count)")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.leading, 10)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: itemWidth), spacing: 40)], spacing: 50) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .focusSection()
    }
}

// MARK: - Arama sayfası

/// Arama simgesine basılınca açılan sayfa. Yazdıkça sonuçlar dikey ızgarada listelenir.
struct TVSearchView<Item: Identifiable, Card: View>: View {
    let prompt: String
    let search: (String) -> [Item]
    let itemWidth: CGFloat
    let card: (Item) -> Card
    @State private var query = ""

    init(prompt: String,
         search: @escaping (String) -> [Item],
         itemWidth: CGFloat,
         @ViewBuilder card: @escaping (Item) -> Card) {
        self.prompt = prompt
        self.search = search
        self.itemWidth = itemWidth
        self.card = card
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let results: [Item] = trimmed.isEmpty ? [] : search(query)

        ZStack {
            if trimmed.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Aramak için yazın")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if results.isEmpty {
                Text("Sonuç bulunamadı")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("\(results.count) sonuç")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: itemWidth), spacing: 40)], spacing: 50) {
                            ForEach(results) { item in
                                card(item)
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 30)
                }
            }
        }
        .searchable(text: $query, prompt: prompt)
    }
}
