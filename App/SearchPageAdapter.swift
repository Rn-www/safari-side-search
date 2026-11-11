import WebKit

/// Reflows desktop Bing/Baidu Search while keeping their normal font sizes.
enum SearchPageAdapter {
    enum Engine: String, CaseIterable { case bing, baidu }

    static func install(in configuration: WKWebViewConfiguration) {
        for engine in Engine.allCases {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source(for: engine), injectionTime: .atDocumentStart,
                forMainFrameOnly: true, in: .defaultClient))
        }
    }

    static func source(for engine: Engine) -> String {
        let hosts = engine == .bing ? #"["bing.com", "www.bing.com", "cn.bing.com"]"#
            : #"["baidu.com", "www.baidu.com", "m.baidu.com"]"#
        let paths = engine == .bing ? #"["/", "/search"]"# : #"["/", "/s", "/baidu"]"#
        return #"""
        (() => {
            "use strict";
            if (!/^https?:$/.test(location.protocol) || !\#(hosts).includes(location.hostname.toLowerCase())) return;
            const isSearch = () => \#(paths).includes(location.pathname);
            const styleID = "sidesearch-\#(engine.rawValue)-width";
            const marker = "data-sidesearch-\#(engine.rawValue)-fit";
            const css = `
            @media (max-width: 800px) {
              html[${marker}], html[${marker}] body {
                width: 100% !important;
                min-width: 0 !important;
                max-width: 100% !important;
                margin: 0 !important;
                box-sizing: border-box !important;
              }
              \#(engine == .bing ? bingCSS : baiduCSS)
            }`;
            const viewportContent = "width=device-width, initial-scale=1";
            let viewport = null, previousContent = null, createdViewport = false;

            function apply() {
                if (!document.documentElement || !document.head) return;
                if (!isSearch()) {
                    document.documentElement.removeAttribute(marker);
                    document.getElementById(styleID)?.remove();
                    // Restore only metadata still owned by this script; a new page
                    // may already have installed its own viewport configuration.
                    if (viewport?.isConnected && viewport.content === viewportContent) {
                        if (createdViewport) viewport.remove();
                        else if (previousContent === null) viewport.removeAttribute("content");
                        else viewport.setAttribute("content", previousContent);
                    }
                    viewport = null;
                    return;
                }
                if (!document.documentElement.hasAttribute(marker)) document.documentElement.setAttribute(marker, "");
                let style = document.getElementById(styleID);
                if (!style) {
                    style = document.createElement("style");
                    style.id = styleID;
                    document.head.appendChild(style);
                }
                if (style.textContent !== css) style.textContent = css;
                let current = document.querySelector('meta[name="viewport"]');
                if (current !== viewport || !current) {
                    viewport = current;
                    createdViewport = !current;
                    previousContent = current?.getAttribute("content") ?? null;
                    if (!viewport) {
                        viewport = document.createElement("meta");
                        viewport.name = "viewport";
                        document.head.appendChild(viewport);
                    }
                }
                if (viewport.content !== viewportContent) viewport.content = viewportContent;
            }

            let scheduled = false;
            let frame = null, timer = null;
            function flush() {
                if (!scheduled) return;
                scheduled = false;
                if (frame !== null) cancelAnimationFrame(frame);
                clearTimeout(timer);
                frame = timer = null;
                apply();
            }
            new MutationObserver(() => {
                if (scheduled) return;
                scheduled = true;
                // Hidden/inactive WebKit views may suspend animation frames. The
                // coalesced fallback also restores metadata before they reappear.
                timer = setTimeout(flush, 100);
                frame = requestAnimationFrame(flush);
            }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["content"] });
            addEventListener("popstate", apply);
            document.addEventListener("DOMContentLoaded", apply, { once: true });
            apply();
        })();
        """#
    }

    private static let bingCSS = #"""
    html[${marker}] body { --lgutter: 12px; --rgutter: 0px; }
    html[${marker}] :is(#b_header, #sb_form, .b_searchboxForm) {
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin-inline: 0 !important; box-sizing: border-box !important;
    }
    html[${marker}] #b_header {
      position: relative !important; inset: auto !important; padding: 12px !important;
    }
    html[${marker}] #sb_form {
      display: flex !important; flex-wrap: wrap !important; align-items: center;
      gap: 8px; padding: 0 !important;
    }
    html[${marker}] #sb_form :is(.b_logoArea, .b_logo) {
      position: relative !important; inset: auto !important; float: none !important;
      margin-inline: 0 !important; max-width: 100% !important;
    }
    html[${marker}] #sb_form .b_logoArea { flex: 0 0 100%; }
    html[${marker}] .b_searchboxForm {
      position: relative !important; display: flex !important; align-items: center !important;
      flex: 1 1 100%; flex-wrap: nowrap !important; height: 48px !important; padding-inline: 4px !important;
    }
    html[${marker}] #sb_form_q {
      position: relative !important; inset: auto !important; margin: 0 !important;
      flex: 1 1 0 !important; width: 0 !important; min-width: 0 !important; max-width: 100% !important;
      height: 44px !important; box-sizing: border-box !important; padding-inline: 8px !important;
    }
    html[${marker}] #sb_search {
      position: relative !important; inset: auto !important; flex: 0 0 40px !important;
      width: 40px !important; height: 40px !important; margin: 0 !important;
    }
    html[${marker}] #sb_form_go {
      position: absolute !important; left: 0 !important; top: 0 !important;
      width: 40px !important; height: 40px !important; margin: 0 !important;
    }
    html[${marker}] .b_searchboxForm > :is(#sb_clt, #sbiarea) {
      position: relative !important; inset: auto !important; flex: 0 0 32px !important;
      width: 32px !important; margin: 0 !important;
    }
    html[${marker}] #id_h {
      position: relative !important; inset: auto !important; float: none !important;
      display: flex !important; flex-wrap: wrap !important; max-width: 100% !important;
      margin: 8px 0 !important; padding: 0 !important;
    }
    html[${marker}] :is(.b_scopebar, #b_scopebar) {
      min-width: 0 !important; max-width: 100% !important; margin: 0 !important;
      padding-inline: 0 !important; overflow-x: auto !important; box-sizing: border-box !important;
    }
    html[${marker}] .b_scopebar > ul { display: flex; flex-wrap: nowrap; white-space: nowrap; }
    html[${marker}] #b_content {
      display: flex !important; flex-direction: column !important;
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin: 0 !important; padding: 12px !important; box-sizing: border-box !important;
    }
    html[${marker}] #b_content :is(main, aside),
    html[${marker}] :is(#b_results, #b_topw, #b_pole, #b_context, #b_rrat_cont, #b_dynRail) {
      position: static !important; float: none !important; display: block !important;
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin-inline: 0 !important; padding-inline: 0 !important; box-sizing: border-box !important;
    }
    html[${marker}] #b_content main { order: 0; }
    html[${marker}] #b_content aside { order: 1; }
    html[${marker}] :is(#b_context, #b_rrat_cont, #b_dynRail) { order: 1; margin-top: 24px !important; }
    html[${marker}] :is(#b_results, #b_topw, #b_context, #b_rrat_cont, #b_dynRail) * {
      min-width: 0 !important; max-width: 100% !important;
      box-sizing: border-box !important; overflow-wrap: anywhere;
    }
    html[${marker}] :is(#b_results, #b_context) :is(h2, h3, p, cite, a, .b_attribution) {
      white-space: normal !important;
    }
    html[${marker}] #b_results h2 {
      height: auto !important; max-height: none !important; overflow: visible !important;
      -webkit-line-clamp: unset !important;
    }
    html[${marker}] :is(#b_results, #b_context) :is(.b_sideBleed, .b_overhangR, .b_fullb, .b_entityTP) {
      margin-inline: 0 !important;
    }
    html[${marker}] :is(#b_results, #b_context) :is(img, video) { height: auto !important; }
    html[${marker}] :is(#b_tween, #b_footer, #b_footerItems) {
      min-width: 0 !important; max-width: 100% !important; margin-inline: 0 !important;
      padding-inline: 12px !important; box-sizing: border-box !important; overflow-wrap: anywhere;
    }
    html[${marker}] #b_tween { order: -1; }
    """#

    private static let baiduCSS = #"""
    html[${marker}] :is(#wrapper, #head, .head_wrapper, .s_form, .s_form_wrapper, #s_form) {
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin-inline: 0 !important; padding-inline: 0 !important; box-sizing: border-box !important;
    }
    html[${marker}] #head {
      position: relative !important; inset: auto !important; height: auto !important;
      padding: 12px !important;
    }
    html[${marker}] #form {
      display: flex !important; flex-wrap: wrap !important; align-items: center; gap: 8px;
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin: 0 !important; padding: 0 !important; box-sizing: border-box !important;
    }
    html[${marker}] :is(#logo, #lg) {
      position: relative !important; inset: auto !important; float: none !important;
      max-width: 100% !important; margin-inline: 0 !important;
    }
    html[${marker}] #form #logo { flex: 0 0 100%; }
    html[${marker}] #form .s_ipt_wr {
      position: relative !important; flex: 1 1 0 !important; width: auto !important;
      min-width: 0 !important; max-width: 100% !important; box-sizing: border-box !important;
    }
    html[${marker}] #kw {
      position: relative !important; inset: auto !important; width: 100% !important;
      min-width: 0 !important; max-width: 100% !important; box-sizing: border-box !important;
    }
    html[${marker}] #form .s_btn_wr { flex: 0 0 auto !important; width: auto !important; }
    html[${marker}] #s_tab {
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin: 0 !important; padding-inline: 12px !important; box-sizing: border-box !important;
      overflow-x: auto !important; white-space: nowrap !important;
    }
    html[${marker}] #u {
      position: relative !important; inset: auto !important; max-width: 100% !important;
      white-space: normal !important; margin: 8px 12px !important;
    }
    html[${marker}] #container {
      display: flex !important; flex-direction: column !important;
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin: 0 !important; padding-inline: 12px !important; box-sizing: border-box !important;
    }
    html[${marker}] :is(#content_left, #content_right) {
      position: static !important; float: none !important;
      width: 100% !important; min-width: 0 !important; max-width: 100% !important;
      margin-inline: 0 !important; padding-inline: 0 !important; box-sizing: border-box !important;
    }
    html[${marker}] #content_left { order: 0; }
    html[${marker}] #content_right { order: 1; margin-top: 24px !important; }
    html[${marker}] :is(#content_left, #content_right) * {
      min-width: 0 !important; max-width: 100% !important;
      box-sizing: border-box !important; overflow-wrap: anywhere;
    }
    html[${marker}] :is(#content_left, #content_right) :is(h3, .t, p, a, cite, .c-showurl) {
      white-space: normal !important;
    }
    html[${marker}] #content_left :is(h3, .t) {
      height: auto !important; max-height: none !important; overflow: visible !important;
      -webkit-line-clamp: unset !important;
    }
    html[${marker}] :is(#content_left, #content_right) :is(.c-row, .cos-row) {
      margin-inline: 0 !important; flex-wrap: wrap !important;
    }
    html[${marker}] :is(#content_left, #content_right) :is(img, video) { height: auto !important; }
    html[${marker}] :is(#rs, #page, #foot, #tsn_inner) {
      min-width: 0 !important; max-width: 100% !important; margin-inline: 0 !important;
      padding-inline: 12px !important; box-sizing: border-box !important; overflow-wrap: anywhere;
    }
    """#
}
