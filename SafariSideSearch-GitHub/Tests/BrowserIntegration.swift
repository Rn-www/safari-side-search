import AppKit
import WebKit
import CoreGraphics

/// Only compiled into the separate test app, never the deliverable app.
@MainActor final class BrowserIntegration {
    private static var retained: BrowserIntegration?
    private let browser = BrowserViewController()
    private var window: NSWindow!
    private var stage = 0
    private var events: [String] = []
    private let base = URL(string: "http://127.0.0.1:18761/")!
    private var deadline: Timer?
    private var googleMode = false

    static func run() {
        if CommandLine.arguments.contains("--search-layout-test") || CommandLine.arguments.contains("--live-layout-test") {
            SearchLayoutIntegration.run(live: CommandLine.arguments.contains("--live-layout-test"))
            return
        }
        if CommandLine.arguments.contains("--search-engine-test") {
            SearchEngineIntegration.run()
            return
        }
        if CommandLine.arguments.contains("--google-layout-test") {
            GoogleLayoutIntegration.run()
            return
        }
        let runner = BrowserIntegration()
        retained = runner
        runner.start()
    }

    private func start() {
        googleMode = !CommandLine.arguments.contains("--fixtures-only")
        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }) else { events.append("built-in display unavailable; test was not shown elsewhere"); complete(false); return }
        let visible = screen.visibleFrame
        let rect = CGRect(x: visible.maxX - 454, y: visible.minY + 24,
                          width: 430, height: min(700, visible.height - 48))
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "侧栏测试 · 内建显示屏"
        events.append("test window placed on built-in display")
        window.contentViewController = browser
        window.setContentSize(rect.size)
        window.setFrameOrigin(rect.origin)
        window.makeKeyAndOrderFront(nil)
        browser.onNavigationFinished = { [weak self] url in self?.finished(url) }
        browser.onNavigationFailed = { [weak self] in
            guard let self = self else { return }
            if self.stage == 6 {
                self.events.append("network failure invoked recoverable error state")
                if self.googleMode {
                    self.stage = 7
                    self.browser.load(SearchRequest(query: "site:webkit.org WebKit")!.googleURL)
                } else { self.complete(true) }
            } else { self.complete(false) }
        }
        deadline = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.complete(false) }
        }
        browser.load(base.appendingPathComponent("index.html"))
    }

    private func finished(_ url: URL) {
        switch stage {
        case 0:
            guard url.lastPathComponent == "index.html" else { complete(false); return }
            events.append("initial fixture loaded")
            stage = 1
            browser.webView.evaluateJavaScript("document.getElementById('regular').click()")
        case 1:
            guard url.lastPathComponent == "page2.html", browser.webView.canGoBack else { complete(false); return }
            events.append("ordinary link retained in same WKWebView")
            stage = 2; browser.goBack()
        case 2:
            guard url.lastPathComponent == "index.html" else { complete(false); return }
            events.append("back navigation returned to original document")
            stage = 3
            browser.webView.evaluateJavaScript("document.getElementById('blank').click()")
        case 3:
            guard url.lastPathComponent == "popup.html", browser.redirectedWindowCount > 0 else { complete(false); return }
            events.append("target=_blank retained in same WKWebView")
            stage = 4; browser.goBack()
        case 4:
            guard url.lastPathComponent == "index.html" else { complete(false); return }
            stage = 5
            Task {
                do {
                    _ = try await browser.webView.callAsyncJavaScript("window.openFixture(); return true", arguments: [:],
                                                                      in: nil, contentWorld: .page)
                } catch { complete(false) }
            }
        case 5:
            guard url.lastPathComponent == "popup.html", browser.redirectedWindowCount >= 2 else { complete(false); return }
            events.append("window.open retained in same WKWebView")
            stage = 6
            browser.load(URL(string: "http://127.0.0.1:18762/unreachable")!)
        case 7:
            guard url.host?.contains("google.") == true else { complete(false); return }
            let script = "Array.from(document.querySelectorAll('a')).find(a => a.querySelector('h3') && a.href.startsWith('https://webkit.org/'))?.href || ''"
            browser.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self = self, let href = value as? String,
                      let target = URL(string: href), target.host == "webkit.org" else { self?.complete(false); return }
                self.events.append("real Google search results rendered")
                self.stage = 8
                let encoded = String(data: try! JSONSerialization.data(withJSONObject: [href]), encoding: .utf8)!
                self.browser.webView.evaluateJavaScript("Array.from(document.querySelectorAll('a')).find(a => a.href === \(encoded)[0]).click()")
            }
        case 8:
            guard url.host == "webkit.org" else { complete(false); return }
            events.append("real Google result opened inside the same WKWebView")
            if !CommandLine.arguments.contains("--exit-on-completion") {
                writeReport(true)
                deadline?.invalidate()
                browser.onNavigationFinished = nil
                browser.onNavigationFailed = nil
            } else { complete(true) }
        default: complete(false)
        }
    }

    private func complete(_ passed: Bool) {
        deadline?.invalidate()
        writeReport(passed)
        if CommandLine.arguments.contains("--exit-on-completion") { exit(passed ? 0 : 1) }
        browser.onNavigationFinished = nil
        browser.onNavigationFailed = nil
    }

    private func writeReport(_ passed: Bool) {
        let report: [String: Any] = ["passed": passed, "stage": stage, "events": events,
                                     "redirectedWindows": browser.redirectedWindowCount,
                                     "url": browser.webView.url?.absoluteString ?? "",
                                     "title": browser.webView.title ?? "", "error": browser.lastErrorMessage ?? ""]
        let output = ProcessInfo.processInfo.environment["SIDESEARCH_TEST_REPORT"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("sidesearch-browser-test.json").path
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: output))
            print(String(data: data, encoding: .utf8)!)
        }
        print(passed ? "PASS: browser integration" : "FAIL: browser integration at stage \(stage)")
        fflush(stdout)
    }
}
