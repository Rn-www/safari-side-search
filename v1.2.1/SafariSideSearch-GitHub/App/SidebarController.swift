import AppKit

private final class SidebarPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class SidebarController: NSObject, NSWindowDelegate {
    let browser = BrowserViewController()
    private let panel: SidebarPanel
    private var timer: Timer?
    private var wantsVisible = false
    private var sourceWindowID: UInt32?
    private var positioning = false
    private var followSafari = true
    private var width: CGFloat

    override init() {
        let stored = UserDefaults.standard.double(forKey: "panelWidth")
        width = stored > 0 ? min(max(stored, PanelLayout.minimumWidth), PanelLayout.maximumWidth) : PanelLayout.defaultWidth
        panel = SidebarPanel(contentRect: CGRect(x: 0, y: 0, width: width, height: 700),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        panel.title = "Safari 侧栏搜索"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: PanelLayout.minimumWidth, height: 280)
        panel.maxSize = NSSize(width: PanelLayout.maximumWidth, height: 5000)
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.contentViewController = browser
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(type)?.isHidden = true
        }
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        browser.onClose = { [weak self] in self?.hide() }
        browser.onFollowChanged = { [weak self] enabled in
            self?.followSafari = enabled
            self?.tick()
        }
        browser.setFollow(true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged),
                                                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func search(_ request: SearchRequest) {
        chooseSourceWindow()
        wantsVisible = true
        placePanel()
        browser.searchSelection(request)
        panel.makeKeyAndOrderFront(nil)
    }

    func show() {
        chooseSourceWindow()
        wantsVisible = true
        placePanel()
        panel.makeKeyAndOrderFront(nil)
        if browser.webView.url == nil { browser.focusAddress() }
    }

    func hide() {
        wantsVisible = false
        panel.orderOut(nil)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.activate(options: [])
    }

    private func chooseSourceWindow() {
        let windows = SafariWindowTracker.windows()
        sourceWindowID = windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.id ?? windows.first?.id
    }

    @objc private func applicationChanged() { tick() }

    private func tick() {
        guard wantsVisible else { return }
        let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let own = Bundle.main.bundleIdentifier
        guard foreground == "com.apple.Safari" || foreground == own else {
            panel.orderOut(nil)
            return
        }
        let windows = SafariWindowTracker.windows()
        if let sourceID = sourceWindowID {
            guard let source = windows.first(where: { $0.id == sourceID }) else {
                panel.orderOut(nil)
                return
            }
            // A different Safari window is in front: wait until the source window returns.
            if foreground == "com.apple.Safari", windows.first?.id != sourceID {
                panel.orderOut(nil)
                return
            }
            if followSafari { position(along: source.frame) }
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func placePanel() {
        if followSafari, let source = SafariWindowTracker.windows().first(where: { $0.id == sourceWindowID }) {
            position(along: source.frame)
        } else if !panel.isVisible, let screen = NSScreen.main ?? NSScreen.screens.first {
            positioning = true
            panel.setFrame(PanelLayout.fallback(screen: screen.visibleFrame, width: width), display: true)
            positioning = false
        }
    }

    private func position(along frame: CGRect) {
        guard !panel.inLiveResize, let screen = SafariWindowTracker.screen(for: frame) else { return }
        let target = PanelLayout.frame(safari: frame, visibleScreen: screen.visibleFrame, width: width)
        guard panel.frame != target else { return }
        positioning = true
        panel.setFrame(target, display: true)
        positioning = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidResize(_ notification: Notification) {
        if !positioning {
            width = min(max(panel.frame.width, PanelLayout.minimumWidth), PanelLayout.maximumWidth)
            UserDefaults.standard.set(width, forKey: "panelWidth")
        }
    }
    func windowDidEndLiveResize(_ notification: Notification) { tick() }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { hide(); return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "l": browser.focusAddress()
        case "r": browser.reloadPage()
        case "[": browser.goBack()
        case "]": browser.goForward()
        case "w": hide()
        case ",": browser.openSettings()
        default: return false
        }
        return true
    }
}
