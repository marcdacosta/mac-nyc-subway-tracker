import AppKit

enum StatusBarIcon {
    static func image(routeID: String?) -> NSImage {
        let imageSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: imageSize, flipped: false) { bounds in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut

            if let routeID, !routeID.isEmpty {
                drawRouteID(routeID, in: bounds)
            } else {
                drawAllTrainsSymbol(in: bounds)
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }

        image.isTemplate = false
        return image
    }

    private static func drawRouteID(_ routeID: String, in bounds: NSRect) {
        let fontSize: CGFloat
        switch routeID.count {
        case 1:
            fontSize = 12
        case 2:
            fontSize = 9
        default:
            fontSize = 7
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let label = routeID as NSString
        let labelSize = label.size(withAttributes: attributes)
        let labelOrigin = NSPoint(
            x: (bounds.width - labelSize.width) / 2,
            y: (bounds.height - labelSize.height) / 2 + 0.5
        )
        label.draw(at: labelOrigin, withAttributes: attributes)
    }

    private static func drawAllTrainsSymbol(in bounds: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        guard let symbol = NSImage(
            systemSymbolName: "tram.fill",
            accessibilityDescription: "All trains"
        )?.withSymbolConfiguration(configuration) else {
            drawRouteID("*", in: bounds)
            return
        }

        let symbolRect = NSRect(
            x: (bounds.width - 10) / 2,
            y: (bounds.height - 10) / 2,
            width: 10,
            height: 10
        )
        symbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1
        )
    }
}
