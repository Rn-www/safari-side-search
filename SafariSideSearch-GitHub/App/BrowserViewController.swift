import AppKit
import WebKit

final class BrowserViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, NSSearchFieldDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?
    var onFollowChanged: ((Bool) -> Void)?
    var onNavigationFinished: ((URL) -> Void)?
    var onNavigationFailed: (() -> Void)?
    private(set) var redirectedWindowCount = 0
    private(set) var lastErrorMessage: String?
    private var observations: [NSKeyValueObservation] = []
    private let address = NSSearchField()
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
    private(set) var engineEditor: SearchEngineEditorController?
    private(set) var currentSearch: SearchRequest?

    init(engineStore: SearchEngineStore = .shared) {
        self.engineStore = engineStore
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configure(follow, symbol: "pin.fill", tooltip: "跟随 Safari 窗口", action: #selector(toggleFollow))
        follow.setButtonType(.toggle)
        follow.state = .on
        follow.bezelStyle = .recessed
        let close = NSButton()
        configure(close, symbol: "xmark", tooltip: "关闭侧栏 (Esc)", action: #selector(closePanel))
        enginePicker.font = .systemFont(ofSize: 11)
        enginePicker.controlSize = .small
        enginePicker.bezelStyle = .texturedRounded
        enginePicker.target = self
        enginePicker.action = #selector(changeEngine)
        enginePicker.setAccessibilityLabel("搜索引擎")
        enginePicker.widthAnchor.constraint(equalToConstant: 116).isActive = true
        enginePicker.cell?.lineBreakMode = .byTruncatingTail
        let heading = NSStackView(views: [icon, title, spacer, enginePicker, follow, close])
        heading.spacing = 8
        heading.alignment = .centerY
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        configure(back, symbol: "chevron.left", tooltip: "后退 (⌘[)", action: #selector(goBack))
        configure(forward, symbol: "chevron.right", tooltip: "前进 (⌘])", action: #selector(goForward))
        configure(reload, symbol: "arrow.clockwise", tooltip: "重新载入 (⌘R)", action: #selector(reloadPage))
        back.isEnabled = false
        forward.isEnabled = false
        address.font = .systemFont(ofSize: 12)
        address.focusRingType = .exterior
        address.sendsSearchStringImmediately = false
        address.sendsWholeSearchString = true
        address.target = self
        address.action = #selector(submitAddress)
        address.delegate = self
        rebuildEnginePicker()
        let external = NSButton()
        configure(external, symbol: "safari", tooltip: "在 Safari 中打开当前网页", action: #selector(openInSafari))
        let navigation = NSStackView(views: [back, forward, address, reload, external])
        navigation.spacing = 4
        navigation.alignment = .centerY
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        address.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

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

        for element in [heading, navigation, separator, webView, status, progress] {
            element.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(element)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            heading.heightAnchor.constraint(equalToConstant: 27),
            navigation.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 7),
            navigation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            navigation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            navigation.heightAnchor.constraint(equalToConstant: 28),
            separator.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 10),
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
        button.widthAnchor.constraint(equalToConstant: 25).isActive = true
        button.heightAnchor.constraint(equalToConstant: 25).isActive = true
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
        if !errorBox.isHidden { return }
        if address.currentEditor() == nil {
            let displayURL = webView.isLoading ? (pendingURL ?? webView.url) : (webView.url ?? pendingURL)
            address.stringValue = displayURL?.absoluteString ?? ""
        }
        let host = webView.url?.host ?? "侧栏浏览器"
        status.stringValue = webView.isLoading ? "正在载入 · \(host)" : host
    }

    func load(_ url: URL) {
        _ = view
        lastErrorMessage = nil
        pendingURL = url
        errorBox.isHidden = true
        address.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func search(_ request: SearchRequest) {
        currentSearch = request
        load(engineStore.selected.url(for: request))
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
        let menu = NSMenu()
        menu.autoenablesItems = false
        for engine in engineStore.engines {
            let item = NSMenuItem(title: engine.name, action: nil, keyEquivalent: "")
            item.representedObject = engine.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, command) in [("添加自定义引擎…", "add"), ("编辑当前引擎…", "edit"), ("删除当前引擎", "delete")] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = command
            item.isEnabled = command == "add" || engineStore.selected.isCustom
            menu.addItem(item)
        }
        enginePicker.menu = menu
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
            showEngineEditor(editing)
        case "delete":
            engineStore.removeCustom(id: engineStore.selected.id)
            engineChanged()
        default:
            guard engineStore.select(id: command) else { rebuildEnginePicker(); return }
            engineChanged()
        }
    }

    private func engineChanged() {
        rebuildEnginePicker()
        if let request = currentSearch { search(request) }
    }

    private func showEngineEditor(_ engine: SearchEngine?) {
        guard engineEditor == nil, view.window != nil else { return }
        let editor = SearchEngineEditorController(engine: engine)
        editor.onSave = { [weak self] name, template in
            guard let self = self else { return }
            try self.engineStore.saveCustom(name: name, urlTemplate: template, editingID: engine?.id)
            self.engineChanged()
        }
        editor.onClose = { [weak self] in self?.engineEditor = nil }
        engineEditor = editor
        presentAsSheet(editor)
    }

    func focusAddress() {
        view.window?.makeFirstResponder(address)
        address.selectText(nil)
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
        if let url = pendingURL { address.stringValue = url.absoluteString }
        errorDescription.stringValue = error.localizedDescription
        status.stringValue = "载入失败 · 可重新尝试"
        errorBox.isHidden = false
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
