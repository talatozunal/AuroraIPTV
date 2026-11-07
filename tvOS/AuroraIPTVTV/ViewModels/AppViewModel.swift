import Foundation
import SwiftUI

class AppViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var vodItems: [VodItem] = []
    @Published var seriesItems: [SeriesItem] = []
    @Published var liveGroups: [CategoryGroup<Channel>] = []
    @Published var vodGroups: [CategoryGroup<VodItem>] = []
    @Published var seriesGroups: [CategoryGroup<SeriesItem>] = []
    @Published var isLoading = false
    @Published var loadingSourceID: UUID? = nil
    @Published var errorMessage: String?
    /// Her playlist'in son yükleme sonucu (satırda gösterilir)
    @Published var sourceStatus: [UUID: SourceStatus] = [:]

    @Published var playlistSources: [PlaylistSource] = [] {
        didSet {
            savePlaylistSources()
        }
    }

    /// Her playlist kendi içeriğini ayrı tutar; böylece tek tek yüklemek mükerrer kayıt üretmez.
    struct SourceStatus {
        let text: String
        let isError: Bool
    }

    private struct SourceContent {
        var channels: [Channel] = []
        var vod: [VodItem] = []
        var series: [SeriesItem] = []
        var note: String?
        var isEmpty: Bool { channels.isEmpty && vod.isEmpty && series.isEmpty }
        var summary: String {
            if let note = note { return "Yüklendi\n" + note }
            return "Yüklendi"
        }
    }
    private var contentBySource: [UUID: SourceContent] = [:]   // yalnızca ana thread'de kullanılır

    /// Sıralama: Önerilen (TR başta), A → Z, Z → A. Seçim kalıcıdır.
    @Published var sortMode: SortMode = SortMode(rawValue: UserDefaults.standard.string(forKey: "sortMode") ?? "") ?? .recommended {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode")
            if oldValue != sortMode {
                Task { await self.applySort() }
            }
        }
    }

    /// Yetişkin içerikli kanal/film/dizileri gizler (varsayılan: açık). Seçim kalıcıdır.
    @Published var hideAdult: Bool = (UserDefaults.standard.object(forKey: "hideAdult") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(hideAdult, forKey: "hideAdult")
            if oldValue != hideAdult {
                Task { await self.publishMergedLists() }
            }
        }
    }

    /// Favori/geçmiş gibi listelerde de aynı filtreyi uygulamak için
    func isHiddenAdult(group: String?, name: String?) -> Bool {
        hideAdult && ContentCategorizer.isAdult(group: group, name: name)
    }

    func shouldHide(_ entry: LibraryEntry) -> Bool {
        isHiddenAdult(group: entry.group, name: entry.kind == .live ? entry.name : nil)
    }

    // Kategorilenmiş (önerilen sırada) ham gruplar ve arama dizini — ana thread'de kullanılır
    private var baseLive: [CategoryGroup<Channel>] = []
    private var baseVod: [CategoryGroup<VodItem>] = []
    private var baseSeries: [CategoryGroup<SeriesItem>] = []
    private var liveKeys: [String: String] = [:]
    private var vodKeys: [String: String] = [:]
    private var seriesKeys: [String: String] = [:]
    private var loadGeneration = 0                              // "Durdur" ve çakışan yüklemeler için

    init() {
        loadPlaylistSources()
    }

    // MARK: - Playlist kayıtları

    func loadPlaylistSources() {
        if let data = UserDefaults.standard.data(forKey: "playlistSources"),
           let decoded = try? JSONDecoder().decode([PlaylistSource].self, from: data) {
            self.playlistSources = decoded
        } else if let oldURL = UserDefaults.standard.string(forKey: "playlistURL"), !oldURL.isEmpty {
            self.playlistSources = [PlaylistSource(name: "Playlist 1", url: oldURL, type: .m3u)]
            UserDefaults.standard.removeObject(forKey: "playlistURL")
        }
    }

    func savePlaylistSources() {
        if let encoded = try? JSONEncoder().encode(playlistSources) {
            UserDefaults.standard.set(encoded, forKey: "playlistSources")
        }
    }

    func addM3UPlaylist(name: String, url: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = PlaylistSource(name: cleanName.isEmpty ? "M3U \(playlistSources.count + 1)" : cleanName,
                                    url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                    type: .m3u)
        playlistSources.append(source)
    }

    func addXtreamPlaylist(name: String, serverURL: String, username: String, password: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = PlaylistSource(name: cleanName.isEmpty ? "Xtream \(playlistSources.count + 1)" : cleanName,
                                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: password,
                                    serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                    type: .xtream)
        playlistSources.append(source)
    }

    func removePlaylist(at indexSet: IndexSet) {
        let removedIDs = indexSet.map { playlistSources[$0].id }
        playlistSources.remove(atOffsets: indexSet)
        removedIDs.forEach {
            contentBySource[$0] = nil
            sourceStatus[$0] = nil
        }
        Task { await publishMergedLists() }
    }

    func setEnabled(_ enabled: Bool, for sourceID: UUID) {
        guard let index = playlistSources.firstIndex(where: { $0.id == sourceID }) else { return }
        playlistSources[index].enabled = enabled
        Task { await publishMergedLists() }
    }

    // MARK: - Yükleme

    func loadAllPlaylists() async {
        let generation = await MainActor.run { () -> Int in
            self.loadGeneration += 1
            self.isLoading = true
            self.loadingSourceID = nil
            self.errorMessage = nil
            return self.loadGeneration
        }

        let sources = await MainActor.run { self.playlistSources.filter { $0.enabled } }
        var fresh: [UUID: SourceContent] = [:]
        var errors: [String] = []
        var statuses: [UUID: SourceStatus] = [:]

        for source in sources {
            let stillCurrent = await MainActor.run { generation == self.loadGeneration }
            if !stillCurrent { return }
            do {
                let content = try await fetchContent(for: source)
                fresh[source.id] = content
                statuses[source.id] = SourceStatus(text: content.summary, isError: false)
            } catch {
                print("[AuroraIPTV][VM] YÜKLEME HATASI (\(source.name)): \(error.localizedDescription)")
                errors.append("\(source.name): \(error.localizedDescription)")
                statuses[source.id] = SourceStatus(text: "Hata: \(error.localizedDescription)", isError: true)
            }
        }

        let stillCurrent = await MainActor.run { () -> Bool in
            guard generation == self.loadGeneration else { return false }
            for (id, content) in fresh { self.contentBySource[id] = content }
            for (id, status) in statuses { self.sourceStatus[id] = status }
            return true
        }
        if !stillCurrent { return }

        await publishMergedLists()
        await MainActor.run {
            guard generation == self.loadGeneration else { return }
            self.errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
            self.isLoading = false
            self.loadingSourceID = nil
        }
    }

    func loadPlaylist(source: PlaylistSource) async {
        let generation = await MainActor.run { () -> Int in
            self.loadGeneration += 1
            self.isLoading = true
            self.loadingSourceID = source.id
            self.errorMessage = nil
            return self.loadGeneration
        }

        var errorText: String?
        var content: SourceContent?
        var status: SourceStatus?
        do {
            let loaded = try await fetchContent(for: source)
            content = loaded
            status = SourceStatus(text: loaded.summary, isError: false)
        } catch {
            status = SourceStatus(text: "Hata: \(error.localizedDescription)", isError: true)
            print("[AuroraIPTV][VM] YÜKLEME HATASI (\(source.name)): \(error.localizedDescription)")
            errorText = "\(source.name): \(error.localizedDescription)"
        }

        let stillCurrent = await MainActor.run { () -> Bool in
            guard generation == self.loadGeneration else { return false }
            if let content = content { self.contentBySource[source.id] = content }
            if let status = status { self.sourceStatus[source.id] = status }
            return true
        }
        if !stillCurrent { return }

        await publishMergedLists()
        await MainActor.run {
            guard generation == self.loadGeneration else { return }
            self.errorMessage = errorText
            self.isLoading = false
            self.loadingSourceID = nil
        }
    }

    func stopAllLoading() {
        DispatchQueue.main.async {
            self.loadGeneration += 1   // süren yüklemelerin sonucu yok sayılır
            print("[AuroraIPTV][VM] Stop: channels=\(self.channels.count), vod=\(self.vodItems.count), series=\(self.seriesItems.count)")
            self.isLoading = false
            self.loadingSourceID = nil
        }
    }

    // MARK: - İçerik çekme

    private func fetchContent(for source: PlaylistSource) async throws -> SourceContent {
        switch source.type {
        case .m3u:
            guard !source.url.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "AuroraIPTV", code: 10, userInfo: [NSLocalizedDescriptionKey: "M3U adresi boş."])
            }
            do {
                return try await fetchM3UContent(for: source)
            } catch {
                // get.php?username=...&password=... biçimindeki adres aslında bir Xtream hesabıdır.
                // M3U indirilemezse (ör. HTTP 520) aynı hesap Xtream API ile yüklenir.
                guard let account = Self.xtreamAccount(fromM3UURL: source.url) else { throw error }
                print("[AuroraIPTV][M3U] \(source.name): M3U alınamadı (\(error.localizedDescription)) — Xtream API deneniyor")
                do {
                    var content = try await fetchXtreamContent(serverURL: account.base, username: account.username,
                                                               password: account.password, sourceName: source.name)
                    content.note = "M3U indirilemedi; aynı hesap Xtream API ile yüklendi."
                    return content
                } catch let apiError {
                    throw NSError(domain: "AuroraIPTV", code: 14, userInfo: [NSLocalizedDescriptionKey:
                        "M3U: \(error.localizedDescription) | Xtream API: \(apiError.localizedDescription)"])
                }
            }

        case .xtream:
            guard !source.serverURL.isEmpty, !source.username.isEmpty, !source.password.isEmpty else {
                throw NSError(domain: "AuroraIPTV", code: 12, userInfo: [NSLocalizedDescriptionKey: "Sunucu, kullanıcı adı veya şifre eksik."])
            }
            return try await fetchXtreamContent(serverURL: source.serverURL, username: source.username,
                                                password: source.password, sourceName: source.name)
        }
    }

    private func fetchM3UContent(for source: PlaylistSource) async throws -> SourceContent {
        let data = try await NetworkService.shared.fetchM3U(from: source.url)
        let parsed = PlaylistParser.parseM3UAll(from: data, sourceName: source.name)
        print("[AuroraIPTV][M3U] \(source.name): \(data.count) bayt indirildi -> kanal=\(parsed.channels.count), film=\(parsed.vod.count), dizi=\(parsed.series.count)")
        let content = SourceContent(channels: parsed.channels, vod: parsed.vod, series: parsed.series)
        if content.isEmpty {
            let preview = String(decoding: data.prefix(120), as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            throw NSError(domain: "AuroraIPTV", code: 11, userInfo: [NSLocalizedDescriptionKey:
                "Listede kanal bulunamadı. Adres doğrudan M3U vermiyor olabilir. Sunucu yanıtının başı: \"\(preview)\""])
        }
        return content
    }

    private func fetchXtreamContent(serverURL: String, username: String, password: String, sourceName: String) async throws -> SourceContent {
        var content = SourceContent()
        var firstError: Error?

        do {
            let live = try await XtreamService.shared.fetchChannelsOnly(serverURL: serverURL, username: username, password: password)
            content.channels = live.map {
                Channel(id: $0.id, name: $0.name, logoURL: $0.logoURL, streamURL: $0.streamURL, group: $0.group, sourceName: sourceName)
            }
        } catch {
            firstError = error
        }

        do {
            let other = try await XtreamService.shared.fetchFromXtream(serverURL: serverURL, username: username, password: password)
            content.vod = other.vod
            content.series = other.series
        } catch {
            if firstError == nil { firstError = error }
        }

        if content.isEmpty {
            if let firstError = firstError { throw firstError }
            throw NSError(domain: "AuroraIPTV", code: 13, userInfo: [NSLocalizedDescriptionKey:
                "Sunucu yanıt verdi ancak içerik listesi boş. Hesap/abonelik ve sunucu adresini kontrol edin."])
        }
        return content
    }

    /// "http://host:port/get.php?username=U&password=P&type=m3u_plus" -> (http://host:port, U, P)
    private static func xtreamAccount(fromM3UURL urlString: String) -> XtreamAccount? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        guard let components = URLComponents(string: trimmed),
              components.path.lowercased().hasSuffix("get.php"),
              let host = components.host,
              let username = components.queryItems?.first(where: { $0.name == "username" })?.value, !username.isEmpty,
              let password = components.queryItems?.first(where: { $0.name == "password" })?.value, !password.isEmpty
        else { return nil }

        let scheme = components.scheme ?? "http"
        let port = components.port.map { ":\($0)" } ?? ""
        return XtreamAccount(base: "\(scheme)://\(host)\(port)", username: username, password: password)
    }

    // MARK: - Birleştirme

    private struct Merged {
        var liveGroups: [CategoryGroup<Channel>]
        var vodGroups: [CategoryGroup<VodItem>]
        var seriesGroups: [CategoryGroup<SeriesItem>]
        var liveKeys: [String: String]
        var vodKeys: [String: String]
        var seriesKeys: [String: String]
    }

    /// Etkin playlist'lerin içeriklerini birleştirir; ağır işler ana thread dışında yapılır.
    private func publishMergedLists() async {
        let snapshot = await MainActor.run { (self.playlistSources, self.contentBySource, self.hideAdult) }
        let merged = Self.merge(sources: snapshot.0, contents: snapshot.1, hideAdult: snapshot.2)
        await MainActor.run {
            self.baseLive = merged.liveGroups
            self.baseVod = merged.vodGroups
            self.baseSeries = merged.seriesGroups
            self.liveKeys = merged.liveKeys
            self.vodKeys = merged.vodKeys
            self.seriesKeys = merged.seriesKeys
        }
        await applySort()
    }

    /// Seçili sıralamayı uygulayıp listeleri yayınlar.
    private func applySort() async {
        let snap = await MainActor.run {
            (self.baseLive, self.baseVod, self.baseSeries, self.liveKeys, self.vodKeys, self.seriesKeys, self.sortMode)
        }
        let live = Self.sort(snap.0, mode: snap.6, keys: snap.3)
        let vod = Self.sort(snap.1, mode: snap.6, keys: snap.4)
        let series = Self.sort(snap.2, mode: snap.6, keys: snap.5)
        await MainActor.run {
            print("[AuroraIPTV][VM] liste: channels=\(live.reduce(0) { $0 + $1.items.count }), vod=\(vod.reduce(0) { $0 + $1.items.count }), series=\(series.reduce(0) { $0 + $1.items.count }), sıralama=\(snap.6.rawValue)")
            self.liveGroups = live
            self.vodGroups = vod
            self.seriesGroups = series
            self.channels = live.flatMap { $0.items }
            self.vodItems = vod.flatMap { $0.items }
            self.seriesItems = series.flatMap { $0.items }
        }
    }

    private static func sort<T: Identifiable>(_ groups: [CategoryGroup<T>], mode: SortMode, keys: [String: String]) -> [CategoryGroup<T>] where T.ID == String {
        guard mode != .recommended else { return groups }
        return groups.map { group in
            let ascending = group.items.sorted { (keys[$0.id] ?? "") < (keys[$1.id] ?? "") }
            return CategoryGroup(name: group.name, items: mode == .az ? ascending : Array(ascending.reversed()), section: group.section)
        }
    }

    private static func merge(sources: [PlaylistSource], contents: [UUID: SourceContent], hideAdult: Bool) -> Merged {
        var allChannels: [Channel] = []
        var allVod: [VodItem] = []
        var allSeries: [SeriesItem] = []

        for source in sources where source.enabled {
            guard let content = contents[source.id] else { continue }
            allChannels.append(contentsOf: content.channels)
            allVod.append(contentsOf: content.vod)
            allSeries.append(contentsOf: content.series)
        }

        if hideAdult {
            var groupCache: [String: Bool] = [:]
            func adultGroup(_ group: String?) -> Bool {
                let key = group ?? ""
                if let cached = groupCache[key] { return cached }
                let value = ContentCategorizer.isAdult(group: group, name: nil)
                groupCache[key] = value
                return value
            }
            // Canlı yayında grup + kanal adı; film/dizide yalnızca grup adı (film adındaki kelimeler yanıltmasın)
            allChannels = allChannels.filter { !adultGroup($0.group) && !ContentCategorizer.isAdult(group: nil, name: $0.name) }
            allVod = allVod.filter { !adultGroup($0.group) }
            allSeries = allSeries.filter { !adultGroup($0.group) }
        }

        let channels = uniqueByID(allChannels)
        let vod = uniqueByID(allVod)
        let series = uniqueByID(allSeries)

        var liveKeys: [String: String] = [:]
        var vodKeys: [String: String] = [:]
        var seriesKeys: [String: String] = [:]
        liveKeys.reserveCapacity(channels.count)
        vodKeys.reserveCapacity(vod.count)
        seriesKeys.reserveCapacity(series.count)
        for item in channels { liveKeys[item.id] = ContentCategorizer.normalize(item.name) }
        for item in vod { vodKeys[item.id] = ContentCategorizer.normalize(item.name) }
        for item in series { seriesKeys[item.id] = ContentCategorizer.normalize(item.name) }

        // Kategorilere ayır: TR başta; canlıda spor türleri ve platformlar, film/dizide platformlar.
        return Merged(liveGroups: ContentCategorizer.liveGroups(channels),
                      vodGroups: ContentCategorizer.vodGroups(vod),
                      seriesGroups: ContentCategorizer.seriesGroups(series),
                      liveKeys: liveKeys, vodKeys: vodKeys, seriesKeys: seriesKeys)
    }

    // MARK: - Arama

    func searchChannels(_ query: String) -> [Channel] {
        Self.filter(channels, keys: liveKeys, query: query, mode: sortMode)
    }

    func searchVod(_ query: String) -> [VodItem] {
        Self.filter(vodItems, keys: vodKeys, query: query, mode: sortMode)
    }

    func searchSeries(_ query: String) -> [SeriesItem] {
        Self.filter(seriesItems, keys: seriesKeys, query: query, mode: sortMode)
    }

    private static func filter<T: Identifiable>(_ items: [T], keys: [String: String], query: String, mode: SortMode) -> [T] where T.ID == String {
        let q = ContentCategorizer.normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var result = items.filter { keys[$0.id]?.contains(q) == true }
        switch mode {
        case .recommended: break
        case .az: result.sort { (keys[$0.id] ?? "") < (keys[$1.id] ?? "") }
        case .za: result.sort { (keys[$0.id] ?? "") > (keys[$1.id] ?? "") }
        }
        return result
    }

    private static func uniqueByID<T: Identifiable>(_ items: [T]) -> [T] where T.ID == String {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Kategori modeli

struct CategoryInfo {
    let label: String
    let tier: Int      // küçük olan üstte
    let order: Int     // aynı tier içinde sıra
    var section: String? = nil   // kenar çubuğunda gösterilen bölüm başlığı (ör. "Türkiye", "Ülkeler")
}

struct CategoryGroup<Item: Identifiable>: Identifiable {
    let name: String
    let items: [Item]
    var section: String? = nil
    var id: String { name }
}

/// Canlı TV, film ve dizileri kategorilere ayırır.
/// Sıralama: TR içerik başta; canlı TV'de spor türleri ve platformlar, film/dizide platformlar.
enum ContentCategorizer {

    // MARK: Anahtar kelime tabloları

    private struct SportType {
        let label: String
        let subs: [String]      // metin içinde geçmesi yeterli
        let words: [String]     // tam kelime olarak geçmeli
        init(_ label: String, subs: [String] = [], words: [String] = []) {
            self.label = label
            self.subs = subs
            self.words = words.map { " \($0) " }
        }
    }

    private static let sportTypes: [SportType] = [
        SportType("Futbol",
                  subs: ["futbol", "football", "soccer"],
                  words: ["super lig", "premier league", "la liga", "laliga", "serie a", "bundesliga", "ligue 1",
                          "champions league", "europa league", "conference league", "uefa", "tff", "lig tv",
                          "fifa", "eredivisie", "libertadores", "copa"]),
        SportType("Basketbol",
                  subs: ["basketbol", "basketball"],
                  words: ["nba", "euroleague", "euro league", "bsl", "bbl"]),
        SportType("Tenis",
                  subs: ["tenis", "tennis"],
                  words: ["atp", "wta", "wimbledon", "roland garros", "us open", "australian open"]),
        SportType("Motor Sporları",
                  subs: ["motogp", "formula", "motorsport", "motor sport", "nascar", "rally"],
                  words: ["f1", "f2", "wrc", "moto gp"]),
        SportType("Dövüş Sporları",
                  subs: ["boxing", "boks", "wrestling", "kickbox"],
                  words: ["ufc", "wwe", "mma", "aew", "fight", "dovus", "glory"]),
        SportType("Voleybol & Hentbol",
                  subs: ["voleybol", "volleyball", "hentbol", "handball"],
                  words: ["cev", "vnl"]),
        SportType("Amerikan Sporları",
                  words: ["nfl", "mlb", "nhl", "ncaa", "mls"]),
        SportType("Golf",
                  subs: ["golf"],
                  words: ["pga"]),
        SportType("Kriket & Rugby",
                  subs: ["cricket", "rugby"],
                  words: ["ipl", "six nations"])
    ]

    private struct Platform {
        let label: String
        let subs: [String]
        let words: [String]
        let live: Bool
        let vod: Bool
        init(_ label: String, subs: [String] = [], words: [String] = [], live: Bool = true, vod: Bool = true) {
            self.label = label
            self.subs = subs
            self.words = words.map { " \($0) " }
            self.live = live
            self.vod = vod
        }
    }

    /// Listedeki sıra, kategori sırasını belirler.
    private static let platforms: [Platform] = [
        Platform("Netflix", subs: ["netflix"]),
        Platform("Disney+", subs: ["disney"]),
        Platform("Amazon Prime", subs: ["amazon", "prime video", "primevideo"], words: ["prime"]),
        Platform("HBO Max", subs: ["hbo"], words: ["max"]),
        Platform("BluTV", subs: ["blutv", "blu tv"]),
        Platform("Exxen", subs: ["exxen"]),
        Platform("Gain", words: ["gain"]),
        Platform("TOD", words: ["tod"]),
        Platform("Tabii", subs: ["tabii"]),
        Platform("Apple TV+", subs: ["apple tv", "appletv"]),
        Platform("Paramount+", subs: ["paramount"]),
        Platform("YouTube", subs: ["youtube"], live: false),
        Platform("Hulu", subs: ["hulu"], live: false),
        Platform("Crunchyroll", subs: ["crunchyroll"], live: false),
        Platform("MUBI", words: ["mubi"], live: false),
        Platform("Peacock", subs: ["peacock"], live: false),
        Platform("TRT", words: ["trt"], live: false),
        // Yalnızca canlı yayın platformları
        Platform("beIN Sports", subs: ["bein"], vod: false),
        Platform("S Sport", subs: ["ssport"], words: ["s sport", "s sport plus"], vod: false),
        Platform("Tivibu", subs: ["tivibu"], vod: false),
        Platform("Digiturk", subs: ["digiturk"], vod: false),
        Platform("Smart Spor", subs: ["smart spor", "smartspor"], vod: false),
        Platform("DAZN", subs: ["dazn"], vod: false),
        Platform("Sky", words: ["sky"], vod: false),
        Platform("Eurosport", subs: ["eurosport"], vod: false)
    ]

    private static let genericSportWords = [" spor ", " sport ", " sports "]
    private static let turkishWords = [" tr ", " trt ", " ulusal ", " yerli "]

    // MARK: Yardımcılar

    /// Küçük harf, aksansız, noktalama yerine tek boşluk; başta ve sonda boşluk (kelime sınırı araması için).
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = " "
        var lastSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        if !lastSpace { out.append(" ") }
        return out
    }

    /// Sağlayıcı grup adındaki oklar/sembolleri temizler: "TR ⟾ HEVC" -> "TR HEVC"
    static func cleanLabel(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+&'.()/"))
        var out = ""
        var lastSpace = true
        for scalar in raw.unicodeScalars {
            if keep.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hasSub(_ text: String, _ subs: [String]) -> Bool {
        for s in subs where text.contains(s) { return true }
        return false
    }

    private static func hasWord(_ text: String, _ paddedWords: [String]) -> Bool {
        for w in paddedWords where text.contains(w) { return true }
        return false
    }

    private static func isTurkish(_ normalized: String) -> Bool {
        hasWord(normalized, turkishWords) || normalized.contains("turk")
    }

    // MARK: Sınıflandırma

    // MARK: Canlı TV: TR başta (kendi içinde Spor/Haber/Film…), sonra yabancı Spor/Haber/Film, sonra ülkeler

    private static let sportsExtraSubs = ["bein", "ssport", "eurosport", "dazn", "smart spor", "smartspor",
                                          "espn", "supersport", "tivibu spor", "exxen spor",
                                          "deporte", "calcio", "futebol", "fussball", "sportif"]
    private static let sportsExtraWords = [" s sport ", " a spor ", " trt spor ", " ht spor ", " nba tv "]
    private static let newsSubs = ["haber", "euronews", "al jazeera", "aljazeera",
                                   "noticias", "nachrichten", "actualites", "notizie", "nieuws"]
    private static let newsWords = [" news ", " cnn ", " bbc ", " ntv ", " tgrt ", " halk tv ", " sozcu ", " tele1 "]
    private static let filmSubs = ["sinema", "cinema", "movie", "film", "dizi", "yesilcam", "cinemax"]
    private static let filmWords = [" series ", " hbo ", " starz ", " kino ", " vod ", " showtime ", " cine ", " filme "]

    // MARK: Yetişkin içerik filtresi

    private static let adultSubs = ["adult", "xxx", "porn", "erotik", "erotic", "yetiskin", "hentai",
                                    "playboy", "brazzers", "hustler", "dorcel", "penthouse", "sextreme", "redlight"]
    private static let adultWords = [" sex ", " 18 ", " 18plus ", " sexy ", " nude "]

    /// Grup ve/veya ad yetişkin içeriğe işaret ediyorsa true ("Adult Swim" gibi çizgi film bloğu hariç).
    static func isAdult(group: String?, name: String?) -> Bool {
        var text = ""
        if let group = group { text += normalize(group) }
        if let name = name { text += normalize(name) }
        if text.isEmpty { return false }
        text = text.replacingOccurrences(of: "adult swim", with: " ")
        return hasSub(text, adultSubs) || hasWord(text, adultWords)
    }

    /// UHD/4K/HEVC kanallar önce VLC ile (ham TS) açılır; yerleşik oynatıcı bu akışlarda sık takılır.
    static func prefersVLC(group: String?, name: String?) -> Bool {
        var text = ""
        if let group = group { text += normalize(group) }
        if let name = name { text += normalize(name) }
        return hasWord(text, [" uhd ", " 4k ", " hevc ", " h265 ", " 2160p ", " 2160 "])
    }

    // MARK: TR spor kanallarının platformlara göre ayrımı

    private static let trSportsPlatforms: [(label: String, subs: [String], words: [String])] = [
        ("TR TRT SPOR", ["trt spor"], []),
        ("TR S SPORT", ["ssport"], [" s sport "]),
        ("TR TİVİBU SPOR", ["tivibu"], []),
        ("TR EXXEN SPOR", ["exxen"], []),
        ("TR SMART SPOR", ["smart spor", "smartspor"], []),
        ("TR A SPOR", [], [" a spor "]),
        ("TR EUROSPORT", ["eurosport"], [])
    ]

    /// Kanal adı (sonra grup adı) bir spor platformuna işaret ediyorsa kanonik etiketini döndürür.
    private static func trPlatformLabel(rawName: String, rawGroup: String?, g: String, n: String) -> String? {
        let plus = rawName.contains("+") || (rawGroup ?? "").contains("+")
            || hasWord(n, [" plus ", " max ", " feed "]) || hasSub(g, ["feed"])
        for text in [n, g] {
            if hasSub(text, ["bein"]) {
                return plus ? "TR beIN FEED / P+" : "TR beIN SPORTS"
            }
            for platform in trSportsPlatforms where hasSub(text, platform.subs) || hasWord(text, platform.words) {
                return platform.label
            }
        }
        return nil
    }

    /// TR kanallarının Spor/Haber/Film dışındaki türleri (sıra numarası kenar çubuğundaki sırayı belirler)
    private static let trOtherGenres: [(label: String, order: Int, subs: [String])] = [
        ("Belgesel", 10, ["belgesel", "documentary", "dokuman"]),
        ("Çocuk", 11, ["cocuk", " kids ", "cartoon", "cizgi", "animation"]),
        ("Dini", 12, [" dini ", "religio"]),
        ("Yerel", 13, ["yerel", "local", "bolgesel"]),
        ("Müzik", 14, ["muzik", "music"]),
        ("Radyo", 15, [" radyo ", " radio "]),
        ("Eğlence", 16, ["eglence", "entertainment", " yasam ", "lifestyle"])
    ]

    private struct Country {
        let name: String
        let codes: [String]
        let subs: [String]
        init(_ name: String, _ codes: [String], _ subs: [String]) {
            self.name = name
            self.codes = codes
            self.subs = subs
        }
    }

    private static let countries: [Country] = [
        Country("Almanya", ["de", "ger"], ["german", "deutsch", "almanya"]),
        Country("İngiltere", ["uk", "gb"], ["united kingdom", "british", "england", "ingiltere"]),
        Country("ABD", ["us", "usa"], ["america", " abd "]),
        Country("Fransa", ["fr"], ["france", "french", "fransa"]),
        Country("İtalya", ["it"], ["italy", "italia", "italyan"]),
        Country("İspanya", ["es"], ["spain", "spanish", "espana", "ispanya"]),
        Country("Portekiz", ["pt"], ["portug"]),
        Country("Hollanda", ["nl"], ["dutch", "nether", "holland", "hollanda"]),
        Country("Belçika", ["be"], ["belgi", "belcika"]),
        Country("Avusturya", ["at"], ["austria", "avusturya"]),
        Country("İsviçre", ["ch"], ["switz", "swiss", "isvicre"]),
        Country("Polonya", ["pl"], ["poland", "polish", "polonya"]),
        Country("Rusya", ["ru"], ["russia", "rusya"]),
        Country("Ukrayna", ["ua"], ["ukrain"]),
        Country("Romanya", ["ro"], ["romania", "romanya"]),
        Country("Bulgaristan", ["bg"], ["bulgar"]),
        Country("Yunanistan", ["gr"], ["greece", "greek", "yunan"]),
        Country("Sırbistan", ["rs", "srb"], ["serb", "sirb"]),
        Country("Hırvatistan", ["hr"], ["croat", "hirvat"]),
        Country("Bosna Hersek", ["ba"], ["bosn"]),
        Country("Arnavutluk", ["al"], ["albania", "arnavut"]),
        Country("Kosova", ["xk", "ks"], ["kosov"]),
        Country("Makedonya", ["mk"], ["macedon", "makedon"]),
        Country("Azerbaycan", ["az"], ["azerb"]),
        Country("Gürcistan", ["ge"], ["georgia", "gurcistan"]),
        Country("Kazakistan", ["kz"], ["kazak"]),
        Country("Arap Ülkeleri", ["ar", "sa", "ae", "eg", "iq", "sy", "lb", "jo", "kw", "qa", "ma", "dz", "tn"], ["arab", "arap"]),
        Country("İran", ["ir"], ["iran", "persian", "farsi"]),
        Country("İsrail", ["il"], ["israel"]),
        Country("Hindistan", ["in"], ["india", "hindi"]),
        Country("Pakistan", ["pk"], ["pakist"]),
        Country("Çin", ["cn"], ["china", "chinese"]),
        Country("Japonya", ["jp"], ["japan"]),
        Country("Güney Kore", ["kr"], ["korea"]),
        Country("Brezilya", ["br"], ["brazil", "brasil"]),
        Country("Meksika", ["mx"], ["mexic"]),
        Country("Kanada", ["ca"], ["canada"]),
        Country("Avustralya", ["au"], ["austral"]),
        Country("İsveç", ["se"], ["swed"]),
        Country("Danimarka", ["dk"], ["denmark", "danish"]),
        Country("Finlandiya", ["fi"], ["finland", "finnish"]),
        Country("Çekya", ["cz"], ["czech"]),
        Country("Slovakya", ["sk"], ["slovak"]),
        Country("Macaristan", ["hu"], ["hungar"]),
        Country("Slovenya", ["si"], ["sloven"]),
        Country("İrlanda", ["ie"], ["ireland", "irish"]),
        Country("Kıbrıs", ["cy"], ["cyprus", "kibris"]),
        Country("Afganistan", ["af"], ["afghan"]),
        Country("Kürtçe", [], ["kurd", "kurt"]),
        Country("Balkanlar", [], ["balkan", "exyu", "ex yu"])
    ]

    private static func detectCountry(_ g: String) -> String? {
        // 1) Grup adının ilk kelimesi ülke kodu: "DE ⟾ Sport", "|UK| News", "[FR] Cinema"
        let trimmed = g.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.split(separator: " ").first.map(String.init) {
            for country in countries where country.codes.contains(first) { return country.name }
        }
        // 2) Grup adında ülke / dil adı geçiyor
        for country in countries where hasSub(g, country.subs) { return country.name }
        return nil
    }

    private static func isSportsText(_ text: String) -> Bool {
        for t in sportTypes where hasSub(text, t.subs) || hasWord(text, t.words) { return true }
        return hasSub(text, sportsExtraSubs) || hasWord(text, sportsExtraWords) || hasWord(text, genericSportWords)
    }

    /// TR grupları: sağlayıcının kendi grup adı kategori olur; sıra örnekteki gibidir:
    /// HEVC, ULUSAL, UHD, beIN SPORTS, beIN FEED / P+, S SPORT, SPOR, HABER, SİNEMA & DİZİ…, BELGESEL, ÇOCUK, DİNİ, YEREL, MÜZİK…
    /// Aynı sıradaki gruplar sağlayıcının kendi (ilk görünme) sırasını korur.
    private static func trGroupCategory(rawGroup: String?, rawName: String, g: String, n: String, seq: Int) -> CategoryInfo {
        let base = cleanLabel(rawGroup) ?? "TR Diğer"
        func info(_ label: String, _ rank: Int) -> CategoryInfo {
            CategoryInfo(label: label, tier: 0, order: rank * 100_000 + seq, section: "Türkiye")
        }

        if hasSub(g, ["hevc"]) { return info(base, 0) }
        if hasSub(g, ["ulusal"]) { return info(base, 1) }
        if hasWord(g, [" uhd ", " 4k "]) { return info(base, 2) }
        if hasSub(g, ["bein"]) {
            let feed = hasSub(g, ["feed"]) || (rawGroup ?? "").contains("+") || hasWord(g, [" plus ", " max "])
            return info(base, feed ? 4 : 3)
        }
        if hasSub(g, ["ssport"]) || hasWord(g, [" s sport "]) { return info(base, 5) }
        if isSportsText(g) {
            // Genel spor grubu: kanal adına göre platform ayrımı (TRT Spor, Tivibu Spor…)
            if let label = trPlatformLabel(rawName: rawName, rawGroup: rawGroup, g: "", n: n) { return info(label, 6) }
            return info(base, 6)
        }
        if hasSub(g, newsSubs) || hasWord(g, newsWords) { return info(base, 8) }
        if hasSub(g, filmSubs) || hasWord(g, filmWords)
            || hasSub(g, ["netflix", "trflix", "salon", "tabii"])
            || hasWord(g, [" 7 24 ", " gain ", " exxen ", " tod ", " disney "]) { return info(base, 9) }
        for genre in trOtherGenres where hasSub(g, genre.subs) { return info(base, genre.order) }
        return info(base, 20)
    }

    private static func classifyLive(rawGroup: String?, rawName: String, g: String, n: String, seq: Int) -> (info: CategoryInfo, tr: Bool) {
        // Grup adı Türkçe ise: sağlayıcının TR grupları
        if isTurkish(g) {
            return (trGroupCategory(rawGroup: rawGroup, rawName: rawName, g: g, n: n, seq: seq), true)
        }

        let both = g + n
        let tr = isTurkish(n)
        let sports = isSportsText(both)
        let news = !sports && (hasSub(both, newsSubs) || hasWord(both, newsWords))
        let film = !sports && !news && (hasSub(both, filmSubs) || hasWord(both, filmWords))

        // Grup adı bilgi vermiyor ama kanal adı Türkçe (ör. "TR: Show TV"): ad üzerinden TR kategorisi
        if tr {
            func info(_ label: String, _ rank: Int) -> CategoryInfo {
                CategoryInfo(label: label, tier: 0, order: rank * 100_000 + seq, section: "Türkiye")
            }
            if sports {
                return (info(trPlatformLabel(rawName: rawName, rawGroup: rawGroup, g: g, n: n) ?? "TR SPOR", 6), tr)
            }
            if news { return (info("TR HABER", 8), tr) }
            if film { return (info("TR SİNEMA & DİZİ", 9), tr) }
            for genre in trOtherGenres where hasSub(both, genre.subs) {
                return (info("TR \(genre.label.uppercased(with: Locale(identifier: "tr_TR")))", genre.order), tr)
            }
            return (info(cleanLabel(rawGroup) ?? "TR Diğer", 20), tr)
        }

        // Yabancı kanallar: grup adı spor/haber/film ise sağlayıcının grup adı kategori olur;
        // yalnızca kanal adından anlaşılıyorsa genel "Yabancı ..." kategorisi kullanılır.
        func foreign(_ rank: Int, section: String, groupMatched: Bool, fallback: String) -> CategoryInfo {
            let label = groupMatched ? (cleanLabel(rawGroup) ?? fallback) : fallback
            return CategoryInfo(label: label, tier: 1, order: rank * 100_000 + seq, section: section)
        }
        if sports {
            return (foreign(0, section: "Spor", groupMatched: isSportsText(g), fallback: "Yabancı Spor"), tr)
        }
        if news {
            return (foreign(1, section: "Haber", groupMatched: hasSub(g, newsSubs) || hasWord(g, newsWords), fallback: "Yabancı Haber"), tr)
        }
        if film {
            return (foreign(2, section: "Film & Dizi", groupMatched: hasSub(g, filmSubs) || hasWord(g, filmWords), fallback: "Yabancı Film & Dizi"), tr)
        }

        // Kalanlar ülkelere göre (A-Z), tanınmayanlar "Diğer"
        let country = detectCountry(g) ?? "Diğer"
        return (CategoryInfo(label: country, tier: 2, order: country == "Diğer" ? 99 : 0, section: "Ülkeler"), tr)
    }

    /// Film/dizi yalnızca grup adına göre sınıflanır (film adındaki "Max" gibi kelimeler yanıltmasın).
    private static func classifyVod(rawGroup: String?, g: String) -> CategoryInfo {
        let tr = isTurkish(g)
        for (i, p) in platforms.enumerated() where p.vod && (hasSub(g, p.subs) || hasWord(g, p.words)) {
            return CategoryInfo(label: tr ? "TR • \(p.label)" : p.label, tier: tr ? 0 : 2, order: i)
        }
        let label = cleanLabel(rawGroup) ?? (tr ? "TR • Diğer" : "Diğer")
        return CategoryInfo(label: label, tier: tr ? 1 : 3, order: 0)
    }

    // MARK: Gruplama

    private struct Bucket<T> {
        var info: CategoryInfo
        var items: [(item: T, tr: Bool)]
    }

    private static func assemble<T: Identifiable>(_ entries: [(item: T, info: CategoryInfo, tr: Bool)],
                                                  trFirst: Bool,
                                                  keepOrder: Bool = false,
                                                  name: (T) -> String) -> [CategoryGroup<T>] {
        var buckets: [String: Bucket<T>] = [:]
        for entry in entries {
            if buckets[entry.info.label] == nil {
                buckets[entry.info.label] = Bucket(info: entry.info, items: [])
            }
            buckets[entry.info.label]!.items.append((item: entry.item, tr: entry.tr))
        }

        let ordered = buckets.values.sorted { a, b in
            if a.info.tier != b.info.tier { return a.info.tier < b.info.tier }
            if a.info.order != b.info.order { return a.info.order < b.info.order }
            return a.info.label.lowercased() < b.info.label.lowercased()
        }

        return ordered.map { bucket in
            if keepOrder {
                // Sağlayıcının kendi sırası korunur
                return CategoryGroup(name: bucket.info.label, items: bucket.items.map { $0.item }, section: bucket.info.section)
            }
            let sorted = bucket.items.sorted { x, y in
                if trFirst && x.tr != y.tr { return x.tr }
                return name(x.item).lowercased() < name(y.item).lowercased()
            }
            return CategoryGroup(name: bucket.info.label, items: sorted.map { $0.item }, section: bucket.info.section)
        }
    }

    static func liveGroups(_ channels: [Channel]) -> [CategoryGroup<Channel>] {
        var groupCache: [String: String] = [:]
        var entries: [(item: Channel, info: CategoryInfo, tr: Bool)] = []
        entries.reserveCapacity(channels.count)

        for (index, channel) in channels.enumerated() {
            let key = channel.group ?? ""
            let g: String
            if let cached = groupCache[key] {
                g = cached
            } else {
                g = normalize(key)
                groupCache[key] = g
            }
            let result = classifyLive(rawGroup: channel.group, rawName: channel.name, g: g, n: normalize(channel.name), seq: min(index, 99_999))
            entries.append((item: channel, info: result.info, tr: result.tr))
        }
        return assemble(entries, trFirst: false, keepOrder: true) { $0.name }
    }

    private static func vodInfoCache<T>(_ items: [T], group: (T) -> String?) -> [(item: T, info: CategoryInfo, tr: Bool)] {
        var cache: [String: CategoryInfo] = [:]
        var entries: [(item: T, info: CategoryInfo, tr: Bool)] = []
        entries.reserveCapacity(items.count)
        for item in items {
            let raw = group(item)
            let key = raw ?? ""
            let info: CategoryInfo
            if let cached = cache[key] {
                info = cached
            } else {
                info = classifyVod(rawGroup: raw, g: normalize(key))
                cache[key] = info
            }
            entries.append((item: item, info: info, tr: info.tier <= 1))
        }
        return entries
    }

    static func vodGroups(_ items: [VodItem]) -> [CategoryGroup<VodItem>] {
        assemble(vodInfoCache(items) { $0.group }, trFirst: false) { $0.name }
    }

    static func seriesGroups(_ items: [SeriesItem]) -> [CategoryGroup<SeriesItem>] {
        assemble(vodInfoCache(items) { $0.group }, trFirst: false) { $0.name }
    }
}


// MARK: - Sıralama

enum SortMode: String, CaseIterable, Identifiable {
    case recommended
    case az
    case za

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Önerilen (TR başta)"
        case .az: return "A → Z"
        case .za: return "Z → A"
        }
    }

    var shortTitle: String {
        switch self {
        case .recommended: return "Önerilen"
        case .az: return "A → Z"
        case .za: return "Z → A"
        }
    }

    /// Kumandada tek tuşla sıradaki moda geçmek için
    var next: SortMode {
        switch self {
        case .recommended: return .az
        case .az: return .za
        case .za: return .recommended
        }
    }
}

