import AppKit
import WebKit

final class BrowserViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?
    var onFollowChanged: ((Bool) -> Void)?
    var onNavigationFinished: ((URL) -> Void)?
    var onNavigationFailed: (() -> Void)?
    private(set) var redirectedWindowCount = 0
    private(set) var lastErrorMessage: String?
    private var observations: [NSKeyValueObservation] = []
    let address = SidebarAddressField()
    let settingsButton = NSButton()
    private let back = NSButton()
    private let forward = NSButton()
    private let reload = NSButton()
    private let follow = NSButton()
    private let status = NSTextField(labelWithString: "准备就绪")
    private let progress = NSProgressIndicator()
    private let errorBox = NSVisualEffectView()
    private let errorDescription = NSTextField(wrappingLabelWithString: "")
    private var pendingURL: URL?
    let enginePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let engineStore: SearchEngineStore
    let preferences: BrowserPreferences
    private var preferenceObservers: [NSObjectProtocol] = []
    private var lastObservedEngine: SearchEngine
    private(set) var settingsWindowController: SettingsWindowController?
    private(set) var engineEditor: SearchEngineEditorController?
    private(set) var currentSearch: SearchRequest?

    init(engineStore: SearchEngineStore = .shared, preferences: BrowserPreferences = .shared) {
        self.engineStore = engineStore
        self.preferences = preferences
        lastObservedEngine = engineStore.selected
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // window.open from explicit clicks is redirected into this same view.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        GooglePageAdapter.install(in: configuration)
        SearchPageAdapter.install(in: configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityLabel("侧栏网页")
        preferenceObservers.append(NotificationCenter.default.addObserver(forName: SearchEngineStore.didChange,
            object: engineStore, queue: nil) { [weak self] _ in self?.engineStoreChanged() })
        preferenceObservers.append(NotificationCenter.default.addObserver(forName: BrowserPreferences.didChange,
            object: preferences, queue: nil) { [weak self] _ in self?.refreshAddressDisplay() })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { for observer in preferenceObservers { NotificationCenter.default.removeObserver(observer) } }

    override func loadView() {
        let root = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 430, height: 700))
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        view = root

        let icon = NSImageView(image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: "侧栏搜索")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        configure(follow, symbol: "pin.fill", tooltip: "跟随 Safari 窗口", action: #selector(toggleFollow))
        follow.setButtonType(.toggle)
        follow.state = .on
        configure(settingsButton, symbol: "gearshape", tooltip: "侧栏设置 (⌘,)", action: #selector(openSettings))
        let close = NSButton()
        configure(close, symbol: "xmark", tooltip: "关闭侧栏 (Esc)", action: #selector(closePanel))
        enginePicker.font = .systemFont(ofSize: 11)
        enginePicker.controlSize = .small
        enginePicker.bezelStyle = .texturedRounded
        enginePicker.target = self
        enginePicker.action = #selector(changeEngine)
        enginePicker.setAccessibilityLabel("搜索引擎")
        enginePicker.isBordered = false
        enginePicker.widthAnchor.constraint(equalToConstant: 100).isActive = true
        enginePicker.cell?.lineBreakMode = .byTruncatingTail
        let engineGlass = GlassChrome.capsule(enginePicker)
        let actions = NSStackView(views: [follow, settingsButton])
        actions.spacing = 2
        actions.alignment = .centerY
        let actionsGlass = GlassChrome.capsule(actions, insets: NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4))
        let closeGlass = GlassChrome.capsule(close, insets: NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4))
        let heading = NSStackView(views: [icon, title, spacer, engineGlass, actionsGlass, closeGlass])
        heading.distribution = .fill
        heading.spacing = 6
        heading.alignment = .centerY
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        actionsGlass.widthAnchor.constraint(equalToConstant: 62).isActive = true
        closeGlass.widthAnchor.constraint(equalToConstant: 34).isActive = true
        for group in [engineGlass, actionsGlass, closeGlass] { group.heightAnchor.constraint(equalToConstant: 32).isActive = true }

        configure(back, symbol: "chevron.left", tooltip: "后退 (⌘[)", action: #selector(goBack))
        configure(forward, symbol: "chevron.right", tooltip: "前进 (⌘])", action: #selector(goForward))
        configure(reload, symbol: "arrow.clockwise", tooltip: "重新载入 (⌘R)", action: #selector(reloadPage))
        back.isEnabled = false
        forward.isEnabled = false
        address.font = .systemFont(ofSize: 13)
        address.isBordered = false
        address.isBezeled = false
        address.drawsBackground = false
        address.focusRingType = .exterior
        address.cell?.isScrollable = true
        address.cell?.usesSingleLineMode = true
        address.cell?.sendsActionOnEndEditing = false
        address.target = self
        address.action = #selector(submitAddress)
        address.delegate = self
        address.onFocus = { [weak self] in self?.revealAddressForEditing() }
        rebuildEnginePicker()
        let external = NSButton()
        configure(external, symbol: "safari", tooltip: "在 Safari 中打开当前网页", action: #selector(openInSafari))
        let backGroup = NSStackView(views: [back, forward])
        backGroup.spacing = 0
        backGroup.alignment = .centerY
        let endGroup = NSStackView(views: [reload, external])
        endGroup.spacing = 0
        endGroup.alignment = .centerY
        let backGlass = GlassChrome.capsule(backGroup, insets: NSEdgeInsets(top: 5, left: 4, bottom: 5, right: 4))
        let searchIcon = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!,
                                  target: self, action: #selector(focusAddress))
        searchIcon.isBordered = false
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.toolTip = "搜索或输入网址"
        searchIcon.setAccessibilityLabel("搜索或输入网址")
        searchIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let clear = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)!,
                             target: self, action: #selector(clearAddress))
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        clear.toolTip = "清空地址栏"
        clear.setAccessibilityLabel("清空地址栏")
        clear.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let addressContents = NSStackView(views: [searchIcon, address, clear])
        addressContents.distribution = .fill
        addressContents.alignment = .centerY
        addressContents.spacing = 6
        let addressGlass = GlassChrome.capsule(addressContents, insets: NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 6), radius: 18)
        let endGlass = GlassChrome.capsule(endGroup, insets: NSEdgeInsets(top: 5, left: 4, bottom: 5, right: 4))
        let navigation = NSStackView(views: [backGlass, addressGlass, endGlass])
        navigation.distribution = .fill
        navigation.spacing = 8
        navigation.alignment = .centerY
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressGlass.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        backGlass.widthAnchor.constraint(equalToConstant: 60).isActive = true
        endGlass.widthAnchor.constraint(equalToConstant: 60).isActive = true
        address.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
        for group in [backGlass, addressGlass, endGlass] { group.heightAnchor.constraint(equalToConstant: 36).isActive = true }
        let rows = NSStackView(views: [heading, navigation])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        let toolbar = GlassChrome.container(rows)

        let separator = NSBox()
        separator.boxType = .separator
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.isIndeterminate = false
        progress.isHidden = true
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle

        for element in [toolbar, separator, webView, status, progress] {
            element.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(element)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            heading.widthAnchor.constraint(equalTo: rows.widthAnchor),
            navigation.widthAnchor.constraint(equalTo: rows.widthAnchor),
            heading.heightAnchor.constraint(equalToConstant: 32),
            navigation.heightAnchor.constraint(equalToConstant: 36),
            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -5),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            status.heightAnchor.constraint(equalToConstant: 13),
            progress.topAnchor.constraint(equalTo: webView.topAnchor),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])
        buildErrorView(in: root)
        observeBrowser()
    }

    private func configure(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func buildErrorView(in root: NSView) {
        errorBox.material = .windowBackground
        errorBox.state = .active
        errorBox.isHidden = true
        errorBox.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(errorBox)
        let symbol = NSImageView(image: NSImage(systemSymbolName: "wifi.exclamationmark", accessibilityDescription: nil)!)
        symbol.contentTintColor = .secondaryLabelColor
        let heading = NSTextField(labelWithString: "无法打开网页")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        errorDescription.font = .systemFont(ofSize: 12)
        errorDescription.textColor = .secondaryLabelColor
        errorDescription.alignment = .center
        let retry = NSButton(title: "重新尝试", target: self, action: #selector(reloadPage))
        retry.bezelStyle = .rounded
        let stack = NSStackView(views: [symbol, heading, errorDescription, retry])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        errorBox.addSubview(stack)
        NSLayoutConstraint.activate([
            errorBox.topAnchor.constraint(equalTo: webView.topAnchor),
            errorBox.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            errorBox.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            errorBox.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: errorBox.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorBox.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: errorBox.widthAnchor, constant: -56),
            errorDescription.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        ])
    }

    private func observeBrowser() {
        observations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.refreshControls() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.refreshControls() },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.refreshControls() },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.refreshControls() },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.refreshControls() }
        ]
    }

    private func refreshControls() {
        back.isEnabled = webView.canGoBack
        forward.isEnabled = webView.canGoForward
        progress.doubleValue = webView.estimatedProgress
        progress.isHidden = !webView.isLoading
        reload.image = NSImage(systemSymbolName: webView.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: nil)
        reload.toolTip = webView.isLoading ? "停止载入" : "重新载入 (⌘R)"
        refreshAddressDisplay()
        if !errorBox.isHidden { return }
        let host = webView.url?.host ?? "侧栏浏览器"
        status.stringValue = webView.isLoading ? "正在载入 · \(host)" : host
    }

    func load(_ url: URL) {
        _ = view
        lastErrorMessage = nil
        pendingURL = url
        errorBox.isHidden = true
        refreshAddressDisplay(preferPending: true)
        webView.load(URLRequest(url: url))
    }

    private var displayedURL: URL? {
        webView.isLoading || !errorBox.isHidden ? (pendingURL ?? webView.url) : (webView.url ?? pendingURL)
    }

    private func refreshAddressDisplay(preferPending: Bool = false) {
        guard isViewLoaded else { return }
        let url = preferPending ? (pendingURL ?? webView.url) : displayedURL
        address.toolTip = url?.absoluteString
        guard address.currentEditor() == nil else { return }
        let text = url.map { AddressDisplay.text(for: $0, showFullURL: preferences.showFullURL) } ?? ""
        if address.stringValue != text { address.stringValue = text }
    }

    private func revealAddressForEditing() {
        guard address.currentEditor() == nil, let url = displayedURL else { return }
        address.stringValue = url.absoluteString
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.refreshAddressDisplay() }
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: engineStore, preferences: preferences)
        }
        settingsWindowController?.show(relativeTo: view.window)
    }

    func search(_ request: SearchRequest) {
        currentSearch = request
        load(engineStore.selected.url(for: request))
    }

    func searchSelection(_ request: SearchRequest) {
        // Clear the previous query before the selection notification so changing
        // engines cannot send the old query to the default engine.
        currentSearch = nil
        engineStore.select(id: engineStore.defaultEngine.id)
        view.window?.makeFirstResponder(webView)
        search(request)
    }

    func submit(_ text: String) {
        if let website = AddressInput.websiteURL(for: text) {
            currentSearch = nil
            load(website)
        } else if let request = SearchRequest(query: text) {
            search(request)
        }
    }

    private func rebuildEnginePicker() {
        enginePicker.menu = SearchEngineMenu.make(store: engineStore, management: true)
        enginePicker.selectItem(at: engineStore.engines.firstIndex(where: { $0.id == engineStore.selected.id }) ?? 0)
        enginePicker.toolTip = "当前使用 \(engineStore.selected.name)；点击切换或添加搜索引擎"
        let placeholder = "\(engineStore.selected.name) 搜索或输入网址"
        address.placeholderString = placeholder
        address.setAccessibilityLabel(placeholder)
    }

    @objc private func changeEngine() {
        guard let command = enginePicker.selectedItem?.representedObject as? String else { return }
        switch command {
        case "add", "edit":
            let editing = command == "edit" ? engineStore.selected : nil
            rebuildEnginePicker()
            DispatchQueue.main.async { [weak self] in self?.showEngineEditor(editing) }
        case "delete":
            engineStore.removeCustom(id: engineStore.selected.id)
        default:
            guard engineStore.select(id: command) else { rebuildEnginePicker(); return }
        }
    }

    private func engineStoreChanged() {
        let previous = lastObservedEngine
        lastObservedEngine = engineStore.selected
        guard isViewLoaded else { return }
        rebuildEnginePicker()
        let current = engineStore.selected
        if previous.id != current.id || previous.urlTemplate != current.urlTemplate,
           let request = currentSearch { search(request) }
    }

    private func showEngineEditor(_ engine: SearchEngine?) {
        guard engineEditor == nil, view.window != nil else { return }
        let editor = SearchEngineEditorController(engine: engine)
        editor.onSave = { [weak self] name, template in
            guard let self = self else { return }
            try self.engineStore.saveInput(name: name, input: template, editingID: engine?.id)
        }
        editor.onClose = { [weak self] in self?.engineEditor = nil }
        engineEditor = editor
        presentAsSheet(editor)
    }

    @objc func focusAddress() {
        revealAddressForEditing()
        view.window?.makeFirstResponder(address)
        address.selectText(nil)
    }

    @objc private func clearAddress() {
        view.window?.makeFirstResponder(address)
        address.stringValue = ""
        address.currentEditor()?.string = ""
    }

    func setFollow(_ enabled: Bool) {
        _ = view
        follow.state = enabled ? .on : .off
        follow.contentTintColor = enabled ? .controlAccentColor : .secondaryLabelColor
        follow.toolTip = enabled ? "正在跟随 Safari，点击可自由放置" : "自由放置，点击跟随 Safari"
    }

    @objc func goBack() { errorBox.isHidden = true; webView.goBack() }
    @objc func goForward() { errorBox.isHidden = true; webView.goForward() }
    @objc func reloadPage() {
        if webView.isLoading { webView.stopLoading(); return }
        if !errorBox.isHidden, let url = pendingURL { load(url) }
        else { webView.reload() }
    }
    @objc private func submitAddress() {
        let text = address.stringValue
        view.window?.makeFirstResponder(webView)
        submit(text)
    }
    @objc private func toggleFollow() {
        let enabled = follow.state == .on
        setFollow(enabled)
        onFollowChanged?(enabled)
    }
    @objc private func closePanel() { onClose?() }
    @objc func openInSafari() {
        guard let url = webView.url, ["http", "https"].contains(url.scheme ?? ""),
              let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        let allowed = ["https", "http", "about"].contains(scheme)
        #if TESTING
        let fixture = scheme == "file"
        #else
        let fixture = false
        #endif
        if allowed || fixture {
            if action.targetFrame == nil {
                redirectedWindowCount += 1
                decisionHandler(.cancel)
                load(url)
            } else {
                if action.targetFrame?.isMainFrame == true { pendingURL = url }
                decisionHandler(.allow)
            }
            return
        }
        decisionHandler(.cancel)
        guard action.navigationType == .linkActivated, let window = view.window,
              !["javascript", "data", "file", "safarisidesearch"].contains(scheme) else { return }
        let alert = NSAlert()
        alert.messageText = "在其他应用中打开？"
        alert.informativeText = "此链接使用 \(scheme) 协议。"
        alert.addButton(withTitle: "打开")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") {
            redirectedWindowCount += 1
            load(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorBox.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControls()
        if let url = webView.url { onNavigationFinished?(url) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError(NSError(domain: "SideSearch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "网页进程已停止，请重新载入。 "]))
    }

    private func showError(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        lastErrorMessage = error.localizedDescription
        errorDescription.stringValue = error.localizedDescription
        status.stringValue = "载入失败 · 可重新尝试"
        errorBox.isHidden = false
        refreshAddressDisplay()
        progress.isHidden = true
        onNavigationFailed?()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window = view.window else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = String(message.prefix(2000))
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window = view.window else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = String(message.prefix(2000))
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
}
