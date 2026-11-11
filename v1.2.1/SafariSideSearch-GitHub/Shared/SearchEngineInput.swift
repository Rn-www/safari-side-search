import Foundation

/// Turns user-facing engine input into the strict template stored by SearchEngine.
struct SearchEngineInput {
    let suggestedName: String
    let urlTemplate: String

    static func resolve(_ input: String) throws -> SearchEngineInput {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw InputError.empty }
        guard raw.count <= 4096, !raw.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else { throw InputError.address }
        let aliases = ["google": 0, "谷歌": 0, "bing": 1, "必应": 1,
                       "baidu": 2, "百度": 2, "duckduckgo": 3, "duck duck go": 3]
        if let index = aliases[raw.lowercased()] {
            let preset = SearchEngine.presets[index]
            return SearchEngineInput(suggestedName: preset.name, urlTemplate: preset.urlTemplate)
        }

        var text = raw.replacingOccurrences(of: "{searchTerms}", with: "{query}")
            .replacingOccurrences(of: "%s", with: "{query}")
        if text.hasPrefix("//") { text = "https:" + text }
        else if text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) == nil {
            // Do not turn an explicit non-web scheme into an apparent hostname.
            let authority = text.components(separatedBy: "/")[0].components(separatedBy: "?")[0]
            if authority.contains(":"),
               authority.range(of: #"^[^:]+:[0-9]+$"#, options: .regularExpression) == nil {
                throw InputError.address
            }
            text = "https://" + text
        }
        let token = "safarisidesearchquerytoken"
        guard !text.contains(token),
              let parts = URLComponents(string: text.replacingOccurrences(of: "{query}", with: token)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host?.lowercased(), !host.isEmpty,
              SearchEngine.hasValidAuthority(parts),
              !host.contains(token), parts.url != nil else { throw InputError.address }
        let known = preset(for: host)
        let name = known?.name ?? String((host.hasPrefix("www.") ? String(host.dropFirst(4)) : host).prefix(40))
        if text.contains("{query}") {
            return try validated(name: name, template: text)
        }

        // Preserve the exact other parameters and encoding of a pasted results URL.
        let termKeys: Set<String> = ["q", "query", "wd", "word", "keyword", "keywords",
            "search", "search_query", "text", "s", "p", "term"]
        var fields = parts.percentEncodedQuery?.components(separatedBy: "&") ?? []
        let candidates = fields.indices.filter { index in
            let key = fields[index].components(separatedBy: "=")[0]
            return termKeys.contains((key.removingPercentEncoding ?? key).lowercased())
        }
        guard candidates.count < 2 else { throw InputError.ambiguous }
        if let index = candidates.first {
            let key = fields[index].components(separatedBy: "=")[0]
            fields[index] = key + "=" + token
            var result = parts
            result.percentEncodedQuery = fields.joined(separator: "&")
            return try validated(name: name,
                template: result.string!.replacingOccurrences(of: token, with: "{query}"))
        }
        if let known, known.paths.contains(parts.path), parts.port == nil {
            var result = URLComponents(string: known.template.replacingOccurrences(of: "{query}", with: token))!
            if let query = parts.percentEncodedQuery, !query.isEmpty {
                result.percentEncodedQuery! += "&" + query
            }
            return try validated(name: known.name,
                template: result.string!.replacingOccurrences(of: token, with: "{query}"))
        }
        throw InputError.unknownSearch
    }

    private static func validated(name: String, template: String) throws -> SearchEngineInput {
        let engine = try SearchEngine.custom(name: name, urlTemplate: template)
        return SearchEngineInput(suggestedName: engine.name, urlTemplate: engine.urlTemplate)
    }

    private struct Known {
        let name: String
        let template: String
        let paths: Set<String>
    }
    private static func preset(for host: String) -> Known? {
        switch host {
        case "google.com", "www.google.com", "google.com.hk", "www.google.com.hk",
             "google.co.uk", "www.google.co.uk":
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return Known(name: "Google", template: "https://www.\(domain)/search?q={query}", paths: ["", "/", "/search", "/webhp"])
        case "bing.com", "www.bing.com", "cn.bing.com":
            return Known(name: "Bing", template: SearchEngine.presets[1].urlTemplate, paths: ["", "/", "/search"])
        case "baidu.com", "www.baidu.com", "m.baidu.com":
            return Known(name: "百度", template: SearchEngine.presets[2].urlTemplate, paths: ["", "/", "/s"])
        case "duckduckgo.com", "www.duckduckgo.com":
            return Known(name: "DuckDuckGo", template: SearchEngine.presets[3].urlTemplate, paths: ["", "/"])
        default: return nil
        }
    }

    enum InputError: LocalizedError {
        case empty, address, unknownSearch, ambiguous
        var errorDescription: String? {
            switch self {
            case .empty: return "请输入搜索引擎名称、域名或搜索结果页网址。"
            case .address: return "无法识别这个地址，请检查域名或粘贴浏览器里的完整搜索网址。"
            case .unknownSearch: return "无法从这个首页判断搜索地址。请在该网站搜索一次，再把结果页网址粘贴到这里。"
            case .ambiguous: return "网址中有多个搜索参数，无法确定搜索词。请换一个更简洁的搜索结果页网址。"
            }
        }
    }
}
