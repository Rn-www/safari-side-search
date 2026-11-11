# Glass toolbar and settings implementation plan

**Goal:** Keep the native glass toolbar, full-URL display preference, synchronized current engine and independent default engine. Preserve ordinary panel-local Escape.

**Architecture:** Sandboxed AppKit app + Safari extension, shared preferences and WKWebView. macOS 26+ native glass with a macOS 13–25 fallback. Universal arm64/x86_64 packaging.

## Confirmed constraints

- Every new right-click query uses the saved default. Toolbar/settings current-engine changes affect only the current query.
- Editing always exposes the complete URL; preference changes preserve unfinished input.
- Visible tests run only on the built-in display.
- The user explicitly rejected a separate Escape app on 2026-11-06. The final product contains no helper, global input hook or auxiliary authorization setting. Safari's own Escape handling stays with Safari.
- Do not change Safari settings or publish GitHub changes.

## Tasks

- [x] Implement and verify glass, URL preferences, engine persistence/migration, synchronized controls and one-request selection search.
- [x] Remove the withdrawn helper/runtime, routes, settings, tests and build wiring; regenerate a two-target project.
- [x] Verify 117 retained core checks and settings controls on the built-in display.
- [x] Obtain an independent rollback review, install signed universal 1.2.0 (7), and refresh source/release ZIPs and checksums.
- [x] Restore accessible test conditions: own test programs stopped, test Settings/Finder windows closed. Original Safari window was preserved because the known temporary-window UUID was not current/identifiable. The helper permission stayed off; its stale system-list entry still requires user Touch ID to delete.
