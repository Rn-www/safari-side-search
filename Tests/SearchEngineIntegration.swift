import AppKit
import WebKit
import CoreGraphics

/// Exercises production controls while intercepting navigation before any network request.
@MainActor final class SearchEngineIntegration: NSObject, WKNavigationDelegate {
    private static var retained: SearchEngineIntegration?
    private var window: NSWindow!
    private var browser: BrowserViewController!
    private var lastURL: URL?
    private var events: [String] = []
    private let suite = "dev.local.SafariSideSearch.EngineTests." + UUID().uuidString

    static func run() {
        let runner = SearchEngineIntegration()
        retained = runner
        Task { await runner.runChecks() }
    }

    private func check(_ condition: Bool, _ message: String) {
        guard condition else { finish(false, message); return }
        events.append(message)
    }

    private func pause() async { try? await Task.sleep(nanoseconds: 220_000_000) }

    private func choose(_ command: String) async {
        guard let item = browser.enginePicker.itemArray.first(where: { $0.representedObject as? String == command }) else {
            finish(false, "missing menu command: \(command)"); return
        }
        check(item.isEnabled, "menu command enabled: \(command)")
        guard let menu = browser.enginePicker.menu else { finish(false, "missing menu"); return }
        menu.performActionForItem(at: menu.index(of: item))
        await pause()
    }

    private func runChecks() async {
        guard let screen = NSScreen.screens.first(where: {
            guard let n = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) != 0
        }) else { finish(false, "built-in display unavailable; did not show on another screen"); return }
        let store = SearchEngineStore(defaults: UserDefaults(suiteName: suite)!)
        browser = BrowserViewController(engineStore: store)
        browser.webView.navigationDelegate = self
        let visible = screen.visibleFrame
        let rect = CGRect(x: visible.maxX - 454, y: visible.minY + 24, width: 430,
                          height: min(700, visible.height - 48))
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable],
                          backing: .buffered, defer: false, screen: screen)
        window.title = "搜索引擎测试 · 内建显示屏"
        window.contentViewController = browser
        window.setContentSize(rect.size)
        window.setFrameOrigin(rect.origin)
        check(visible.contains(window.frame), "test window fits built-in display before showing")
        window.makeKeyAndOrderFront(nil)
        if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            check(CGDisplayIsBuiltin(number.uint32Value) != 0, "test window uses built-in display")
        } else { finish(false, "test window has no screen"); return }
        browser.search(SearchRequest(query: "中文 C++ & 🧭")!)
        await pause()
        check(lastURL?.host == "www.google.com", "selection starts in Google")
        await choose("bing")
        check(lastURL?.host == "www.bing.com", "switch reruns query in Bing")
        check(URLComponents(url: lastURL!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "中文 C++ & 🧭", "switch retains Unicode query")
        await choose("baidu")
        check(lastURL?.host == "www.baidu.com" && lastURL?.query?.hasPrefix("wd=") == true, "Baidu uses wd parameter")
        browser.submit("another search")
        await pause()
        check(lastURL == store.selected.url(for: SearchRequest(query: "another search")!), "address query uses selected engine")
        browser.submit("https://example.com/path")
        await pause()
        let websiteURL = lastURL
        await choose("duckduckgo")
        check(lastURL == websiteURL, "switch without a current query keeps website")

        await choose("add")
        guard let editor = browser.engineEditor else { finish(false, "custom editor not presented"); return }
        check(editor.view.window?.sheetParent == window, "custom editor is a native sheet on test window")
        capture(editor.view, name: "engine-editor")
        editor.nameField.stringValue = "My Engine"
        editor.templateField.stringValue = "javascript:{query}"
        editor.saveButton.performClick(nil)
        check(!editor.validationMessage.isEmpty && browser.engineEditor != nil, "invalid template stays open with error")
        editor.templateField.stringValue = "https://example.org/find/{query}"
        editor.saveButton.performClick(nil)
        await pause()
        check(store.selected.name == "My Engine" && browser.engineEditor == nil, "custom save selects engine and closes sheet")
        browser.search(SearchRequest(query: "C++ 中文 &/")!)
        await pause()
        check(lastURL?.host == "example.org" && lastURL?.absoluteString.contains("C%2B%2B") == true, "custom path template receives encoded query")
        await choose("edit")
        guard let edit = browser.engineEditor else { finish(false, "edit not presented"); return }
        edit.nameField.stringValue = "Renamed"
        edit.templateField.stringValue = "https://example.net/?text={query}"
        edit.saveButton.performClick(nil)
        await pause()
        check(store.customEngines.count == 1 && lastURL?.host == "example.net", "editing current engine reruns query without duplication")
        let restored = SearchEngineStore(defaults: UserDefaults(suiteName: suite)!)
        check(restored.customEngines == store.customEngines && restored.selected == store.defaultEngine, "custom templates persist and a new session starts with the default")
        await choose("delete")
        check(store.selected == .google && store.customEngines.isEmpty && lastURL?.host == "www.google.com", "deleting selected custom falls back and reruns query")
        await choose("add")
        browser.engineEditor?.cancelButton.performClick(nil)
        await pause()
        check(store.customEngines.isEmpty && store.selected == .google, "cancel leaves settings unchanged")
        for width: CGFloat in [340, 430, 720] {
            window.setContentSize(NSSize(width: width, height: 650))
            window.setFrameOrigin(CGPoint(x: visible.maxX - width - 24, y: visible.minY + 24))
            browser.view.layoutSubtreeIfNeeded()
            let pickerFrame = browser.enginePicker.convert(browser.enginePicker.bounds, to: browser.view)
            check(browser.view.bounds.contains(pickerFrame), "engine picker fits \(Int(width)) pt sidebar")
            capture(browser.view, name: "engine-sidebar-\(Int(width))")
        }
        finish(true, "all checks passed")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        lastURL = action.request.url
        decisionHandler(.cancel)
    }

    private func finish(_ passed: Bool, _ message: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        print(passed ? "PASS: search engine integration" : "FAIL: search engine integration: \(message)")
        for event in events { print("  " + event) }
        fflush(stdout)
        exit(passed ? 0 : 1)
    }

    private func capture(_ view: NSView, name: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SideSearch-EngineCaptures", isDirectory: true)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                let file = folder.appendingPathComponent(name + ".png")
                try data.write(to: file)
                print("UI capture: " + file.path)
            }
        } catch {
            print("UI capture unavailable: " + error.localizedDescription)
        }
    }
}
