#!/usr/bin/env python3
"""Run core checks or opt-in WebKit integration tests using only the stdlib."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading

from build import ROOT, developer_tools

def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["core", "browser", "layout", "live-layout", "engines", "settings", "all"], default="core")
    parser.add_argument("--work-dir", type=Path, default=ROOT / "build/tests")
    options = parser.parse_args()
    work = options.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if options.suite in ["core", "all"]:
        compiler, sdk = developer_tools()
        binary = work / "core-tests"
        run([compiler, "-sdk", sdk, "-swift-version", "5", "-module-cache-path", work / "module-cache",
             *sorted((ROOT / "Shared").glob("*.swift")), ROOT / "App/SearchEngineStore.swift",
             ROOT / "App/BrowserPreferences.swift", ROOT / "App/AddressDisplay.swift",
             ROOT / "App/PanelLayout.swift", ROOT / "Tests/CoreTests.swift",
             "-o", binary])
        run([binary], timeout=30)
    if options.suite == "core": return

    # A separate testing bundle ID and no embedded extension prevent tests from
    # changing the installed Safari extension. All visible windows use built-in display.
    app = work / "Browser Tests.app"
    run([sys.executable, ROOT / "scripts/build.py", "--integration-test", "--output", app,
         "--work-dir", work / "app-work"])
    binary = app / "Contents/MacOS/SafariSideSearch"
    if options.suite in ["browser", "all"]:
        handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / "Tests/Fixtures"))
        try:
            server = ThreadingHTTPServer(("127.0.0.1", 18761), handler)
        except OSError as error:
            sys.exit(f"Cannot bind local fixture server on 127.0.0.1:18761: {error}")
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            run([binary, "--fixtures-only", "--exit-on-completion"], timeout=70)
        finally:
            server.shutdown()
            server.server_close()
    if options.suite in ["layout", "all"]:
        run([binary, "--google-layout-test"], timeout=70)
        run([binary, "--search-layout-test"], timeout=70)
    if options.suite == "live-layout":
        run([binary, "--live-layout-test"], timeout=110)
    if options.suite in ["engines", "all"]:
        run([binary, "--search-engine-test"], timeout=70)
    if options.suite in ["settings", "all"]:
        run([binary, "--settings-test"], timeout=70)

if __name__ == "__main__": main()
