import Foundation

struct VodItem: Identifiable, Hashable {
    let id: String
    let name: String
    let posterURL: String?
    let streamURL: String?
    let plot: String?
    let year: String?
    let group: String?
    let containerExtension: String?
    
    init(id: String = UUID().uuidString, name: String, posterURL: String? = nil, streamURL: String? = nil, plot: String? = nil, year: String? = nil, group: String? = nil, containerExtension: String? = nil) {
        self.id = id
        self.name = name
        self.posterURL = posterURL
        self.streamURL = streamURL
        self.plot = plot
        self.year = year
        self.group = group
        self.containerExtension = containerExtension
    }
}