// MARK: - Favoriler ve son izlenenler

enum LibraryKind: String, Codable {
    case live, movie, series, episode

    var title: String {
        switch self {
        case .live: return "Canlı TV"
        case .movie: return "Film"
        case .series: return "Dizi"
        case .episode: return "Dizi bölümü"
        }
    }

    var icon: String {
        switch self {
        case .live: return "tv"
        case .movie: return "film"
        case .series, .episode: return "play.rectangle"
        }
    }
}

/// Favori veya geçmiş kaydı. İçerik anlık görüntüsüyle saklanır; playlist yüklü olmasa da oynatılabilir.
struct LibraryEntry: Identifiable, Codable, Hashable {
    var id: String
    var kind: LibraryKind
    var refID: String
    var name: String
    var imageURL: String?
    var streamURL: String?
    var group: String?
    var seriesID: String?
    var account: XtreamAccount?
    var date: Date
}

extension LibraryEntry {
    static func key(channel: Channel) -> String { "live|" + (channel.streamURL ?? channel.id) }
    static func key(vod: VodItem) -> String { "movie|" + (vod.streamURL ?? vod.id) }
    static func key(series: SeriesItem) -> String {
        if let seriesID = series.seriesID, let account = series.account {
            return "series|\(account.base)|\(seriesID)"
        }
        return "series|" + (series.streamURL ?? series.id)
    }

