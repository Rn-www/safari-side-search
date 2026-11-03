#!/usr/bin/env python3
"""Dependency-free local build. Never accepts licenses or changes Safari settings."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def run(args):
    subprocess.run([str(arg) for arg in args], check=True)

def developer_tools():
    """Use the caller's selected Xcode; support nonstandard Xcode app names."""
    selected = os.environ.get("DEVELOPER_DIR")
    if not selected:
        result = subprocess.run(["/usr/bin/xcode-select", "-p"], capture_output=True, text=True)
        if result.returncode:
            sys.exit("Select a full Xcode installation or set DEVELOPER_DIR before building.")
        selected = result.stdout.strip()
    developer = Path(selected).expanduser()
    compiler = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    sdk = developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if not compiler.exists() or not sdk.exists():
        sys.exit("A full Xcode installation is required; command-line tools alone are not sufficient.")
    return compiler, sdk

def remove_finder_metadata(bundle):
    # iCloud/File Provider may attach Finder metadata to newly created bundles.
    # These two non-security attributes are forbidden in a code-signed bundle.
    for name in ["com.apple.FinderInfo", "com.apple.ResourceFork"]:
        subprocess.run(["/usr/bin/xattr", "-dr", name, str(bundle)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "build/Safari Side Search.app")
    parser.add_argument("--work-dir", type=Path, default=ROOT / "build/work")
    parser.add_argument("--identity", default="-", help="codesign identity; default ad-hoc")
    parser.add_argument("--integration-test", action="store_true")
    options = parser.parse_args()
    final_app = options.output.resolve()
    work = options.work_dir.resolve()
    compiler, sdk = developer_tools()
    work.mkdir(parents=True, exist_ok=True)
    if final_app.exists():
        # Only replace a prior build of THIS app at an explicitly chosen output path.
        info = final_app / "Contents/Info.plist"
        if not info.exists() or plistlib.loads(info.read_bytes()).get("CFBundleIdentifier") not in ["dev.local.SafariSideSearch", "dev.local.SafariSideSearch.Testing"]:
            sys.exit(f"Refusing to overwrite another application: {final_app}")
    # Code signing must happen outside iCloud/File Provider. Its automatic Finder
    # attributes otherwise race codesign. The verified ZIP contains no xattrs.
    staging = tempfile.TemporaryDirectory(prefix="SafariSideSearch-build-")
    app = Path(staging.name) / final_app.name
    extension = app / "Contents/PlugIns/SafariSideSearchExtension.appex"
    for bundle in ([app] if options.integration_test else [app, extension]):
        (bundle / "Contents/MacOS").mkdir(parents=True)
        (bundle / "Contents/Resources").mkdir()
    flags = ["-sdk", sdk, "-swift-version", "5", "-target", f"{platform.machine()}-apple-macosx13.0",
             "-module-cache-path", work / "module-cache"]
    print("Building native assets…", flush=True)
    asset_tool = work / "make-assets"
    assets = work / "generated-assets"
    run([compiler, *flags, "-parse-as-library", ROOT / "scripts/MakeAssets.swift", "-o", asset_tool])
    run([asset_tool, assets])
    run(["/usr/bin/iconutil", "-c", "icns", assets / "App/Resources/AppIcon.iconset",
         "-o", assets / "App/Resources/AppIcon.icns"])
    app_info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    if options.integration_test:
        app_info["CFBundleIdentifier"] = "dev.local.SafariSideSearch.Testing"
        app_info["CFBundleDisplayName"] = "侧栏搜索测试"
        app_info.pop("CFBundleURLTypes", None)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(app_info))
    shutil.copy2(assets / "App/Resources/AppIcon.icns", app / "Contents/Resources/AppIcon.icns")
    if not options.integration_test:
        shutil.copy2(ROOT / "Extension/Info.plist", extension / "Contents/Info.plist")
        for resource in (ROOT / "Extension/Resources").iterdir():
            if resource.is_file() and resource.name != "toolbar.pdf":
                shutil.copy2(resource, extension / "Contents/Resources" / resource.name)
        shutil.copy2(assets / "Extension/Resources/toolbar.pdf", extension / "Contents/Resources/toolbar.pdf")
    print("Building browser and Safari extension…", flush=True)
    shared = sorted((ROOT / "Shared").glob("*.swift"))
    app_sources = sorted((ROOT / "App").glob("*.swift"))
    extra = ["-D", "TESTING", *sorted((ROOT / "Tests").glob("*Integration.swift"))] if options.integration_test else []
    run([compiler, *flags, "-O", "-module-name", "SafariSideSearch", *app_sources, *shared, *extra,
         "-o", app / "Contents/MacOS/SafariSideSearch"])
    if not options.integration_test:
        run([compiler, *flags, "-O", "-parse-as-library", "-application-extension",
             "-module-name", "SafariSideSearchExtension", *shared, ROOT / "Extension/SafariExtensionHandler.swift",
             "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-o", extension / "Contents/MacOS/SafariSideSearchExtension"])
    print("Signing local build…", flush=True)
    remove_finder_metadata(app)
    sign_targets = [(app, ROOT / "App/App.entitlements")]
    if not options.integration_test: sign_targets.insert(0, (extension, ROOT / "Extension/Extension.entitlements"))
    for bundle, entitlements in sign_targets:
        remove_finder_metadata(app)
        run(["/usr/bin/codesign", "--force", "--sign", options.identity, "--timestamp=none",
             "--entitlements", entitlements, bundle])
    remove_finder_metadata(app)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    archive = final_app.with_suffix(".zip")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
        for file in app.rglob("*"):
            if file.is_file(): package.write(file, file.relative_to(app.parent))
    if final_app.exists(): shutil.rmtree(final_app)
    shutil.copytree(app, final_app, copy_function=shutil.copy)
    (work / "build.json").write_text(json.dumps({"app": str(final_app), "archive": str(archive), "architecture": platform.machine(),
        "signature": "ad-hoc" if options.identity == "-" else "development", "integration_test": options.integration_test}, indent=2))
    staging.cleanup()
    print(f"Built: {final_app}\nVerified package: {archive}", flush=True)

if __name__ == "__main__": main()
