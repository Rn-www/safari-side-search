import AppKit

/// Standard text shortcuts and Quit for manual test previews, without production
/// status-menu actions that could open a sidebar on a different display.
enum TestingAppMenus {
    @MainActor static func install() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle:"退出测试", action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q").target = NSApp
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem(title:"编辑",action:nil,keyEquivalent:"")
        let edit = NSMenu(title:"编辑")
        for (title,action,key) in [("剪切",#selector(NSText.cut(_:)),"x"),
                                   ("复制",#selector(NSText.copy(_:)),"c"),
                                   ("粘贴",#selector(NSText.paste(_:)),"v"),
                                   ("全选",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(withTitle:title,action:action,keyEquivalent:key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
