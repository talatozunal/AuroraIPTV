import Foundation

struct PlaylistSource: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String = ""
    var username: String = ""
    var password: String = ""
    var serverURL: String = ""
    var type: SourceType = .m3u
    var enabled: Bool = true
    
    enum SourceType: String, Codable, CaseIterable {
        case m3u = "M3U"
        case xtream = "Xtream Codes"
    }
    
    init(id: UUID = UUID(), name: String, url: String = "", username: String = "", password: String = "", serverURL: String = "", type: SourceType = .m3u, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.password = password
        self.serverURL = serverURL
        self.type = type
        self.enabled = enabled
    }
}
