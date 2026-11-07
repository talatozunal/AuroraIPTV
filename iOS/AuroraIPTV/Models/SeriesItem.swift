import Foundation

/// Xtream Codes hesap bilgisi (dizi bölümlerini sonradan çekebilmek için dizi ile birlikte saklanır)
struct XtreamAccount: Hashable, Codable {
    let base: String
    let username: String
    let password: String
}

struct SeriesItem: Identifiable, Hashable {
    let id: String
    let name: String
    let posterURL: String?
    let plot: String?
    let year: String?
    let group: String?
    /// Xtream `series_id` (bölüm listesini çekmek için gerekli)
    let seriesID: String?
    let account: XtreamAccount?
    /// M3U listelerinde dizi bölümü doğrudan bir yayın adresi olabilir
    let streamURL: String?

    init(id: String = UUID().uuidString,
         name: String,
         posterURL: String? = nil,
         plot: String? = nil,
         year: String? = nil,
         group: String? = nil,
         seriesID: String? = nil,
         account: XtreamAccount? = nil,
         streamURL: String? = nil) {
        self.id = id
        self.name = name
        self.posterURL = posterURL
        self.plot = plot
        self.year = year
        self.group = group
        self.seriesID = seriesID
        self.account = account
        self.streamURL = streamURL
    }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let streamURL: String
    let imageURL: String?
    let plot: String?
    let duration: String?
}

struct SeriesDetail {
    var plot: String?
    var episodes: [Episode]
}
