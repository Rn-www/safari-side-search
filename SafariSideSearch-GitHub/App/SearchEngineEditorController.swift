import AppKit

final class SearchEngineEditorController: NSViewController {
    let nameField = NSTextField()
    let templateField = NSTextField()
    let saveButton = NSButton()
    let cancelButton = NSButton()
    private(set) var validationMessage = ""
    var onSave: ((String, String) throws -> Void)?
    var onClose: (() -> Void)?
    private let engine: SearchEngine?
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(engine: SearchEngine? = nil) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 440, height: 290))
        background.material = .windowBackground
        background.blendingMode = .withinWindow
        background.state = .active
        view = background
        let title = NSTextField(labelWithString: engine == nil ? "添加搜索引擎" : "编辑搜索引擎")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let nameLabel = NSTextField(labelWithString: "名称")
        let templateLabel = NSTextField(labelWithString: "搜索地址")
        nameField.placeholderString = "例如：我的搜索"
        nameField.stringValue = engine?.name ?? ""
        nameField.setAccessibilityLabel("搜索引擎名称")
        templateField.placeholderString = "https://example.com/search?q={query}"
        templateField.stringValue = engine?.urlTemplate ?? ""
        templateField.setAccessibilityLabel("搜索地址模板")
        templateField.cell?.isScrollable = true
        let hint = NSTextField(wrappingLabelWithString: "将网址中的搜索词换成 {query}，例如：\nhttps://www.bing.com/search?q={query}\n保存后会将搜索词发送给这个网站。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("搜索引擎设置错误")

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
        for element in [title, nameLabel, nameField, templateLabel, templateField, hint, errorLabel, buttons] {
            element.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(element)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 17),
            nameLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 88),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            templateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 20),
            templateLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            templateField.centerYAnchor.constraint(equalTo: templateLabel.centerYAnchor),
            templateField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            templateField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            hint.topAnchor.constraint(equalTo: templateField.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            errorLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            buttons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: errorLabel.bottomAnchor, constant: 10)
        ])
        preferredContentSize = view.frame.size
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
    }

    @objc private func save() {
        do {
            try onSave?(nameField.stringValue, templateField.stringValue)
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
