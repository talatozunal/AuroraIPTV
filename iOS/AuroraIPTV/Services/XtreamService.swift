import Foundation

final class XtreamService {
    static let shared = XtreamService()
    private init() {}

    // MARK: - Yardımcılar

    private func normalizedBaseURL(_ serverURL: String) throws -> String {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        guard let url = URL(string: value), url.host != nil else { throw URLError(.badURL) }
        return value
    }

    private func apiURL(base: String, username: String, password: String, action: String, extra: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base + "/player_api.php") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action)
        ] + extra
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func fetchJSON(base: String, username: String, password: String, action: String, extra: [URLQueryItem] = []) async throws -> Any {
        let url = try apiURL(base: base, username: username, password: password, action: action, extra: extra)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17.6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "AuroraIPTV.Xtream", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Sunucu HTTP \(http.statusCode) yanıtı verdi."])
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("[AuroraIPTV][Xtream] \(action) raw start: \(String(raw.prefix(120)))")
        }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    private func fetchArray(base: String, username: String, password: String, action: String) async throws -> [[String: Any]] {
        let object = try await fetchJSON(base: base, username: username, password: password, action: action)
        if let array = object as? [[String: Any]] {
            return array
        }
        if let array = object as? [Any], array.isEmpty {
            return []
        }
        if object is [String: Any] {
            throw NSError(domain: "AuroraIPTV.Xtream", code: 2, userInfo: [NSLocalizedDescriptionKey: "Xtream API (\(action)) array bekleniyordu, farklı format döndü. Hesap/abonelik veya giriş bilgileri hatalı olabilir."])
        }
        throw NSError(domain: "AuroraIPTV.Xtream", code: 1, userInfo: [NSLocalizedDescriptionKey: "Xtream API beklenen listeyi döndürmedi. Sunucu adresi veya giriş bilgileri hatalı olabilir."])
    }

    private func categoryMap(base: String, username: String, password: String, action: String) async -> [String: String] {
        guard let items = try? await fetchArray(base: base, username: username, password: password, action: action) else { return [:] }
        var map: [String: String] = [:]
        for item in items {
            if let id = stringValue(item["category_id"]), let name = stringValue(item["category_name"]) {
                map[id] = name
            }
        }
        return map
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private func streamPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? value
    }

    // MARK: - Canlı yayın

    func fetchChannelsOnly(serverURL: String, username: String, password: String) async throws -> [Channel] {
        let base = try normalizedBaseURL(serverURL)
        let categoryNames = await categoryMap(base: base, username: username, password: password, action: "get_live_categories")

        let items = try await fetchArray(base: base, username: username, password: password, action: "get_live_streams")
        print("[AuroraIPTV][Xtream] get_live_streams count: \(items.count)")
        let safeUser = streamPathComponent(username)
        let safePassword = streamPathComponent(password)
        return items.compactMap { item in
            guard let streamID = stringValue(item["stream_id"]), !streamID.isEmpty else { return nil }
            let name = stringValue(item["name"]) ?? "İsimsiz Kanal"
            let logo = stringValue(item["stream_icon"])
            let categoryID = stringValue(item["category_id"])
            let group = stringValue(item["category_name"]) ?? (categoryID.flatMap { categoryNames[$0] })
            // ÖNEMLİ: AVPlayer ham .ts yayınını oynatamaz (siyah ekran). HLS (.m3u8) kullanılmalı.
            let streamURL = "\(base)/live/\(safeUser)/\(safePassword)/\(streamID).m3u8"
            return Channel(id: "\(base)|live|\(streamID)", name: name, logoURL: logo, streamURL: streamURL, group: group)
        }
    }

    // MARK: - Film + Dizi listesi

    func fetchFromXtream(serverURL: String, username: String, password: String) async throws -> (data: Data, vod: [VodItem], series: [SeriesItem]) {
        let base = try normalizedBaseURL(serverURL)
        let safeUser = streamPathComponent(username)
        let safePassword = streamPathComponent(password)
        let account = XtreamAccount(base: base, username: username, password: password)

        var vodItems: [VodItem] = []
        var seriesItems: [SeriesItem] = []
        var firstError: Error?

        // Film
        do {
            let vodCategories = await categoryMap(base: base, username: username, password: password, action: "get_vod_categories")
            let vodJSON = try await fetchArray(base: base, username: username, password: password, action: "get_vod_streams")
            print("[AuroraIPTV][Xtream] get_vod_streams count: \(vodJSON.count)")
            vodItems = vodJSON.compactMap { item -> VodItem? in
                guard let id = stringValue(item["stream_id"]), !id.isEmpty else { return nil }
                let name = stringValue(item["name"]) ?? "İsimsiz Film"
                let cover = stringValue(item["stream_icon"])
                let ext = (stringValue(item["container_extension"]) ?? "mp4").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let categoryID = stringValue(item["category_id"])
                let group = stringValue(item["category_name"]) ?? categoryID.flatMap { vodCategories[$0] }
                let url = "\(base)/movie/\(safeUser)/\(safePassword)/\(id).\(ext.isEmpty ? "mp4" : ext)"
                return VodItem(id: "\(base)|vod|\(id)", name: name, posterURL: cover, streamURL: url, group: group, containerExtension: ext)
            }
        } catch {
            firstError = error
            print("[AuroraIPTV][Xtream] Film listesi alınamadı: \(error.localizedDescription)")
        }

        // Dizi
        do {
            let seriesCategories = await categoryMap(base: base, username: username, password: password, action: "get_series_categories")
            let seriesJSON = try await fetchArray(base: base, username: username, password: password, action: "get_series")
            print("[AuroraIPTV][Xtream] get_series count: \(seriesJSON.count)")
            seriesItems = seriesJSON.compactMap { item -> SeriesItem? in
                guard let seriesID = stringValue(item["series_id"]), !seriesID.isEmpty else { return nil }
                let name = stringValue(item["name"]) ?? "İsimsiz Dizi"
                let categoryID = stringValue(item["category_id"])
                let group = stringValue(item["category_name"]) ?? categoryID.flatMap { seriesCategories[$0] }
                let year = stringValue(item["year"]) ?? stringValue(item["releaseDate"]).map { String($0.prefix(4)) }
                return SeriesItem(id: "\(base)|series|\(seriesID)",
                                  name: name,
                                  posterURL: stringValue(item["cover"]),
                                  plot: stringValue(item["plot"]),
                                  year: year,
                                  group: group,
                                  seriesID: seriesID,
                                  account: account)
            }
        } catch {
            if firstError == nil { firstError = error }
            print("[AuroraIPTV][Xtream] Dizi listesi alınamadı: \(error.localizedDescription)")
        }

        // Her ikisi de başarısızsa hatayı yukarı ilet; biri başarılıysa o kadarını göster.
        if vodItems.isEmpty && seriesItems.isEmpty, let firstError = firstError {
            throw firstError
        }
        return (Data(), vodItems, seriesItems)
    }

    // MARK: - Dizi detayı (sezon / bölümler)

    func fetchSeriesDetail(account: XtreamAccount, seriesID: String) async throws -> SeriesDetail {
        let object = try await fetchJSON(base: account.base,
                                         username: account.username,
                                         password: account.password,
                                         action: "get_series_info",
                                         extra: [URLQueryItem(name: "series_id", value: seriesID)])
        guard let root = object as? [String: Any] else {
            throw NSError(domain: "AuroraIPTV.Xtream", code: 3, userInfo: [NSLocalizedDescriptionKey: "Dizi bilgisi beklenen biçimde gelmedi."])
        }

        let info = root["info"] as? [String: Any]
        let plot = stringValue(info?["plot"])
        let safeUser = streamPathComponent(account.username)
        let safePassword = streamPathComponent(account.password)

        var episodes: [Episode] = []

        func parse(_ list: [[String: Any]], fallbackSeason: Int) {
            for (index, ep) in list.enumerated() {
                guard let epID = stringValue(ep["id"]) else { continue }
                let season = intValue(ep["season"]) ?? fallbackSeason
                let number = intValue(ep["episode_num"]) ?? (index + 1)
                let title = stringValue(ep["title"]) ?? "Bölüm \(number)"
                let ext = (stringValue(ep["container_extension"]) ?? "mp4").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let epInfo = ep["info"] as? [String: Any]
                let url = "\(account.base)/series/\(safeUser)/\(safePassword)/\(epID).\(ext.isEmpty ? "mp4" : ext)"
                episodes.append(Episode(id: "\(seriesID)|\(epID)",
                                        season: season,
                                        number: number,
                                        title: title,
                                        streamURL: url,
                                        imageURL: stringValue(epInfo?["movie_image"]),
                                        plot: stringValue(epInfo?["plot"]),
                                        duration: stringValue(epInfo?["duration"])))
            }
        }

        if let dict = root["episodes"] as? [String: Any] {
            for (key, value) in dict {
                if let list = value as? [[String: Any]] {
                    parse(list, fallbackSeason: Int(key) ?? 0)
                }
            }
        } else if let array = root["episodes"] as? [Any] {
            // Bazı paneller sezonları dict yerine dizi olarak döndürür
            for (index, value) in array.enumerated() {
                if let list = value as? [[String: Any]] {
                    parse(list, fallbackSeason: index + 1)
                }
            }
        }

        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }
        return SeriesDetail(plot: plot, episodes: episodes)
    }
}