    init(channel: Channel) {
        self.init(id: Self.key(channel: channel), kind: .live, refID: channel.id, name: channel.name,
                  imageURL: channel.logoURL, streamURL: channel.streamURL, group: channel.group,
                  seriesID: nil, account: nil, date: Date())
    }

    init(vod: VodItem) {
        self.init(id: Self.key(vod: vod), kind: .movie, refID: vod.id, name: vod.name,
                  imageURL: vod.posterURL, streamURL: vod.streamURL, group: vod.group,
                  seriesID: nil, account: nil, date: Date())
    }

    init(series: SeriesItem) {
        self.init(id: Self.key(series: series), kind: .series, refID: series.id, name: series.name,
                  imageURL: series.posterURL, streamURL: series.streamURL, group: series.group,
                  seriesID: series.seriesID, account: series.account, date: Date())
    }

    init(episode: Episode, series: SeriesItem) {
        self.init(id: "episode|" + episode.streamURL, kind: .episode, refID: episode.id,
                  name: "\(series.name) • S\(episode.season) B\(episode.number)",
                  imageURL: episode.imageURL ?? series.posterURL, streamURL: episode.streamURL,
                  group: series.group, seriesID: nil, account: nil, date: Date())
    }

    /// M3U'dan gelen, doğrudan oynatılabilir dizi öğesi
    init(playableSeries series: SeriesItem) {
        self.init(id: "episode|" + (series.streamURL ?? series.id), kind: .episode, refID: series.id,
                  name: series.name, imageURL: series.posterURL, streamURL: series.streamURL,
                  group: series.group, seriesID: nil, account: nil, date: Date())
    }

