import Foundation
import CoreGraphics

@main struct CoreTests {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError("FAIL: " + message) }
        }
        for text in ["中文搜索", "a & b + c # d ? e = f %", "two\nlines", "café 🧭", "https://example.com?a=1&b=2"] {
            let request = SearchRequest(query: text)!
            expect(SearchRequest(deepLink: request.deepLink) == request, "deep link round trip: \(text)")
            let items = URLComponents(url: request.googleURL, resolvingAgainstBaseURL: false)!.queryItems!
            expect(items.count == 1 && items[0].value == text, "Google query round trip")
            expect(request.googleURL.scheme == "https" && request.googleURL.host == "www.google.com", "fixed search destination")
        }
        expect(SearchRequest(query: " \n ") == nil, "empty selection")
        expect(SearchRequest(query: "  test  ")?.query == "test", "trim whitespace")
        expect(SearchRequest(query: "C++ A+B %&")!.googleURL.absoluteString == "https://www.google.com/search?q=C%2B%2B%20A%2BB%20%25%26", "form-style Google decoding preserves literal plus")
        expect(SearchRequest(query: String(repeating: "🧑‍💻", count: 5000))?.query.count == 4000, "grapheme-safe limit")
        for invalid in ["file:///etc/hosts", "https://search?q=x", "safarisidesearch://open?q=x",
                        "safarisidesearch://search/path?q=x", "safarisidesearch://user@search?q=x",
                        "safarisidesearch://search:80?q=x", "safarisidesearch://search?q=x&q=y",
                        "safarisidesearch://search?q=x#fragment", "safarisidesearch://search?q="] {
            expect(SearchRequest(deepLink: URL(string: invalid)!) == nil, "reject malformed route")
        }
        expect(AddressInput.url(for: "example.com")?.absoluteString == "https://example.com", "domain input")
        expect(AddressInput.url(for: "javascript:alert(1)")?.host == "www.google.com", "scheme input becomes search")
        expect(AddressInput.url(for: "") == nil, "empty address")
        let query = SearchRequest(query: "中文 C++ A+B &/#?= % 🧭")!
        for engine in SearchEngine.presets {
            let url = engine.url(for: query)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            expect(items.first?.value == query.query, "preset encodes query: \(engine.name)")
            expect(url.absoluteString.contains("C%2B%2B%20A%2BB"), "literal plus stays encoded")
            expect(AddressInput.url(for: "hello world", using: engine) == engine.url(for: SearchRequest(query: "hello world")!), "address respects engine")
            expect(AddressInput.url(for: "https://example.com", using: engine)?.host == "example.com", "engine keeps explicit website")
        }
        let custom = try! SearchEngine.custom(name: "  自定义  ", urlTemplate: "https://example.com/find/{query}?lang=zh#results")
        expect(custom.name == "自定义", "trim custom name")
        let customURL = custom.url(for: query)
        expect(customURL.host == "example.com" && customURL.fragment == "results", "fixed custom authority and fragment")
        expect(URLComponents(url: customURL, resolvingAgainstBaseURL: false)!.path == "/find/" + query.query, "custom path round trip")
        expect(customURL.absoluteString.contains("%26%2F%23%3F%3D"), "reserved characters cannot change URL structure")
        for template in ["https://example.com/?q=hello", "https://example.com/?q={query}&q={query}",
                         "javascript:alert('{query}')", "file:///tmp/{query}", "https://{query}.example.com/",
                         "https://user:password@example.com/?q={query}", "https://example.com/#{query}",
                         "https://example.com:99999/?q={query}", "https:///search?q={query}",
                         "https://example.com/?q={query}&x={other}", "https://example.com/a b?q={query}"] {
            expect((try? SearchEngine.custom(name: "Search", urlTemplate: template)) == nil, "reject invalid custom template: \(template)")
        }
        for name in ["", "  ", "a\nb", String(repeating: "a", count: 41)] {
            expect((try? SearchEngine.custom(name: name, urlTemplate: "https://example.com/?q={query}")) == nil, "reject invalid custom name")
        }
        let suite = "dev.local.SafariSideSearch.CoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchEngineStore(defaults: defaults)
        expect(store.selected == .google && store.engines.count == 4, "first run defaults to Google")
        expect(store.select(id: "baidu"), "select Baidu")
        expect(SearchEngineStore(defaults: defaults).selected.id == "baidu", "preset selection survives relaunch")
        let saved = try! store.saveCustom(name: "My Search", urlTemplate: "https://example.com/?q={query}")
        expect(store.selected == saved && store.engines.count == 5, "save selects custom engine")
        expect(SearchEngineStore(defaults: defaults).selected == saved, "custom engine survives relaunch")
        expect((try? store.saveCustom(name: "google", urlTemplate: saved.urlTemplate)) == nil, "duplicate preset name")
        expect((try? store.saveCustom(name: "MY SEARCH", urlTemplate: saved.urlTemplate)) == nil, "duplicate custom name")
        let edited = try! store.saveCustom(name: "Updated", urlTemplate: "https://example.org/s/{query}", editingID: saved.id)
        expect(edited.id == saved.id && store.customEngines.count == 1, "edit preserves identity without duplicate")
        expect(SearchEngineStore(defaults: defaults).selected == edited, "edit survives relaunch")
        expect(!store.select(id: "missing") && store.selected == edited, "invalid selection leaves current engine")
        expect(!store.removeCustom(id: "google") && store.engines.count == 5, "presets cannot be deleted")
        expect(store.removeCustom(id: edited.id) && store.selected == .google, "delete selected custom falls back to Google")
        expect(SearchEngineStore(defaults: defaults).customEngines.isEmpty, "deletion survives relaunch")
        defaults.set(Data("broken JSON".utf8), forKey: SearchEngineStore.preferencesKey)
        expect(SearchEngineStore(defaults: defaults).selected == .google, "corrupt preferences fall back")
        let invalidSettings: [String: Any] = ["selectedID": "custom.unsafe", "customEngines": [
            ["id": "custom.unsafe", "name": "Unsafe", "urlTemplate": "javascript:{query}"],
            ["id": "custom.valid", "name": "Valid", "urlTemplate": "https://example.com/?q={query}"],
            ["id": "custom.valid", "name": "Duplicate ID", "urlTemplate": "https://example.org/?q={query}"],
            ["id": "google", "name": "Override", "urlTemplate": "https://example.org/?q={query}"]]]
        defaults.set(try! JSONSerialization.data(withJSONObject: invalidSettings), forKey: SearchEngineStore.preferencesKey)
        let recovered = SearchEngineStore(defaults: defaults)
        expect(recovered.selected == .google && recovered.customEngines.count == 1, "revalidate persisted engines and deduplicate IDs")
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                       CGRect(x: 0, y: -1080, width: 1920, height: 1080)] {
            let safari = screen.insetBy(dx: 40, dy: 40)
            let frame = PanelLayout.frame(safari: safari, visibleScreen: screen, width: 430)
            expect(screen.contains(frame), "panel inside screen")
            expect(safari.contains(frame), "panel inside Safari content bounds")
            expect(frame.width == 430, "default width")
            expect(frame.maxY < safari.maxY - 40, "clear Safari toolbar")
        }
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        expect(tiny.contains(PanelLayout.frame(safari: tiny, visibleScreen: tiny, width: 999)), "small window clamps")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        expect(screen.contains(PanelLayout.frame(safari: .zero, visibleScreen: screen, width: 430)), "missing window fallback")
        print("PASS: \(checks) core checks")
    }
}
