import AppKit

@main struct MakeAssets {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let iconset = root.appendingPathComponent("App/Resources/AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let transform = NSAffineTransform()
                transform.scale(by: CGFloat(pixels) / 1024)
                transform.concat()
                let background = NSBezierPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), xRadius: 195, yRadius: 195)
                NSGradient(starting: NSColor(calibratedRed: 0.32, green: 0.70, blue: 0.98, alpha: 1),
                           ending: NSColor(calibratedRed: 0.08, green: 0.33, blue: 0.86, alpha: 1))!.draw(in: background, angle: -90)
                NSColor.white.withAlphaComponent(0.94).setFill()
                NSBezierPath(roundedRect: CGRect(x: 230, y: 244, width: 564, height: 536), xRadius: 58, yRadius: 58).fill()
                NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
                NSBezierPath(roundedRect: CGRect(x: 618, y: 260, width: 160, height: 504), xRadius: 40, yRadius: 40).fill()
                NSColor(calibratedRed: 0.15, green: 0.44, blue: 0.87, alpha: 1).setStroke()
                let lens = NSBezierPath(ovalIn: CGRect(x: 316, y: 441, width: 198, height: 198))
                lens.lineWidth = 34; lens.stroke()
                let handle = NSBezierPath()
                handle.move(to: CGPoint(x: 484, y: 468)); handle.line(to: CGPoint(x: 560, y: 386))
                handle.lineWidth = 34; handle.lineCapStyle = .round; handle.stroke()
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
        let toolbar = Toolbar(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let destination = root.appendingPathComponent("Extension/Resources/toolbar.pdf")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try toolbar.dataWithPDF(inside: toolbar.bounds).write(to: destination)
    }
}

final class Toolbar: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setStroke()
        let outline = NSBezierPath(roundedRect: CGRect(x: 2, y: 3, width: 16, height: 14), xRadius: 2, yRadius: 2)
        outline.lineWidth = 1.5; outline.stroke()
        let line = NSBezierPath(); line.move(to: CGPoint(x: 12, y: 3)); line.line(to: CGPoint(x: 12, y: 17))
        line.lineWidth = 1.5; line.stroke()
    }
}
