import AppKit

final class SearchEngineEditorController: NSViewController, NSTextFieldDelegate {
    let nameField = NSTextField()
    let templateField = NSTextField()
    let saveButton = NSButton()
    let cancelButton = NSButton()
    private(set) var validationMessage = ""
    var onSave: ((String, String) throws -> Void)?
    var onClose: (() -> Void)?
    private let engine: SearchEngine?
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let previewLabel = NSTextField(wrappingLabelWithString: "")

    init(engine: SearchEngine? = nil) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 480, height: 330))
        background.material = .windowBackground
        background.blendingMode = .withinWindow
        background.state = .active
        view = background
        let title = NSTextField(labelWithString: engine == nil ? "添加搜索引擎" : "编辑搜索引擎")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let nameLabel = NSTextField(labelWithString: "名称（可选）")
        let templateLabel = NSTextField(labelWithString: "搜索引擎")
        nameField.placeholderString = "留空则自动命名"
        nameField.stringValue = engine?.name ?? ""
        nameField.setAccessibilityLabel("搜索引擎名称")
        templateField.placeholderString = "例如：google.com、百度，或搜索结果页网址"
        templateField.stringValue = engine?.urlTemplate ?? ""
        templateField.setAccessibilityLabel("搜索引擎名称、域名或搜索网址")
        templateField.delegate = self
        templateField.cell?.isScrollable = true
        let hint = NSTextField(wrappingLabelWithString: "Google、Bing、百度、DuckDuckGo 可直接输入名称或域名，自动补全搜索地址。其他引擎请粘贴一次搜索结果页的网址。\n保存后，搜索词会发送给这个网站。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("搜索引擎设置错误")
        previewLabel.font = .systemFont(ofSize: 11)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.maximumNumberOfLines = 2
        previewLabel.cell?.lineBreakMode = .byTruncatingMiddle
        previewLabel.setAccessibilityLabel("自动识别的搜索地址")

        cancelButton.title = "取消"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.title = "保存并使用"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        let spacer = NSView()
        let buttons = NSStackView(views: [spacer, cancelButton, saveButton])
        buttons.spacing = 8
        for element in [title, nameLabel, nameField, templateLabel, templateField, hint, previewLabel, errorLabel, buttons] {
            element.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(element)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            templateLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            templateLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            templateField.centerYAnchor.constraint(equalTo: templateLabel.centerYAnchor),
            templateField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 116),
            templateField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nameLabel.topAnchor.constraint(equalTo: templateLabel.bottomAnchor, constant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: templateField.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            previewLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            buttons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: errorLabel.bottomAnchor, constant: 10)
        ])
        preferredContentSize = view.frame.size
        updatePreview()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(templateField)
    }

    func controlTextDidChange(_ notification: Notification) { updatePreview() }

    private func updatePreview() {
        if let resolved = try? SearchEngineInput.resolve(templateField.stringValue) {
            previewLabel.stringValue = resolved.urlTemplate.replacingOccurrences(of: "{query}", with: "搜索词")
            nameField.placeholderString = "自动：" + resolved.suggestedName
        } else {
            previewLabel.stringValue = ""
            nameField.placeholderString = "留空则自动命名"
        }
        validationMessage = ""
        errorLabel.stringValue = ""
    }

    @objc private func save() {
        do {
            // Commit the field editor before reading values after Return/click.
            view.window?.makeFirstResponder(nil)
            guard let onSave else { return }
            try onSave(nameField.stringValue, templateField.stringValue)
            close()
        } catch {
            validationMessage = error.localizedDescription
            errorLabel.stringValue = validationMessage
        }
    }

    @objc private func cancel() { close() }

    private func close() {
        dismiss(self)
        onClose?()
    }
}
