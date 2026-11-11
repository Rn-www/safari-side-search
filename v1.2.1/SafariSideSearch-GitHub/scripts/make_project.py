#!/usr/bin/env python3
"""Generate a small, conventional Xcode project without external packages."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def uid(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

def array(values):
    return "(" + ", ".join(values) + ")"

def add(key, isa, **fields):
    objects[uid(key)] = "{isa = " + isa + "; " + " ".join(f"{k} = {v};" for k, v in fields.items()) + "}"
    return uid(key)

def ref(path, kind):
    return add("file:" + path, "PBXFileReference", lastKnownFileType=quoted(kind), path=quoted(path), sourceTree=quoted("<group>"))

def buildfile(path, kind, target):
    return add("build:" + target + path, "PBXBuildFile", fileRef=ref(path, kind))

def configlist(key, settings):
    configs = []
    for name in ["Debug", "Release"]:
        values = {**settings, "SWIFT_OPTIMIZATION_LEVEL": quoted("-Onone" if name == "Debug" else "-O")}
        encoded = "{" + " ".join(f"{k} = {v};" for k, v in values.items()) + "}"
        configs.append(add(key + name, "XCBuildConfiguration", name=quoted(name), buildSettings=encoded))
    return add(key + "list", "XCConfigurationList", buildConfigurations=array(configs),
               defaultConfigurationIsVisible="0", defaultConfigurationName=quoted("Release"))

def main():
    shared = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "Shared").glob("*.swift"))]
    sources = {"app": shared + [str(p.relative_to(ROOT)) for p in sorted((ROOT / "App").glob("*.swift"))],
               "extension": shared + ["Extension/SafariExtensionHandler.swift"]}
    resources = {"app": ["App/Resources/AppIcon.icns"],
                 "extension": ["Extension/Resources/content.js", "Extension/Resources/toolbar.pdf"]}
    products = {}
    for target in ["app", "extension"]:
        product = "Safari Side Search.app" if target == "app" else "SafariSideSearchExtension.appex"
        products[target] = add("product:" + target, "PBXFileReference", explicitFileType=quoted("wrapper.application" if target == "app" else "wrapper.app-extension"),
                               path=quoted(product), sourceTree="BUILT_PRODUCTS_DIR")
    for target in ["extension", "app"]:
        sourcephase = add(target + "Sources", "PBXSourcesBuildPhase", buildActionMask="2147483647",
                          files=array([buildfile(p, "sourcecode.swift", target) for p in sources[target]]), runOnlyForDeploymentPostprocessing="0")
        resourcephase = add(target + "Resources", "PBXResourcesBuildPhase", buildActionMask="2147483647",
                            files=array([buildfile(p, "file" if p.endswith("icns") else "text", target) for p in resources[target]]),
                            runOnlyForDeploymentPostprocessing="0")
        phases = [sourcephase, resourcephase]
        dependencies = []
        if target == "app":
            embed = add("embedbuild", "PBXBuildFile", fileRef=products["extension"], settings="{ATTRIBUTES = (RemoveHeadersOnCopy, );}")
            phases.append(add("embedphase", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath=quoted(""),
                              dstSubfolderSpec="13", files=array([embed]), name=quoted("Embed App Extensions"), runOnlyForDeploymentPostprocessing="0"))
            proxy = add("extensionProxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1",
                        remoteGlobalIDString=uid("target:extension"), remoteInfo=quoted("SafariSideSearchExtension"))
            dependencies.append(add("dependency", "PBXTargetDependency", target=uid("target:extension"), targetProxy=proxy))
        folder = "App" if target == "app" else "Extension"
        settings = {"PRODUCT_BUNDLE_IDENTIFIER": quoted("dev.local.SafariSideSearch" + (".Extension" if target == "extension" else "")),
                    "PRODUCT_NAME": quoted("Safari Side Search" if target == "app" else "SafariSideSearchExtension"),
                    "EXECUTABLE_NAME": quoted("SafariSideSearch" if target == "app" else "SafariSideSearchExtension"),
                    "PRODUCT_MODULE_NAME": quoted("SafariSideSearch" if target == "app" else "SafariSideSearchExtension"),
                    "INFOPLIST_FILE": quoted(folder + "/Info.plist"), "GENERATE_INFOPLIST_FILE": "NO",
                    "CODE_SIGN_ENTITLEMENTS": quoted(folder + "/" + folder + ".entitlements"),
                    "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": quoted("Apple Development"),
                    "SWIFT_VERSION": "5.0", "MACOSX_DEPLOYMENT_TARGET": "13.0", "SDKROOT": "macosx",
                    "ENABLE_APP_SANDBOX": "YES", "ENABLE_HARDENED_RUNTIME": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": quoted("$(inherited) @executable_path/../Frameworks"),
                    "SKIP_INSTALL": "NO" if target == "app" else "YES"}
        if target == "app": settings["ENABLE_OUTGOING_NETWORK_CONNECTIONS"] = "YES"
        else: settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
        config = configlist(target, settings)
        add("target:" + target, "PBXNativeTarget", name=quoted("Safari Side Search" if target == "app" else "SafariSideSearchExtension"),
            buildConfigurationList=config, buildPhases=array(phases), buildRules="()", dependencies=array(dependencies),
            productName=settings["PRODUCT_NAME"], productReference=products[target],
            productType=quoted("com.apple.product-type.application" if target == "app" else "com.apple.product-type.app-extension"))
    for path in ["App/Info.plist", "Extension/Info.plist", "App/App.entitlements", "Extension/Extension.entitlements"]:
        ref(path, "text.plist.xml")
    fileids = sorted(ident for ident, obj in objects.items() if "PBXFileReference" in obj and "BUILT_PRODUCTS_DIR" not in obj)
    productgroup = add("productsgroup", "PBXGroup", children=array(list(products.values())), name=quoted("Products"), sourceTree=quoted("<group>"))
    group = add("mainGroup", "PBXGroup", children=array(fileids + [productgroup]), sourceTree=quoted("<group>"))
    projectconfig = configlist("project", {"CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "5.0", "MACOSX_DEPLOYMENT_TARGET": "13.0"})
    add("project", "PBXProject", attributes="{LastUpgradeCheck = 2700;}", buildConfigurationList=projectconfig,
        compatibilityVersion=quoted("Xcode 14.0"), developmentRegion=quoted("zh_CN"), hasScannedForEncodings="0",
        knownRegions=array([quoted("zh_CN"), quoted("en"), quoted("Base")]), mainGroup=group,
        productRefGroup=productgroup, projectDirPath=quoted(""), projectRoot=quoted(""),
        targets=array([uid("target:app"), uid("target:extension")]))
    project = ROOT / "SafariSideSearch.xcodeproj"
    project.mkdir(exist_ok=True)
    text = "// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
    text += "\n".join(f"{ident} = {obj};" for ident, obj in objects.items())
    text += "\n}; rootObject = " + uid("project") + ";}\n"
    (project / "project.pbxproj").write_text(text)
    scheme = project / "xcshareddata/xcschemes"
    scheme.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:app")}" BuildableName="Safari Side Search.app" BlueprintName="Safari Side Search" ReferencedContainer="container:SafariSideSearch.xcodeproj"/>'
    (scheme / "Safari Side Search.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
    print(project)

if __name__ == "__main__": main()
