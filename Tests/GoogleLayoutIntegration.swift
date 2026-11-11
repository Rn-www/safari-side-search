import AppKit
import WebKit
import CoreGraphics

/// Exercises the real WKUserScript on controlled documents, never another screen.
@MainActor final class GoogleLayoutIntegration {
    private static var retained: GoogleLayoutIntegration?
    private let browser = BrowserViewController()
    private var window: NSWindow!
    private var checks: [[String: Any]] = []
    private let fixture = """
    <!doctype html><html><head><meta charset="utf-8"><title>Google 窄屏布局测试</title>
    <style>
    body{margin:0;min-width:1200px;font:16px -apple-system,sans-serif;background:#fff;color:#202124}
    #searchform{width:1200px;min-width:1200px;padding:24px 0}
    form[role=search]{width:692px;margin-left:180px}
    .RNNXgb{width:692px;border:1px solid #bbb;border-radius:24px;padding:12px}
    input{border:0;font:inherit;width:90%}#rcnt{display:flex;width:1100px}
    #center_col{width:652px;min-width:652px;margin-left:180px}
    #rso>div{width:652px;padding:12px 0}h3{font-size:20px;color:#1a0dab;margin:10px 0}
    p{line-height:1.6}cite{white-space:nowrap}#rhs{width:350px;min-width:350px;margin-left:40px}
    </style></head><body>
    <div id="searchform"><form role="search"><div class="RNNXgb"><input name="q" value="Safari 侧栏搜索"></div></form></div>
    <main id="main"><div id="rcnt"><div id="center_col"><div id="search"><div id="rso">
    <div><cite>https://example.test/averylongunbrokenurlwithmanylettersandnumbers123456789012345678901234567890</cite>
    <h3>搜索结果标题在侧栏里自动换行</h3><p>这是一段用于验证宽度的结果摘要。缩窄或加宽侧栏时，内容应重新排版，保留正常字号，也不需要左右移动页面。</p></div>
    </div></div></div><aside id="rhs"><h3>相关信息</h3><p>右侧信息卡片会排列到搜索结果下方，保留内容。</p></aside></div></main>
    </body></html>
    """

    static func run() {
        let runner = GoogleLayoutIntegration()
        retained = runner
        runner.start()
    }

    private func start() {
        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }) else { finish(false, "Built-in display required"); return }
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Google 宽度适配 · 内建显示屏"
        window.contentViewController = browser
        window.setContentSize(NSSize(width: 430, height: min(700, screen.visibleFrame.height - 48)))
        window.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24))
        window.makeKeyAndOrderFront(nil)
        Task { await verify() }
    }

    private func load(base: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            browser.onNavigationFinished = { _ in continuation.resume() }
            browser.onNavigationFailed = { continuation.resume(throwing: NSError(domain: "LayoutTest", code: 1)) }
            browser.webView.loadHTMLString(fixture, baseURL: URL(string: base)!)
        }
        // Wait for browser layout and the adapter's requestAnimationFrame, not network.
        _ = try await browser.webView.callAsyncJavaScript(
            "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); return true;",
            arguments: [:], in: nil, contentWorld: .page)
    }

    private func verify() async {
        do {
            try await load(base: "https://www.google.com/search?q=layout")
            for width in [340, 430, 720] {
                window.setContentSize(NSSize(width: width, height: 700))
                let result = try await browser.webView.callAsyncJavaScript("""
                    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                    const rect = s => document.querySelector(s).getBoundingClientRect();
                    const w = document.documentElement.clientWidth;
                    const center = rect('#center_col'), rhs = rect('#rhs'), form = rect('form');
                    return { viewport: w, scroll: document.documentElement.scrollWidth,
                      adapted: document.documentElement.hasAttribute('data-sidesearch-google-fit'),
                      centerLeft: center.left, centerRight: center.right,
                      formLeft: form.left, formRight: form.right,
                      rhsBelow: rhs.top >= center.bottom,
                      font: getComputedStyle(document.querySelector('h3')).fontSize };
                    """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
                checks.append(result.merging(["requestedWidth": width]) { _, value in value })
                guard result["adapted"] as? Bool == true,
                      let viewport = result["viewport"] as? Double,
                      let scroll = result["scroll"] as? Double, scroll <= viewport + 1,
                      let left = result["centerLeft"] as? Double, left >= 0,
                      let right = result["centerRight"] as? Double, right <= viewport + 1,
                      let formRight = result["formRight"] as? Double, formRight <= viewport + 1,
                      result["rhsBelow"] as? Bool == true, result["font"] as? String == "20px" else {
                    finish(false, "Width \(width) did not reflow"); return
                }
            }
            let dynamic = try await browser.webView.callAsyncJavaScript("""
                const card = document.createElement('div');
                card.style.cssText = 'width:1400px;min-width:1400px';
                card.textContent = 'Dynamically inserted Google result';
                document.querySelector('#rso').appendChild(card);
                document.querySelector('#sidesearch-google-width').remove();
                await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                return !!document.querySelector('#sidesearch-google-width') &&
                  card.getBoundingClientRect().right <= document.documentElement.clientWidth + 1;
                """, arguments: [:], in: nil, contentWorld: .page)
            guard dynamic as? Bool == true else { finish(false, "Dynamic results did not adapt"); return }
            for base in ["https://example.org/search", "https://www.google.com.attacker.example/search", "https://www.google.com/maps"] {
                try await load(base: base)
                let untouched = try await browser.webView.evaluateJavaScript("!document.querySelector('#sidesearch-google-width')")
                guard untouched as? Bool == true else { finish(false, "Non-search page was modified"); return }
            }
            if CommandLine.arguments.contains("--keep-open") {
                window.setContentSize(NSSize(width: 430, height: 700))
                try await load(base: "https://www.google.com/search?q=layout")
            }
            finish(true, "340/430/720 pt; readable text; dynamic results; non-Google isolation")
        } catch { finish(false, error.localizedDescription) }
    }

    private func finish(_ passed: Bool, _ message: String) {
        let result: [String: Any] = ["passed": passed, "message": message, "measurements": checks]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: data, encoding: .utf8)!)
        }
        print(passed ? "PASS: Google width adaptation" : "FAIL: Google width adaptation")
        fflush(stdout)
        if !CommandLine.arguments.contains("--keep-open") || !passed { exit(passed ? 0 : 1) }
    }
}
