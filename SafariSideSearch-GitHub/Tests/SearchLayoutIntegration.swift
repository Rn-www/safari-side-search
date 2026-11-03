import AppKit
import WebKit
import CoreGraphics

/// Controlled layout checks plus an opt-in live check, on the built-in display only.
@MainActor final class SearchLayoutIntegration {
    private static var retained: SearchLayoutIntegration?
    private let browser = BrowserViewController()
    private var window: NSWindow!
    private var screen: NSScreen!
    private var checks: [[String: Any]] = []
    private let live: Bool
    private var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("SideSearch-SearchLayouts") }

    init(live: Bool) { self.live = live }

    static func run(live: Bool = false) {
        let runner = SearchLayoutIntegration(live: live)
        retained = runner
        runner.start()
    }

    private func start() {
        guard let builtIn = NSScreen.screens.first(where: {
            guard let n = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) != 0
        }) else { finish(false, "Built-in display required; no fallback screen"); return }
        screen = builtIn
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                          backing: .buffered, defer: false, screen: screen)
        window.title = live ? "实时搜索布局 · 内建显示屏" : "百度 / Bing 布局 · 内建显示屏"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = browser
        setWidth(430)
        guard screen.visibleFrame.contains(window.frame) else { finish(false, "Window outside built-in display"); return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + (live ? 85 : 55)) { [self] in
            finish(false, "Layout test watchdog expired")
        }
        Task { if live { await verifyLive() } else { await verifyFixtures() } }
    }

    private func setWidth(_ width: Int) {
        window.setContentSize(NSSize(width: CGFloat(width), height: min(700, screen.visibleFrame.height - 48)))
        window.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24))
    }

    private func load(_ start: () -> Void, timeout: TimeInterval = 15) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var completed = false
            var timer: Timer?
            let complete: (Error?) -> Void = { [self] error in
                guard !completed else { return }
                completed = true
                timer?.invalidate()
                browser.onNavigationFinished = nil
                browser.onNavigationFailed = nil
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
            browser.onNavigationFinished = { _ in complete(nil) }
            browser.onNavigationFailed = { [self] in
                complete(NSError(domain: "SearchLayout", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: browser.lastErrorMessage ?? "Navigation failed"]))
            }
            timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                Task { @MainActor in
                    complete(NSError(domain: "SearchLayout", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Navigation timed out"]))
                }
            }
            start()
        }
    }

    private func script(_ source: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await browser.webView.callAsyncJavaScript(source, arguments: arguments, in: nil, contentWorld: .page)
    }

    private func settle() async throws {
        _ = try await script("await new Promise(r => { setTimeout(r,250); requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))); }); return true;")
    }

    private func loadFixture(_ engine: SearchPageAdapter.Engine, base: String? = nil, withViewport: Bool = true) async throws {
        var html = engine == .bing ? Self.bingFixture : Self.baiduFixture
        if !withViewport { html = html.replacingOccurrences(of: #"<meta name="viewport" content="width=1200">"#, with: "") }
        let url = base ?? (engine == .bing ? "https://www.bing.com/search?q=layout" : "https://www.baidu.com/s?wd=layout")
        try await load { browser.webView.loadHTMLString(html, baseURL: URL(string: url)!) }
        try await settle()
    }

    private func measure(_ engine: SearchPageAdapter.Engine) async throws -> [String: Any] {
        try await settle()
        return try await script("""
            const rect = s => { const r = document.querySelector(s)?.getBoundingClientRect();
              return r ? {left:r.left, right:r.right, top:r.top, bottom:r.bottom, width:r.width, height:r.height} : null; };
            const main = rect(engine === 'bing' ? '#b_results' : '#content_left');
            const side = rect(engine === 'bing' ? '#b_context' : '#content_right');
            const form = rect(engine === 'bing' ? '.b_searchboxForm' : '#form');
            const button = rect(engine === 'bing' ? '#sb_form_go' : '#su');
            const input = rect(engine === 'bing' ? '#sb_form_q' : '#kw');
            const title = document.querySelector(engine === 'bing' ? '#b_results h2' : '#content_left h3');
            const width = document.documentElement.clientWidth;
            const overflow = Array.from(document.body.querySelectorAll('*')).filter(e => {
              const r=e.getBoundingClientRect(); return r.width && r.right > width + 1 && getComputedStyle(e).position !== 'fixed';
            }).slice(0,12).map(e => ({tag:e.tagName,id:e.id,cls:typeof e.className==='string'?e.className:'',right:e.getBoundingClientRect().right}));
            return {viewport:width, scroll:document.documentElement.scrollWidth,
              adapted:document.documentElement.hasAttribute('data-sidesearch-'+engine+'-fit'),
              main, side, form, button, input, sideBelow:!!main && !!side && side.top >= main.bottom,
              font:title ? getComputedStyle(title).fontSize : '',
              titleUnclipped:!!title && title.scrollHeight <= title.clientHeight+1,
              rootOverflow:getComputedStyle(document.documentElement).overflowX,
              bodyOverflow:getComputedStyle(document.body).overflowX, overflow};
            """, arguments: ["engine": engine.rawValue]) as? [String: Any] ?? [:]
    }

    private func fits(_ m: [String: Any], expectSidebar: Bool = true) -> Bool {
        guard m["adapted"] as? Bool == true,
              let viewport = m["viewport"] as? Double,
              let scroll = m["scroll"] as? Double, scroll <= viewport + 1 else { return false }
        for key in ["main", "form", "button", "input"] {
            guard let r = m[key] as? [String: Any], let left = r["left"] as? Double, left >= -1,
                  let right = r["right"] as? Double, right <= viewport + 1,
                  let width = r["width"] as? Double, width > 0 else { return false }
        }
        if let button = m["button"] as? [String: Any],
           let width = button["width"] as? Double, let height = button["height"] as? Double,
           width < 30 || height < 24 { return false }
        if let input = m["input"] as? [String: Any], let button = m["button"] as? [String: Any],
           let inputLeft = input["left"] as? Double, let inputRight = input["right"] as? Double,
           let buttonLeft = button["left"] as? Double, let buttonRight = button["right"] as? Double,
           inputLeft < buttonRight - 1 && inputRight > buttonLeft + 1 { return false }
        if expectSidebar && m["sideBelow"] as? Bool != true { return false }
        return !["hidden", "clip"].contains(m["rootOverflow"] as? String ?? "") &&
            !["hidden", "clip"].contains(m["bodyOverflow"] as? String ?? "")
    }

    private func verifyFixtures() async {
        do {
            for engine in SearchPageAdapter.Engine.allCases {
                try await loadFixture(engine)
                for width in [340, 430, 720] {
                    setWidth(width)
                    let m = try await measure(engine)
                    checks.append(m.merging(["engine":engine.rawValue,"requestedWidth":width]) { _,v in v })
                    let formHeight = (m["form"] as? [String: Any])?["height"] as? Double ?? 0
                    guard fits(m), m["font"] as? String == "20px", m["titleUnclipped"] as? Bool == true,
                          engine != .bing || formHeight <= 64 else {
                        finish(false, "\(engine.rawValue) did not fit \(width)"); return
                    }
                    if width == 340 || width == 430 { await snapshot("fixture-\(engine.rawValue)-\(width)") }
                }
                // Leaving a search route in-page restores the original viewport.
                let restored = try await script("""
                    history.pushState({}, '', engine === 'bing' ? '/images/search' : '/other');
                    document.body.appendChild(document.createElement('span'));
                    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                    return !document.querySelector('#sidesearch-'+engine+'-width') &&
                      !document.documentElement.hasAttribute('data-sidesearch-'+engine+'-fit') &&
                      document.querySelector('meta[name=viewport]')?.content === 'width=1200';
                    """, arguments: ["engine":engine.rawValue])
                guard restored as? Bool == true else { finish(false, "Search route cleanup failed"); return }
                try await loadFixture(engine)
                let dynamic = try await script("""
                    const card=document.createElement('div'); card.id='dynamic-card';
                    card.style.cssText='width:1600px;min-width:1600px';
                    card.textContent='LongUnbrokenDynamicResultTitle'.repeat(12);
                    document.querySelector(engine==='bing'?'#b_results':'#content_left').appendChild(card);
                    document.querySelector('#sidesearch-'+engine+'-width').remove();
                    document.querySelector('meta[name=viewport]').remove();
                    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))));
                    return document.querySelectorAll('#sidesearch-'+engine+'-width').length===1 &&
                      document.documentElement.scrollWidth <= document.documentElement.clientWidth+1;
                    """, arguments: ["engine":engine.rawValue])
                guard dynamic as? Bool == true else { finish(false, "Dynamic content/style restoration failed"); return }
                try await loadFixture(engine, withViewport: false)
                let createdViewportRemoved = try await script("""
                    history.pushState({}, '', '/other'); document.body.appendChild(document.createElement('span'));
                    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                    return !document.querySelector('meta[name=viewport]');
                    """)
                guard createdViewportRemoved as? Bool == true else { finish(false, "Created viewport not removed"); return }
                let aliases = engine == .bing ? ["https://cn.bing.com/search", "https://bing.com/search"]
                    : ["https://baidu.com/s", "https://m.baidu.com/s", "https://www.baidu.com/baidu"]
                for url in aliases {
                    setWidth(430)
                    try await loadFixture(engine, base:url)
                    guard fits(try await measure(engine)) else { finish(false, "Alias did not reflow: \(url)"); return }
                }
                let excluded = engine == .bing ? ["https://www.bing.com/images/search", "https://www.bing.com/maps",
                    "https://www.bing.com.attacker.example/search", "https://copilot.bing.com/"]
                    : ["https://image.baidu.com/search", "https://baike.baidu.com/item/Safari",
                    "https://www.baidu.com.attacker.example/s", "https://wappass.baidu.com/static/captcha/tuxing_v2.html"]
                for url in excluded + ["https://example.org/search"] {
                    try await loadFixture(engine, base:url)
                    let untouched = try await script("""
                        return !document.querySelector('style[id^="sidesearch-"]') &&
                          document.querySelector('meta[name=viewport]')?.content==='width=1200';
                        """)
                    guard untouched as? Bool == true else { finish(false, "Unrelated page modified: \(url)"); return }
                }
            }
            finish(true, "340/430/720 pt; normal fonts; dynamic content; route/viewport cleanup; domain isolation")
        } catch { finish(false, error.localizedDescription) }
    }

    private func verifyLive() async {
        var blocked = 0
        var failed = false
        for engine in SearchPageAdapter.Engine.allCases {
            do {
                print("Live checking: " + engine.rawValue); fflush(stdout)
                setWidth(430)
                let url = engine == .bing ? "https://www.bing.com/search?q=Safari" : "https://www.baidu.com/s?wd=Safari"
                try await load({ browser.load(URL(string:url)!) }, timeout:22)
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let count = try await script("return document.querySelectorAll(engine==='bing'?'#b_results li.b_algo':'#content_left .result, #content_left .result-op').length;", arguments:["engine":engine.rawValue]) as? Int ?? 0
                print("Live results: \(engine.rawValue), count=\(count)"); fflush(stdout)
                guard count > 0 else {
                    checks.append(["engine":engine.rawValue,"status":"blocked","url":browser.webView.url?.absoluteString ?? "", "reason":"No search results; verification or different page"])
                    blocked += 1
                    continue
                }
                for width in [340,430,720] {
                    print("Measuring \(engine.rawValue): \(width)"); fflush(stdout)
                    setWidth(width)
                    let m = try await measure(engine)
                    let passed = fits(m, expectSidebar:false)
                    checks.append(m.merging(["engine":engine.rawValue,"requestedWidth":width,"status":passed ? "passed":"failed"]) { _,v in v })
                    if !passed { failed = true }
                    await snapshot("live-\(engine.rawValue)-\(width)")
                }
            } catch {
                browser.webView.stopLoading()
                blocked += 1
                checks.append(["engine":engine.rawValue,"status":"blocked","reason":error.localizedDescription])
            }
        }
        finish(!failed && blocked == 0, blocked > 0 ? "Live verification incomplete; \(blocked) engine(s) unavailable" : "Live page widths checked", partial:!failed && blocked > 0)
    }

    private func snapshot(_ name: String) async {
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                var completed = false
                let configuration = WKSnapshotConfiguration()
                configuration.afterScreenUpdates = false
                browser.webView.takeSnapshot(with:configuration) { image,error in
                    guard !completed else { return }
                    completed = true
                    if let image = image { continuation.resume(returning:image) }
                    else { continuation.resume(throwing:error ?? NSError(domain:"Snapshot",code:1)) }
                }
                DispatchQueue.main.asyncAfter(deadline:.now()+4) {
                    guard !completed else { return }
                    completed = true
                    continuation.resume(throwing:NSError(domain:"Snapshot",code:2))
                }
            }
            if let data=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:data),
               let png=bitmap.representation(using:.png,properties:[:]) {
                let file=folder.appendingPathComponent(name+".png")
                try png.write(to:file)
                print("Layout capture: "+file.path)
            }
        } catch { print("Snapshot unavailable: "+error.localizedDescription) }
    }

    private func finish(_ passed: Bool, _ message: String, partial: Bool = false) {
        let result: [String:Any] = ["passed":passed,"partial":partial,"message":message,"measurements":checks]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {
            try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try? data.write(to:folder.appendingPathComponent(live ? "live-report.json":"fixture-report.json"))
            print(String(data:data,encoding:.utf8)!)
        }
        let label = live ? "live search layout" : "Bing/Baidu width adaptation"
        print((passed ? "PASS: " : partial ? "PARTIAL: " : "FAIL: ")+label)
        fflush(stdout)
        exit(passed || partial ? 0:1)
    }

    private static let bingFixture = #"""
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=1200">
    <style>
    body{min-width:1200px;margin:0;font:16px -apple-system;background:#fff;color:#222}
    #b_header{min-width:1200px;padding:24px 0 0 180px}#sb_form{width:1000px}
    .b_logoArea{position:absolute;left:40px}.b_searchboxForm{position:relative;width:650px;border:1px solid #aaa;border-radius:20px}
    #sb_form_q{width:650px;font:inherit;border:0;padding:12px;border-radius:20px}
    #sb_search{display:inline-block;width:40px;height:40px;position:relative}#sb_form_go{position:absolute;left:0;top:0;width:40px;height:40px}
    #sbiarea{display:inline-block;width:32px;height:32px}
    .b_scopebar{width:900px;margin-left:180px}.b_scopebar ul{display:flex;gap:30px;padding:0;list-style:none}
    #b_content{width:1100px;padding-left:180px;display:flex;gap:40px}#b_results{width:650px;min-width:650px;padding:0;list-style:none}
    #b_results li{width:650px;margin:20px 0}h2{font-size:20px;white-space:nowrap;height:24px;overflow:hidden}
    cite{white-space:nowrap}p{line-height:1.6}#b_context{width:350px;min-width:350px;position:absolute;left:920px;list-style:none}
    </style></head><body><header id="b_header"><form id="sb_form"><a class="b_logoArea" href="/">Bing</a>
    <div class="b_searchboxForm"><div id="sb_search"><div id="sb_go_par"><input type="submit" id="sb_form_go" value="搜索"></div></div><input id="sb_form_q" name="q" value="Safari 侧栏搜索"><div id="sbiarea">⌕</div></div></form>
    <nav class="b_scopebar"><ul><li>网页</li><li>图片</li><li>视频</li><li>新闻</li><li>地图</li><li>更多</li></ul></nav></header>
    <div id="b_content"><main><ol id="b_results"><li class="b_algo"><h2><a href="https://example.test/">Bing 搜索结果中的很长标题应在窄侧栏自动换行</a></h2>
    <cite>https://example.test/verylongunbrokenurlwithmanylettersandnumbers123456789012345678901234567890</cite><p>保持正常字号，搜索框和内容列适应窗口。无需缩小整个页面，右侧信息仍可在下方阅读。</p></li></ol></main>
    <aside><ol id="b_context"><li><h2>相关信息</h2><p>卡片保留并移动到结果下方。</p></li></ol></aside></div></body></html>
    """#

    private static let baiduFixture = #"""
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=1200">
    <style>
    body{min-width:1200px;margin:0;font:16px -apple-system;background:#fff;color:#222}#wrapper{min-width:1200px}
    #head{position:fixed;left:0;top:0;width:1200px} .head_wrapper{width:1200px;margin-left:121px;padding:20px 0}
    #form{width:850px;margin-left:121px}.s_ipt_wr{display:inline-block;width:560px}#kw{width:560px;font:inherit;padding:12px}
    .s_btn_wr{display:inline-block;width:100px}#su{width:100px;font:inherit;height:42px}
    #s_tab{width:1000px;margin:110px 0 0 121px;white-space:nowrap}#s_tab a{margin-right:36px}
    #container{width:1200px;position:relative}#content_left{width:560px;min-width:560px;margin-left:121px}
    #content_right{position:absolute;left:850px;width:350px;min-width:350px}.result{width:560px}
    h3{font-size:20px;white-space:nowrap;height:24px;overflow:hidden}p{line-height:1.6}.c-showurl{white-space:nowrap}
    .c-row{margin:0 -8px}.c-span24{width:560px;min-width:560px}
    </style></head><body><div id="wrapper"><div id="head"><div class="head_wrapper"><form id="form">
    <a id="logo" href="/">百度</a><span class="s_ipt_wr"><input id="kw" name="wd" value="Safari 侧栏搜索"></span><span class="s_btn_wr"><input id="su" type="submit" value="百度一下"></span>
    </form></div></div><nav id="s_tab"><a>网页</a><a>图片</a><a>视频</a><a>资讯</a><a>地图</a><a>更多</a></nav>
    <div id="container"><aside id="content_right"><h3>相关信息</h3><p>保留右侧卡片，在侧栏中排列到结果下方。</p></aside>
    <div id="content_left"><div class="result c-container"><h3 class="t"><a href="https://example.test/">百度搜索结果中的很长标题应在窄侧栏自动换行</a></h3>
    <div class="c-row"><div class="c-span24"><p>搜索框、结果和摘要根据侧栏宽度重新排版，保留正常字号，内容不被裁掉。</p></div></div>
    <cite class="c-showurl">https://example.test/averylongunbrokenurlwithmanylettersandnumbers123456789012345678901234567890</cite></div></div></div></div></body></html>
    """#
}
