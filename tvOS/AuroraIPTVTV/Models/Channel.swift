import Foundation

struct Channel: Identifiable, Hashable {
    let id: String
    let name: String
    let logoURL: String?
    let streamURL: String?
    let group: String?
    let epgID: String?
    let sourceName: String?
    
    init(id: String = UUID().uuidString, name: String, logoURL: String? = nil, streamURL: String? = nil, group: String? = nil, epgID: String? = nil, sourceName: String? = nil) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.group = group
        self.epgID = epgID
        self.sourceName = sourceName
    }
}
