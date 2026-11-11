import Foundation

struct SearchEngine: Codable, Equatable {
    let id: String
    let name: String
    let urlTemplate: String

    static let google = SearchEngine(id: "google", name: "Google", urlTemplate: "https://www.google.com/search?q={query}")
    static let presets: [SearchEngine] = [
        google,
        SearchEngine(id: "bing", name: "Bing", urlTemplate: "https://www.bing.com/search?q={query}"),
        SearchEngine(id: "baidu", name: "百度", urlTemplate: "https://www.baidu.com/s?wd={query}"),
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", urlTemplate: "https://duckduckgo.com/?q={query}")
    ]

    var isCustom: Bool { id.hasPrefix("custom.") }

    private init(id: String, name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }

    static func custom(name: String, urlTemplate: String, id: String = "custom." + UUID().uuidString) throws -> SearchEngine {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              id.hasPrefix("custom."), id.count > 7 else { throw ValidationError.name }
        let template = urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "safarisidesearchquerytoken"
        let remainder = template.replacingOccurrences(of: "{query}", with: "")
        guard template.components(separatedBy: "{query}").count == 2,
              template.count <= 4096, !template.contains(marker),
              !remainder.contains("{"), !remainder.contains("}"),
              !template.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let parts = URLComponents(string: template.replacingOccurrences(of: "{query}", with: marker)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.contains(marker), hasValidAuthority(parts),
              parts.fragment?.contains(marker) != true,
              (parts.percentEncodedPath.contains(marker) || parts.percentEncodedQuery?.contains(marker) == true),
              parts.url != nil else { throw ValidationError.template }
        return SearchEngine(id: id, name: name, urlTemplate: template)
    }

    static func hasValidAuthority(_ parts: URLComponents) -> Bool {
        guard let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return false }
        let decoded = host.removingPercentEncoding ?? host
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            .union(CharacterSet(charactersIn: "/\\?#@{}"))
        guard !decoded.unicodeScalars.contains(where: { forbidden.contains($0) }) else { return false }
        if let port = parts.port {
            guard (1...65535).contains(port) else { return false }
        } else if parts.rangeOfPort != nil { return false } // Numeric overflow is not an absent port.
        guard let text = parts.string, let schemeEnd = text.range(of: "://")?.upperBound else { return false }
        let authority = text[schemeEnd...].prefix { !"/?#".contains($0) }
        guard !decoded.contains(":") || authority.hasPrefix("[") else { return false }
        return !authority.hasSuffix(":")
    }

    func url(for request: SearchRequest) -> URL {
        // Encode the value, never the whole template. Reserved characters (including
        // literal +, &, #, / and %) cannot change the destination or its parameters.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let value = request.query.addingPercentEncoding(withAllowedCharacters: unreserved)!
        return URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: value))!
    }

    enum ValidationError: LocalizedError {
        case name, template, duplicateName, missingEngine
        var errorDescription: String? {
            switch self {
            case .name: return "请输入 1–40 个字符的名称，不要使用换行或控制字符。"
            case .template: return "请输入 HTTP 或 HTTPS 搜索地址，在路径或查询参数中包含一个 {query}，用它代表搜索词。"
            case .duplicateName: return "已存在同名引擎，请换一个名称。"
            case .missingEngine: return "这个自定义引擎已不存在，请重新添加。"
            }
        }
    }
}
