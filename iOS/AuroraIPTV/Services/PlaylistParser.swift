import Foundation

final class PlaylistParser {
    private static func decodeText(_ data: Data) -> String? {
        // UTF-16 yalnızca BOM varsa denenir; aksi halde rastgele baytlar "başarıyla" çözülüp çöp üretiyordu.
        if data.count >= 2 {
            let b0 = data[data.startIndex]
            let b1 = data[data.startIndex + 1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF),
               let text = String(data: data, encoding: .utf16) {
                return text
            }
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1254)
            ?? String(data: data, encoding: .isoLatin1)
        return text?.replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:^|\\s)\(escaped)=\\\"([^\\\"]*)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    private static func name(from extinf: String) -> String {
        guard let comma = extinf.firstIndex(of: ",") else { return "Bilinmeyen Kanal" }
        let value = extinf[extinf.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Bilinmeyen Kanal" : value
    }

    static func parseM3U(from data: Data, sourceName: String = "") -> [Channel] {
        guard let content = decodeText(data) else { return [] }
        var channels: [Channel] = []
        var currentExtInf: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("#EXTINF:") {
                currentExtInf = line
                continue
            }
            if line.hasPrefix("#") { continue }

            // A stream URL belongs to the preceding EXTINF record.
            guard line.contains("://") else {
                currentExtInf = nil
                continue
            }

            if let extinf = currentExtInf {
                let channelName = name(from: extinf)
                channels.append(Channel(
                    name: channelName,
                    logoURL: attribute("tvg-logo", in: extinf),
                    streamURL: line,
                    group: attribute("group-title", in: extinf),
                    epgID: attribute("tvg-id", in: extinf),
                    sourceName: sourceName
                ))
                currentExtInf = nil
            } else {
                // Also tolerate simple playlists containing bare stream URLs.
                channels.append(Channel(name: line, streamURL: line, sourceName: sourceName))
            }
        }
        return channels
    }

    static func parseVodAndSeries(from data: Data) -> (vod: [VodItem], series: [SeriesItem]) {
        guard let content = decodeText(data) else { return ([], []) }
        var vodItems: [VodItem] = []
        var seriesItems: [SeriesItem] = []
        var currentExtInf: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.uppercased().hasPrefix("#EXTINF:") { currentExtInf = line; continue }
            if line.hasPrefix("#") { continue }
            guard let extinf = currentExtInf else { continue }

            let itemName = name(from: extinf)
            let logo = attribute("tvg-logo", in: extinf)
            let group = attribute("group-title", in: extinf)
            let groupLower = (group ?? "").lowercased()
            let nameLower = itemName.lowercased()
            if groupLower.contains("film") || groupLower.contains("movie") || groupLower.contains("vod") {
                vodItems.append(VodItem(name: itemName, posterURL: logo, streamURL: line, group: group))
            } else if groupLower.contains("dizi") || groupLower.contains("serie") || groupLower.contains("series") {
                seriesItems.append(SeriesItem(name: itemName, posterURL: logo, group: group, streamURL: line))
            } else if [".mp4", ".mkv", ".avi", ".mov"].contains(where: { nameLower.hasSuffix($0) || line.lowercased().contains($0) }) {
                vodItems.append(VodItem(name: itemName, posterURL: logo, streamURL: line, group: group))
            }
            currentExtInf = nil
        }
        return (vodItems, seriesItems)
    }

    // MARK: - Tek geçişte sınıflandırma (canlı / film / dizi)

    private enum M3UKind { case live, movie, series }

    private static func classify(url: String, group: String?) -> M3UKind {
        let path = (URL(string: url)?.path ?? url).lowercased()
        let ext = (path as NSString).pathExtension
        let g = (group ?? "").lowercased()

        if path.contains("/live/") || ext == "m3u8" || ext == "ts" { return .live }
        if path.contains("/series/") || g.contains("dizi") || g.contains("serie") { return .series }
        if path.contains("/movie/") || g.contains("film") || g.contains("movie") || g.contains("vod") || g.contains("sinema")
            || ["mp4", "mkv", "avi", "mov", "wmv", "flv"].contains(ext) { return .movie }
        return .live
    }

    /// M3U içeriğini bir kez okuyup her öğeyi yalnızca bir yere (canlı, film veya dizi) koyar.
    static func parseM3UAll(from data: Data, sourceName: String) -> (channels: [Channel], vod: [VodItem], series: [SeriesItem]) {
        guard let content = decodeText(data) else { return ([], [], []) }
        var channels: [Channel] = []
        var vod: [VodItem] = []
        var series: [SeriesItem] = []
        var currentExtInf: String?
        var index = 0

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.uppercased().hasPrefix("#EXTINF:") { currentExtInf = line; continue }
            if line.hasPrefix("#") { continue }
            guard line.contains("://") else { currentExtInf = nil; continue }

            let extinf = currentExtInf
            currentExtInf = nil
            index += 1

            let itemName = extinf.map { name(from: $0) } ?? line
            let logo = extinf.flatMap { attribute("tvg-logo", in: $0) }
            let group = extinf.flatMap { attribute("group-title", in: $0) }
            let id = "m3u|\(sourceName)|\(index)"

            switch classify(url: line, group: group) {
            case .series:
                series.append(SeriesItem(id: id, name: itemName, posterURL: logo, group: group, streamURL: line))
            case .movie:
                let ext = ((URL(string: line)?.path ?? line) as NSString).pathExtension.lowercased()
                vod.append(VodItem(id: id, name: itemName, posterURL: logo, streamURL: line, group: group, containerExtension: ext.isEmpty ? nil : ext))
            case .live:
                channels.append(Channel(id: id, name: itemName, logoURL: logo, streamURL: line, group: group,
                                        epgID: extinf.flatMap { attribute("tvg-id", in: $0) }, sourceName: sourceName))
            }
        }
        return (channels, vod, series)
    }
}
