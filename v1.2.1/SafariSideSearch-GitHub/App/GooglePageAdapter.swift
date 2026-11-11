import WebKit

/// Reflows Google Search inside a narrow view without reducing text size.
enum GooglePageAdapter {
    static func install(in configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(WKUserScript(
            source: source, injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .defaultClient))
    }

    static let source = #"""
    (() => {
        "use strict";
        const isSearch = () =>
            /^https?:$/.test(location.protocol) &&
            /^(www\.)?google\.(com|[a-z]{2}|com\.[a-z]{2}|co\.[a-z]{2}|cat)$/i.test(location.hostname) &&
            ["/", "/search", "/webhp"].includes(location.pathname);
        if (!isSearch()) return;

        const styleID = "sidesearch-google-width";
        const marker = "data-sidesearch-google-fit";
        const css = `
        @media (max-width: 800px) {
          html[${marker}], html[${marker}] body {
            min-width: 0 !important;
            width: 100% !important;
            max-width: 100% !important;
            margin: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] body {
            --center-abs-margin: 12px;
            --center-margin: 12px;
            --center-width: calc(100vw - 24px);
            --rhs-width: calc(100vw - 24px);
            --rhs-margin: 0px;
          }
          html[${marker}] body > div,
          html[${marker}] :is(#main, main, [role="main"], #cnt, #gb) {
            min-width: 0 !important;
            max-width: 100% !important;
            box-sizing: border-box !important;
          }
          html[${marker}] :is(#cnt, #main, main, [role="main"]) {
            margin-inline: 0 !important;
            padding-inline: 0 !important;
          }
          html[${marker}] #rcnt {
            display: block !important;
            width: calc(100% - 24px) !important;
            min-width: 0 !important;
            max-width: calc(100% - 24px) !important;
            margin-inline: 12px !important;
            padding-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] :is(#center_col, #rhs) {
            position: relative !important;
            inset-inline: auto !important;
            float: none !important;
            width: 100% !important;
            min-width: 0 !important;
            max-width: 100% !important;
            margin-inline: 0 !important;
            padding-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] #rhs { margin-top: 24px !important; }
          html[${marker}] :is(#search, #rso, #topstuff, #topads, #bottomads, #botstuff) {
            width: auto !important;
            min-width: 0 !important;
            max-width: 100% !important;
            margin-inline: 0 !important;
            padding-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] :is(#center_col, #rhs, #botstuff) * {
            min-width: 0 !important;
            max-width: 100% !important;
            box-sizing: border-box !important;
            overflow-wrap: anywhere;
          }
          html[${marker}] :is(#center_col, #rhs) :is(h3, p, cite) {
            white-space: normal !important;
          }
          html[${marker}] #searchform {
            position: relative !important;
            inset: auto !important;
            width: 100% !important;
            min-width: 0 !important;
            max-width: 100% !important;
            margin: 0 !important;
            padding-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] form[role="search"] {
            width: calc(100% - 24px) !important;
            min-width: 0 !important;
            max-width: calc(100% - 24px) !important;
            margin-inline: 12px !important;
            padding-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] form[role="search"] :is(.A8SBwf, .RNNXgb) {
            width: 100% !important;
            min-width: 0 !important;
            max-width: 100% !important;
            margin-inline: 0 !important;
            box-sizing: border-box !important;
          }
          html[${marker}] form[role="search"] input[name="q"] {
            min-width: 0 !important;
            max-width: 100% !important;
            box-sizing: border-box !important;
          }
          html[${marker}] #logo {
            position: relative !important;
            inset: auto !important;
            margin: 12px !important;
          }
          html[${marker}] :is(#hdtb, #hdtb-msb, #appbar, #result-stats, #foot, #footer) {
            min-width: 0 !important;
            max-width: 100% !important;
            margin-inline: 0 !important;
            padding-inline: 12px !important;
            box-sizing: border-box !important;
          }
          html[${marker}] :is(#hdtb, #hdtb-msb) { overflow-x: auto !important; }
          html[${marker}] #result-stats { white-space: normal !important; }
        }`;

        function apply() {
            if (!document.documentElement || !document.head) return;
            if (!isSearch()) {
                document.documentElement.removeAttribute(marker);
                return;
            }
            document.documentElement.setAttribute(marker, "");
            if (!document.getElementById(styleID)) {
                const style = document.createElement("style");
                style.id = styleID;
                style.textContent = css;
                document.head.appendChild(style);
            }
            let viewport = document.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement("meta");
                viewport.name = "viewport";
                document.head.appendChild(viewport);
            }
            const content = "width=device-width, initial-scale=1";
            if (viewport.content !== content) viewport.content = content;
        }

        // CSS responds to resizing; the observer only restores the style after
        // Google replaces document fragments during in-page navigation.
        let scheduled = false;
        new MutationObserver(() => {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(() => { scheduled = false; apply(); });
        }).observe(document, { childList: true, subtree: true });
        addEventListener("popstate", apply);
        document.addEventListener("DOMContentLoaded", apply, { once: true });
        apply();
    })();
    """#
}
