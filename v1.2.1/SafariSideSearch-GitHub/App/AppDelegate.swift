import AppKit
import SafariServices

@main final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var sidebar = SidebarController()
    private var statusItem: NSStatusItem?
    private var setupWindow: NSWindow?
    private let extensionStatus = NSTextField(wrappingLabelWithString: "正在检查扩展状态…")
    private var handledURL = false
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if TESTING
        TestingAppMenus.install()
        BrowserIntegration.run()
        #else
        buildMenus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self, !self.handledURL else { return }
            self.showSetup()
        }
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let request = SearchRequest(deepLink: url) {
                handledURL = true
                sidebar.search(request)
            } else if url.scheme == "safarisidesearch", url.host == "show",
                      url.query == nil, url.path.isEmpty {
                handledURL = true
                sidebar.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if TESTING
        return false
        #else
        showSetup()
        return true
        #endif
    }

    private func buildMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Safari 侧栏搜索")
        statusItem?.button?.toolTip = "Safari 侧栏搜索"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示侧栏", action: #selector(showSidebar), keyEquivalent: "")
        menu.addItem(withTitle: "侧栏设置…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(withTitle: "使用说明与扩展设置…", action: #selector(showSetup), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出侧栏搜索", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem?.menu = menu

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出侧栏搜索", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"),
                                      ("剪切", #selector(NSText.cut(_:)), "x"),
                                      ("复制", #selector(NSText.copy(_:)), "c"),
                                      ("粘贴", #selector(NSText.paste(_:)), "v"),
                                      ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSidebar() { sidebar.show() }
    @objc private func showSettings() { sidebar.browser.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSetup() {
        if setupWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 470),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Safari 侧栏搜索"
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            let background = NSVisualEffectView()
            background.material = .sidebar
            background.state = .active
            window.contentView = background
            let icon = NSImageView(image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)!)
            icon.contentTintColor = .controlAccentColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            let title = NSTextField(labelWithString: "阅读不停，随手查找")
            title.font = .systemFont(ofSize: 23, weight: .semibold)
            let body = NSTextField(wrappingLabelWithString: "在 Safari 里选中文字，右键选择\n“在侧栏搜索”，使用默认引擎查询。\n\n顶部菜单可临时切换当前查询的引擎，\n齿轮可设置默认引擎和完整网址显示。\n搜索结果和后续网页都在侧栏内打开。")
            body.alignment = .center
            body.font = .systemFont(ofSize: 13)
            body.textColor = .secondaryLabelColor
            extensionStatus.alignment = .center
            extensionStatus.font = .systemFont(ofSize: 11)
            extensionStatus.textColor = .secondaryLabelColor
            let settings = NSButton(title: "打开 Safari 扩展设置", target: self, action: #selector(openExtensionSettings))
            settings.bezelStyle = .rounded
            settings.keyEquivalent = "\r"
            let preview = NSButton(title: "先试试侧栏", target: self, action: #selector(trySidebar))
            preview.bezelStyle = .rounded
            let footnote = NSTextField(wrappingLabelWithString: "启用扩展后，请允许它在你需要选词的网站上运行。\n面板使用独立登录状态；菜单栏图标可随时重新打开。")
            footnote.font = .systemFont(ofSize: 10)
            footnote.textColor = .tertiaryLabelColor
            footnote.alignment = .center
            let stack = NSStackView(views: [icon, title, body, extensionStatus, settings, preview, footnote])
            stack.orientation = .vertical
            stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
                stack.widthAnchor.constraint(equalToConstant: 370)
            ])
            window.center()
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: "dev.local.SafariSideSearch.Extension") { [weak self] state, error in
            DispatchQueue.main.async {
                if let state = state {
                    self?.extensionStatus.stringValue = state.isEnabled ? "扩展已启用 ✓" : "下一步：在 Safari 设置中勾选扩展"
                } else {
                    self?.extensionStatus.stringValue = "请在 Safari → 设置 → 扩展中查看启用状态"
                }
            }
        }
    }

    @objc private func trySidebar() {
        setupWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        sidebar.show()
    }

    @objc private func openExtensionSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "dev.local.SafariSideSearch.Extension") { [weak self] error in
            if error != nil {
                DispatchQueue.main.async {
                    self?.extensionStatus.stringValue = "请手动打开 Safari → 设置 → 扩展"
                }
            }
        }
    }
}