    var asChannel: Channel {
        Channel(id: "fav|" + refID, name: name, logoURL: imageURL, streamURL: streamURL, group: group)
    }

    var asVod: VodItem {
        VodItem(id: "fav|" + refID, name: name, posterURL: imageURL, streamURL: streamURL, group: group, containerExtension: nil)
    }

    var asSeries: SeriesItem {
        SeriesItem(id: "fav|" + refID, name: name, posterURL: imageURL, group: group,
                   seriesID: seriesID, account: account, streamURL: streamURL)
    }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [LibraryEntry] = []
    @Published private(set) var history: [LibraryEntry] = []

    private var favoriteIDs: Set<String> = []
    private let favoritesKey = "library.favorites.v1"
    private let historyKey = "library.history.v1"
    private let historyLimit = 40
    private let favoritesLimit = 300

    init() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([LibraryEntry].self, from: data) {
            favorites = decoded
            favoriteIDs = Set(decoded.map { $0.id })
        }
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([LibraryEntry].self, from: data) {
            history = decoded
        }
    }

    func isFavorite(_ key: String) -> Bool {
        favoriteIDs.contains(key)
    }

    func toggleFavorite(_ entry: LibraryEntry) {
        if favoriteIDs.contains(entry.id) {
            favorites.removeAll { $0.id == entry.id }
            favoriteIDs.remove(entry.id)
        } else {
            var added = entry
            added.date = Date()
            favorites.insert(added, at: 0)
            favoriteIDs.insert(added.id)
            // tvOS'ta UserDefaults ~500 KB ile sınırlıdır; en eski favoriler elenir.
            if favorites.count > favoritesLimit {
                let removed = favorites.suffix(favorites.count - favoritesLimit)
                favoriteIDs.subtract(removed.map { $0.id })
                favorites = Array(favorites.prefix(favoritesLimit))
            }
        }
        saveFavorites()
    }

    func removeFavorites(ids: [String]) {
        favorites.removeAll { ids.contains($0.id) }
        favoriteIDs.subtract(ids)
        saveFavorites()
    }

    func recordPlay(_ entry: LibraryEntry) {
        var played = entry
        played.date = Date()
        history.removeAll { $0.id == played.id }
        history.insert(played, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        saveHistory()
    }

    func removeHistory(ids: [String]) {
        history.removeAll { ids.contains($0.id) }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func historyChannels() -> [Channel] { history.filter { $0.kind == .live }.map { $0.asChannel } }
    func historyVod() -> [VodItem] { history.filter { $0.kind == .movie }.map { $0.asVod } }

    func favoriteChannels() -> [Channel] { favorites.filter { $0.kind == .live }.map { $0.asChannel } }
    func favoriteVod() -> [VodItem] { favorites.filter { $0.kind == .movie }.map { $0.asVod } }
    func favoriteSeries() -> [SeriesItem] { favorites.filter { $0.kind == .series }.map { $0.asSeries } }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}
