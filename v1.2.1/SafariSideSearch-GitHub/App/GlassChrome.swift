import AppKit

enum GlassChrome {
    static func capsule(_ content: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4), radius: CGFloat = 16) -> NSView {
        let surface: NSView
        let host = NSView()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            // This is a documented macOS 27 property. Objective-C dispatch keeps
            // source builds compatible with the macOS 26 SDK as well.
            if #available(macOS 27.0, *), glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(true, forKey: "effectIsInteractive")
            }
            glass.contentView = host
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .headerView
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.masksToBounds = true
            effect.addSubview(host)
            surface = effect
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: surface.topAnchor),
            host.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: host.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -insets.right)
        ])
        return surface
    }

    static func container(_ content: NSView) -> NSView {
        let container: NSView
        if #available(macOS 26.0, *) {
            let glassContainer = NSGlassEffectContainerView()
            glassContainer.spacing = 0
            glassContainer.contentView = content
            container = glassContainer
        } else {
            container = NSView()
            container.addSubview(content)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }
}

/// Reveal the canonical URL before AppKit installs its field editor.
final class SidebarAddressField: NSTextField {
    var onFocus: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        onFocus?()
        return super.becomeFirstResponder()
    }
    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }
}

enum SearchEngineMenu {
    static func make(store: SearchEngineStore, management: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for engine in store.engines {
            let item = NSMenuItem(title: engine.name, action: nil, keyEquivalent: "")
            item.representedObject = engine.id
            menu.addItem(item)
        }
        if management {
            menu.addItem(.separator())
            for (title, command) in [("添加自定义引擎…", "add"), ("编辑当前引擎…", "edit"), ("删除当前引擎", "delete")] {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = command
                item.isEnabled = command == "add" || store.selected.isCustom
                menu.addItem(item)
            }
        }
        return menu
    }
}
