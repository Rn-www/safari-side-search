import Foundation

final class SearchEngineStore {
    static let shared = SearchEngineStore()
    static let preferencesKey = "searchEngines.v1"
    private let defaults: UserDefaults
    private(set) var customEngines: [SearchEngine] = []
    private var selectedID = SearchEngine.google.id

    private struct Settings: Codable {
        let selectedID: String
        let customEngines: [SearchEngine]
    }

    var engines: [SearchEngine] { SearchEngine.presets + customEngines }
    var selected: SearchEngine { engines.first(where: { $0.id == selectedID }) ?? .google }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.preferencesKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return }
        // Revalidate persisted entries; malformed settings must never become URLs.
        for stored in settings.customEngines {
            guard let engine = try? SearchEngine.custom(name: stored.name, urlTemplate: stored.urlTemplate, id: stored.id),
                  !engines.contains(where: { $0.id == engine.id || Self.sameName($0.name, engine.name) }) else { continue }
            customEngines.append(engine)
        }
        if engines.contains(where: { $0.id == settings.selectedID }) { selectedID = settings.selectedID }
    }

    @discardableResult func select(id: String) -> Bool {
        guard engines.contains(where: { $0.id == id }) else { return false }
        selectedID = id
        persist()
        return true
    }

    @discardableResult func saveCustom(name: String, urlTemplate: String, editingID: String? = nil) throws -> SearchEngine {
        if let id = editingID, !customEngines.contains(where: { $0.id == id }) {
            throw SearchEngine.ValidationError.missingEngine
        }
        let engine = try SearchEngine.custom(name: name, urlTemplate: urlTemplate, id: editingID ?? "custom." + UUID().uuidString)
        guard !engines.contains(where: { $0.id != engine.id && Self.sameName($0.name, engine.name) }) else {
            throw SearchEngine.ValidationError.duplicateName
        }
        if let index = customEngines.firstIndex(where: { $0.id == engine.id }) { customEngines[index] = engine }
        else { customEngines.append(engine) }
        selectedID = engine.id
        persist()
        return engine
    }

    @discardableResult func removeCustom(id: String) -> Bool {
        guard customEngines.contains(where: { $0.id == id }) else { return false }
        customEngines.removeAll(where: { $0.id == id })
        if selectedID == id { selectedID = SearchEngine.google.id }
        persist()
        return true
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Settings(selectedID: selectedID, customEngines: customEngines)) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }
}
