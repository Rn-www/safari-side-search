import AppKit
import CoreGraphics

struct SafariWindow {
    let id: CGWindowID
    let frame: CGRect
}

enum SafariWindowTracker {
    static func windows() -> [SafariWindow] {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        return list.compactMap { item in
            guard let pid = item[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = item[kCGWindowNumber as String] as? UInt32,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 250, rect.height > 200 else { return nil }
            return SafariWindow(id: id, frame: CGRect(x: rect.minX, y: desktopTop - rect.maxY,
                                                      width: rect.width, height: rect.height))
        }
    }

    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max {
            area($0.frame.intersection(rect)) < area($1.frame.intersection(rect))
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
