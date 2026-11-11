import Foundation

final class SearchEngineStore: NSObject {
    static let shared = SearchEngineStore()
    static let preferencesKey = "searchEngines.v1"
    static let didChange = Notification.Name("SafariSideSearch.enginesDidChange")
    private let defaults: UserDefaults
    private(set) var customEngines: [SearchEngine] = []
    private var selectedID = SearchEngine.google.id
    private var defaultID = SearchEngine.google.id

    private struct Settings: Codable {
        let selectedID: String
        let customEngines: [SearchEngine]
        let defaultID: String?
    }

    var engines: [SearchEngine] { SearchEngine.presets + customEngines }
    var selected: SearchEngine { engines.first(where: { $0.id == selectedID }) ?? .google }
    var defaultEngine: SearchEngine { engines.first(where: { $0.id == defaultID }) ?? .google }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        guard let data = defaults.data(forKey: Self.preferencesKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return }
        // Revalidate persisted entries; malformed settings must never become URLs.
        for stored in settings.customEngines {
            guard let engine = try? SearchEngine.custom(name: stored.name, urlTemplate: stored.urlTemplate, id: stored.id),
                  !engines.contains(where: { $0.id == engine.id || Self.sameName($0.name, engine.name) }) else { continue }
            customEngines.append(engine)
        }
        // Older versions remembered only the selected engine. Preserve that choice
        // as the initial default; later current-query choices stay independent.
        let restoredDefault = settings.defaultID ?? settings.selectedID
        if engines.contains(where: { $0.id == restoredDefault }) { defaultID = restoredDefault }
        selectedID = defaultID
    }

    @discardableResult func select(id: String) -> Bool {
        guard engines.contains(where: { $0.id == id }) else { return false }
        guard selectedID != id else { return true }
        selectedID = id
        persist()
        return true
    }

    @discardableResult func setDefault(id: String) -> Bool {
        guard engines.contains(where: { $0.id == id }) else { return false }
        guard defaultID != id else { return true }
        defaultID = id
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

    @discardableResult func saveInput(name: String, input: String, editingID: String? = nil) throws -> SearchEngine {
        let resolved = try SearchEngineInput.resolve(input)
        let typedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if editingID == nil, let existing = engines.first(where: {
            $0.urlTemplate == resolved.urlTemplate && (typedName.isEmpty || Self.sameName($0.name, typedName))
        }) {
            select(id: existing.id)
            return existing
        }
        var finalName = typedName.isEmpty ? resolved.suggestedName : typedName
        if typedName.isEmpty {
            var number = 2
            while engines.contains(where: { $0.id != editingID && Self.sameName($0.name, finalName) }) {
                let suffix = " (\(number))"
                finalName = String(resolved.suggestedName.prefix(40 - suffix.count)) + suffix
                number += 1
            }
        }
        return try saveCustom(name: finalName, urlTemplate: resolved.urlTemplate, editingID: editingID)
    }

    @discardableResult func removeCustom(id: String) -> Bool {
        guard customEngines.contains(where: { $0.id == id }) else { return false }
        customEngines.removeAll(where: { $0.id == id })
        if defaultID == id { defaultID = SearchEngine.google.id }
        if selectedID == id { selectedID = defaultID }
        persist()
        return true
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Settings(selectedID: selectedID, customEngines: customEngines, defaultID: defaultID)) {
            defaults.set(data, forKey: Self.preferencesKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
}
