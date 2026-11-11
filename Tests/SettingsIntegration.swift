import AppKit
import WebKit
import CoreGraphics

@MainActor final class SettingsIntegration: NSObject, WKNavigationDelegate {
    private static var retained: SettingsIntegration?
    private let suite = "dev.local.SafariSideSearch.SettingsTests." + UUID().uuidString
    private var browser: BrowserViewController!
    private var window: NSWindow!
    private var screen: NSScreen!
    private var requests: [URL] = []
    private var events: [String] = []
    private var completed = false

    static func run() {
        let runner = SettingsIntegration()
        retained = runner
        Task { await runner.verify() }
    }

    private func check(_ condition: Bool, _ message: String) {
        guard condition else { finish(false, message); return }
        events.append(message)
    }
    private func pause() async { try? await Task.sleep(nanoseconds: 280_000_000) }
    private func choose(_ id: String, in picker: NSPopUpButton) async {
        guard let item = picker.itemArray.first(where: { $0.representedObject as? String == id }) else {
            finish(false, "Menu item missing: " + id); return
        }
        check(item.isEnabled, "Enabled menu command: " + id)
        guard let menu = picker.menu else { finish(false, "Menu missing"); return }
        menu.performActionForItem(at: menu.index(of: item))
        await pause()
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func verify() async {
        guard let builtIn = NSScreen.screens.first(where: {
            guard let n = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) != 0
        }) else { finish(false, "Built-in display unavailable; no fallback"); return }
        screen = builtIn
        let defaults = UserDefaults(suiteName: suite)!
        let store = SearchEngineStore(defaults: defaults)
        let preferences = BrowserPreferences(defaults: defaults)
        browser = BrowserViewController(engineStore: store, preferences: preferences)
        browser.webView.navigationDelegate = self
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false, screen: screen)
        window.title = "玻璃工具栏与设置测试 · 内建显示屏"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentViewController = browser
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        setWidth(430)
        check(screen.visibleFrame.contains(window.frame), "Sidebar fits built-in display before showing")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [self] in
            if !completed { finish(false, "Settings integration watchdog expired") }
        }
        let url = URL(string: "https://example.org/a/long/path?q=C%2B%2B#results")!
        browser.load(url)
        try? await Task.sleep(nanoseconds: 700_000_000)
        check(browser.address.stringValue == "example.org", "Compact address shows origin")
        browser.focusAddress()
        await pause()
        check(browser.address.stringValue == url.absoluteString, "Focusing address reveals complete URL")
        browser.address.stringValue = "draft query not submitted"
        browser.address.currentEditor()?.string = "draft query not submitted"
        let beforeDraft = requests.count
        preferences.showFullURL = true
        check(browser.address.stringValue == "draft query not submitted", "Preference changes preserve in-progress text")
        preferences.showFullURL = false
        window.makeFirstResponder(browser.webView)
        await pause()
        check(browser.address.stringValue == "example.org", "Blur restores compact canonical URL")
        check(requests.count == beforeDraft, "Blur does not submit an unfinished query")

        browser.settingsButton.performClick(nil)
        await pause()
        guard let controller = browser.settingsWindowController, let settingsWindow = controller.window else {
            finish(false, "Settings window not opened by gear"); return
        }
        let settings = controller.settings
        let screenNumber = settingsWindow.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        check(screenNumber.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } == true, "Settings opens on sidebar built-in display")
        settings.view.layoutSubtreeIfNeeded()
        check(settings.view.subviews.allSatisfy { settings.view.bounds.insetBy(dx:-1,dy:-1).contains($0.frame) }, "Settings controls stay within window")
        settings.showFullURLButton.performClick(nil)
        check(preferences.showFullURL && browser.address.stringValue == url.absoluteString, "Settings enables full address immediately")
        settings.showFullURLButton.performClick(nil)
        check(!preferences.showFullURL && browser.address.stringValue == "example.org", "Settings restores compact display immediately")

        browser.search(SearchRequest(query: "first C++ query")!)
        await pause()
        requests.removeAll()
        await choose("bing", in: settings.currentEnginePicker)
        check(store.selected.id == "bing" && browser.enginePicker.selectedItem?.representedObject as? String == "bing", "Settings selection synchronizes toolbar")
        check(requests.count == 1 && requests.last?.host == "www.bing.com", "Current engine switch loads query exactly once")
        await choose("baidu", in: browser.enginePicker)
        check(settings.currentEnginePicker.selectedItem?.representedObject as? String == "baidu", "Toolbar selection synchronizes settings")
        let beforeDefault = requests.count
        await choose("bing", in: settings.defaultEnginePicker)
        check(store.defaultEngine.id == "bing" && store.selected.id == "baidu", "Default and current engines are independent")
        check(requests.count == beforeDefault, "Default change does not navigate")
        requests.removeAll()
        let newQuery = SearchRequest(query: "new selected text 中文")!
        browser.searchSelection(newQuery)
        await pause()
        check(requests.count == 1 && requests.last == store.defaultEngine.url(for: newQuery), "New selection uses default once without replaying old query")
        await choose("baidu", in: settings.currentEnginePicker)
        browser.submit("typed address query")
        await pause()
        check(requests.last == store.selected.url(for: SearchRequest(query:"typed address query")!), "Address queries use current engine")
        check(store.defaultEngine.id == "bing", "Temporary query engine leaves default unchanged")

        await choose("add", in: settings.currentEnginePicker)
        guard let editor = settings.engineEditor else { finish(false, "Settings custom editor missing"); return }
        check(editor.view.window?.sheetParent == settingsWindow, "Settings custom editor is a native sheet")
        editor.nameField.stringValue = "Settings Engine"
        editor.templateField.stringValue = "https://example.net/?q={query}"
        editor.saveButton.performClick(nil)
        await pause()
        let customID = store.selected.id
        check(browser.enginePicker.selectedItem?.representedObject as? String == customID, "Settings custom engine appears in toolbar")
        await choose(customID, in: settings.defaultEnginePicker)
        let relaunched = SearchEngineStore(defaults: defaults)
        check(relaunched.defaultEngine.id == customID && relaunched.selected.id == customID, "Custom default survives a new session")
        await choose("delete", in: browser.enginePicker)
        check(store.defaultEngine == .google && store.selected == .google, "Deleting custom default recovers both selections")
        check(settings.defaultEnginePicker.selectedItem?.representedObject as? String == "google", "Default fallback synchronizes settings")

        settings.addEngineButton.performClick(nil)
        await pause()
        guard let recognized = settings.engineEditor else { finish(false, "Direct add button did not open editor"); return }
        recognized.templateField.stringValue = "google.com"
        recognized.templateField.currentEditor()?.string = "google.com"
        recognized.saveButton.performClick(nil)
        await pause()
        check(settings.engineEditor == nil && store.selected == .google && store.customEngines.isEmpty,
              "Domain-only preset save succeeds without duplicate-name failure")
        settings.addEngineButton.performClick(nil)
        await pause()
        guard let automatic = settings.engineEditor else { finish(false, "Automatic editor missing"); return }
        automatic.templateField.stringValue = "example.org/find?lang=zh&q=hello"
        automatic.templateField.currentEditor()?.string = automatic.templateField.stringValue
        automatic.saveButton.performClick(nil)
        await pause()
        check(settings.engineEditor == nil && store.selected.name == "example.org" &&
              store.selected.urlTemplate == "https://example.org/find?lang=zh&q={query}",
              "Result URL saves with automatic name and search parameter")
        await choose(store.selected.id, in: settings.defaultEnginePicker)
        check(SearchEngineStore(defaults: defaults).defaultEngine == store.selected,
              "Automatically recognized custom default persists")
        check(settingsWindow.isVisible, "Settings stays visible after engine operations")
        await choose("delete", in: browser.enginePicker)

        settingsWindow.close()
        browser.settingsButton.performClick(nil)
        await pause()
        check(browser.settingsWindowController === controller && controller.window?.isVisible == true, "Settings reuses one window")
        if #available(macOS 26.0, *) {
            let glasses = descendants(browser.view).compactMap { $0 as? NSGlassEffectView }
            check(glasses.count >= 6 && glasses.allSatisfy { $0.contentView != nil }, "Toolbar uses native Liquid Glass surfaces")
            if #available(macOS 27.0, *) {
                check(glasses.allSatisfy { $0.value(forKey:"effectIsInteractive") as? Bool == true }, "Glass responds to interaction")
            }
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named:theme)
            settingsWindow.appearance = window.appearance
            for width in [340,430,720] {
                setWidth(width)
                browser.view.layoutSubtreeIfNeeded()
                for control in [browser.address as NSView, browser.enginePicker, browser.settingsButton] {
                    let rect = control.convert(control.bounds,to:browser.view)
                    check(rect.width > 10 && rect.height > 10 && browser.view.bounds.contains(rect), "Control fits \(width) pt in \(theme.rawValue)")
                }
                check(browser.address.bounds.width >= CGFloat(width) - 224, "Address field uses available toolbar width")
            }
            capture(settings.view,name:theme == .aqua ? "settings-light":"settings-dark")
            setWidth(430)
            capture(browser.view,name:theme == .aqua ? "toolbar-light":"toolbar-dark")
        }
        settingsWindow.close()
        // Error display must retain the same URL-display preference.
        browser.webView.navigationDelegate = browser
        let errorURL = URL(string:"http://127.0.0.1:1/error?test=1")!
        browser.load(errorURL)
        for _ in 0..<30 {
            if browser.lastErrorMessage != nil { break }
            try? await Task.sleep(nanoseconds:100_000_000)
        }
        check(browser.lastErrorMessage != nil && browser.address.stringValue == "http://127.0.0.1:1", "Failure state keeps compact URL")
        preferences.showFullURL = true
        check(browser.address.stringValue == errorURL.absoluteString, "Failure state supports full URL")
        preferences.showFullURL = false
        if CommandLine.arguments.contains("--keep-open") {
            browser.webView.navigationDelegate = self
            window.appearance = NSAppearance(named:.darkAqua)
            settingsWindow.appearance = window.appearance
            setWidth(430)
            browser.load(URL(string:"https://www.google.com/search?q=Liquid%20Glass")!)
            await pause()
            browser.openSettings()
        }
        finish(true,"All settings checks passed")
    }

    private func setWidth(_ width: Int) {
        window.setContentSize(NSSize(width:CGFloat(width),height:min(700,screen.visibleFrame.height-48)))
        window.setFrameOrigin(CGPoint(x:screen.visibleFrame.maxX-CGFloat(width)-24,y:screen.visibleFrame.minY+24))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, ["http","https"].contains(url.scheme ?? "") { requests.append(url) }
        decisionHandler(.cancel)
    }
    private func capture(_ view: NSView,name:String) {
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("SideSearch-SettingsCaptures")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if let data=bitmap.representation(using:.png,properties:[:]) {
                let file=folder.appendingPathComponent(name+".png")
                try data.write(to:file)
                print("Settings capture: "+file.path)
            }
        } catch { print("Capture unavailable: "+error.localizedDescription) }
    }
    private func finish(_ passed:Bool,_ message:String) {
        completed = true
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
        print(passed ? "PASS: glass toolbar and settings" : "FAIL: settings: "+message)
        for event in events { print("  "+event) }
        fflush(stdout)
        if !passed || !CommandLine.arguments.contains("--keep-open") {
            exit(passed ? 0:1)
        }
    }
}
