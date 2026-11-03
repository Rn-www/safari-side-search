import AppKit
import SafariServices

final class SafariExtensionHandler: SFSafariExtensionHandler {
    override func validateContextMenuItem(withCommand command: String, in page: SFSafariPage,
                                         userInfo: [String: Any]? = nil,
                                         validationHandler: @escaping (Bool, String?) -> Void) {
        let request = (userInfo?["selectedText"] as? String).flatMap { SearchRequest(query: $0) }
        validationHandler(command != "search-selection" || request == nil, nil)
    }

    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage,
                                         userInfo: [String: Any]? = nil) {
        guard command == "search-selection", let text = userInfo?["selectedText"] as? String,
              let request = SearchRequest(query: text) else { return }
        openCompanion(request.deepLink)
    }

    override func toolbarItemClicked(in window: SFSafariWindow) {
        openCompanion(URL(string: "safarisidesearch://show")!)
    }

    override func validateToolbarItem(in window: SFSafariWindow,
                                      validationHandler: @escaping (Bool, String) -> Void) {
        validationHandler(true, "")
    }

    private func openCompanion(_ url: URL) {
        // Use this extension's own containing app; do not trust another scheme handler.
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }
}
