import Foundation

class NetworkService {
    static let shared = NetworkService()
    private init() {}

    /// Bazı sunucular belirli istemci kimliklerini reddeder (HTTP 403/5xx); sırayla farklı kimlikler denenir.
    private let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1",
        "VLC/3.0.18 LibVLC/3.0.18",
        "okhttp/4.9.3"
    ]

    func fetchM3U(from urlString: String) async throws -> Data {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        guard let url = URL(string: trimmed) ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            throw URLError(.badURL)
        }

        var lastError: Error = URLError(.badServerResponse)

        for userAgent in userAgents {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let preview = String(decoding: data.prefix(100), as: UTF8.self)
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
                    print("[AuroraIPTV][M3U] HTTP \(http.statusCode) (\(userAgent.prefix(12))...): \(preview)")
                    lastError = NSError(domain: "AuroraIPTV.M3U", code: http.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: "Sunucu HTTP \(http.statusCode) yanıtı verdi."])
                    continue   // sonraki istemci kimliğini dene
                }
                return data
            } catch {
                lastError = error
                if (error as? URLError)?.code == .cancelled { throw error }
            }
        }
        throw lastError
    }
}
