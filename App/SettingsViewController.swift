import AppKit

final class SettingsViewController: NSViewController {
    let showFullURLButton = NSButton(checkboxWithTitle: "显示完整网址", target: nil, action: nil)
    let currentEnginePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let defaultEnginePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let addEngineButton = NSButton(title: "添加搜索引擎…", target: nil, action: nil)
    private(set) var engineEditor: SearchEngineEditorController?
    private let store: SearchEngineStore
    private let preferences: BrowserPreferences
    private var observers: [NSObjectProtocol] = []

    init(store: SearchEngineStore, preferences: BrowserPreferences) {
        self.store = store
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        for (name, object) in [(SearchEngineStore.didChange, store as NSObject), (BrowserPreferences.didChange, preferences as NSObject)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                self?.refresh()
            })
        }

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    override func viewWillAppear() { super.viewWillAppear(); refresh() }

    override func loadView() {
        let root = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 480, height: 400))
        root.material = .windowBackground
        root.state = .active
        view = root
        let title = NSTextField(labelWithString: "侧栏搜索设置")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = caption("调整搜索引擎与地址栏显示")
        showFullURLButton.target = self
        showFullURLButton.action = #selector(toggleFullURL)
        showFullURLButton.setAccessibilityLabel("显示完整网址")
        let addressHint = caption("关闭时只显示域名；进入地址栏编辑时始终显示完整网址。")
        let currentLabel = NSTextField(labelWithString: "当前搜索引擎")
        let defaultLabel = NSTextField(labelWithString: "默认搜索引擎")
        let currentHint = caption("切换后继续搜索当前查询，与顶部菜单同步。")
        let defaultHint = caption("每次右键发起新搜索时使用；不会改变正在浏览的查询。")
        for picker in [currentEnginePicker, defaultEnginePicker] {
            picker.controlSize = .regular
            picker.font = .systemFont(ofSize: 13)
            picker.target = self
            picker.widthAnchor.constraint(equalToConstant: 218).isActive = true
        }
        currentEnginePicker.action = #selector(changeCurrentEngine)
        defaultEnginePicker.action = #selector(changeDefaultEngine)
        currentEnginePicker.setAccessibilityLabel("当前搜索引擎")
        defaultEnginePicker.setAccessibilityLabel("默认搜索引擎")
        addEngineButton.bezelStyle = .rounded
        addEngineButton.target = self
        addEngineButton.action = #selector(addEngine)
        let separator = NSBox()
        separator.boxType = .separator
        let separator2 = NSBox()
        separator2.boxType = .separator
        for item in [title, subtitle, showFullURLButton, addressHint, separator, currentLabel,
                     currentEnginePicker, currentHint, defaultLabel, defaultEnginePicker, defaultHint, separator2, addEngineButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(item)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            showFullURLButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            showFullURLButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            addressHint.topAnchor.constraint(equalTo: showFullURLButton.bottomAnchor, constant: 6),
            addressHint.leadingAnchor.constraint(equalTo: title.leadingAnchor, constant: 18),
            addressHint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            separator.topAnchor.constraint(equalTo: addressHint.bottomAnchor, constant: 18),
            separator.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            currentEnginePicker.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),
            currentEnginePicker.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            currentLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            currentLabel.centerYAnchor.constraint(equalTo: currentEnginePicker.centerYAnchor),
            currentHint.topAnchor.constraint(equalTo: currentEnginePicker.bottomAnchor, constant: 6),
            currentHint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            currentHint.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            separator2.topAnchor.constraint(equalTo: currentHint.bottomAnchor, constant: 18),
            separator2.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            separator2.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            defaultEnginePicker.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 18),
            defaultEnginePicker.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            defaultLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            defaultLabel.centerYAnchor.constraint(equalTo: defaultEnginePicker.centerYAnchor),
            defaultHint.topAnchor.constraint(equalTo: defaultEnginePicker.bottomAnchor, constant: 6),
            defaultHint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            defaultHint.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            addEngineButton.topAnchor.constraint(equalTo: defaultHint.bottomAnchor, constant: 18),
            addEngineButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            addEngineButton.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22)
        ])
        refresh()
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func refresh() {
        guard isViewLoaded else { return }
        showFullURLButton.state = preferences.showFullURL ? .on : .off
        currentEnginePicker.menu = SearchEngineMenu.make(store: store, management: true)
        defaultEnginePicker.menu = SearchEngineMenu.make(store: store, management: false)
        currentEnginePicker.selectItem(at: store.engines.firstIndex(where: { $0.id == store.selected.id }) ?? 0)
        defaultEnginePicker.selectItem(at: store.engines.firstIndex(where: { $0.id == store.defaultEngine.id }) ?? 0)
    }

    @objc private func toggleFullURL() { preferences.showFullURL = showFullURLButton.state == .on }

    @objc private func addEngine() { showEngineEditor(nil) }

    @objc private func changeDefaultEngine() {
        guard let id = defaultEnginePicker.selectedItem?.representedObject as? String else { return }
        store.setDefault(id: id)
        refresh()
    }

    @objc private func changeCurrentEngine() {
        guard let command = currentEnginePicker.selectedItem?.representedObject as? String else { return }
        switch command {
        case "add", "edit":
            let engine = command == "edit" ? store.selected : nil
            refresh()
            guard engineEditor == nil else { return }
            // Present after AppKit has finished tracking the popup menu.
            DispatchQueue.main.async { [weak self] in self?.showEngineEditor(engine) }
        case "delete": store.removeCustom(id: store.selected.id)
        default: store.select(id: command)
        }
        refresh()
    }

    private func showEngineEditor(_ engine: SearchEngine?) {
        guard engineEditor == nil, view.window?.isVisible == true else { return }
        let editor = SearchEngineEditorController(engine: engine)
        editor.onSave = { [weak self] name, input in
            try self?.store.saveInput(name: name, input: input, editingID: engine?.id)
        }
        editor.onClose = { [weak self] in self?.engineEditor = nil }
        engineEditor = editor
        presentAsSheet(editor)
    }
}

final class SettingsWindowController: NSWindowController {
    let settings: SettingsViewController

    init(store: SearchEngineStore, preferences: BrowserPreferences) {
        settings = SettingsViewController(store: store, preferences: preferences)
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 400),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "侧栏搜索设置"
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentViewController = settings
        super.init(window: panel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(relativeTo source: NSWindow?) {
        guard let window = window else { return }
        if !window.isVisible, let screen = (source?.isVisible == true ? source?.screen : nil) ?? NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame.insetBy(dx: 16, dy: 16)
            let center = source?.isVisible == true ? source!.frame : visible
            let x = min(max(center.midX - window.frame.width / 2, visible.minX), visible.maxX - window.frame.width)
            let y = min(max(center.midY - window.frame.height / 2, visible.minY), visible.maxY - window.frame.height)
            window.setFrameOrigin(CGPoint(x: x, y: y))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
