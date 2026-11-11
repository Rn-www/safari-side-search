import Foundation

final class BrowserPreferences: NSObject {
    static let shared = BrowserPreferences()
    static let didChange = Notification.Name("SafariSideSearch.browserPreferencesDidChange")
    private let defaults: UserDefaults
    private static let fullURLKey = "appearance.showFullURL"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    var showFullURL: Bool {
        get { defaults.bool(forKey: Self.fullURLKey) }
        set {
            guard newValue != showFullURL else { return }
            defaults.set(newValue, forKey: Self.fullURLKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

}
