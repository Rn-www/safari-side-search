import Foundation

struct SearchRequest: Equatable {
    static let maximumLength = 4000
    let query: String

    init?(query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        self.query = String(cleaned.prefix(Self.maximumLength))
    }

    init?(deepLink: URL) {
        guard let parts = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "safarisidesearch",
              parts.host?.lowercased() == "search",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.fragment == nil,
              let items = parts.queryItems,
              items.count == 1, items[0].name == "q",
              let query = items[0].value else { return nil }
        self.init(query: query)
    }

    var googleURL: URL { SearchEngine.google.url(for: self) }

    var deepLink: URL {
        var parts = URLComponents()
        parts.scheme = "safarisidesearch"
        parts.host = "search"
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
}

enum AddressInput {
    static func url(for text: String, using engine: SearchEngine = .google) -> URL? {
        if let website = websiteURL(for: text) { return website }
        return SearchRequest(query: text).map { engine.url(for: $0) }
    }

    static func websiteURL(for text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil { return url }
        if !value.contains(where: { $0.isWhitespace }), !value.contains(":"),
           value.contains("."), let url = URL(string: "https://" + value), url.host != nil {
            return url
        }
        return nil
    }
}
