import AppKit

/// Menu bar icon: a small calendar page with the month cut out of its header
/// band and the day number below. Drawn as a template image so macOS tints it
/// for light and dark menu bars.
enum DateIcon {
    static func image(for date: Date) -> NSImage {
        let day = String(Calendar.current.component(.day, from: date))
        let month = date.formatted(.dateTime.month(.abbreviated)).uppercased()
        let headerHeight: CGFloat = 7

        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let page = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            page.lineWidth = 1.5
            page.stroke()

            let header = NSRect(x: 0, y: rect.maxY - headerHeight, width: rect.width, height: headerHeight)
            NSGraphicsContext.saveGraphicsState()
            page.addClip()
            header.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Knock the month out of the band so the menu bar shows through.
            let monthText = NSAttributedString(string: month, attributes: [
                .font: NSFont.systemFont(ofSize: 5.5, weight: .heavy),
                .foregroundColor: NSColor.black,
                .kern: 0.3,
            ])
            let monthSize = monthText.size()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            monthText.draw(at: NSPoint(
                x: (rect.width - monthSize.width) / 2,
                y: header.minY + (headerHeight - monthSize.height) / 2 + 0.3
            ))
            NSGraphicsContext.restoreGraphicsState()

            let number = NSAttributedString(string: day, attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.black,
            ])
            let numberSize = number.size()
            number.draw(at: NSPoint(
                x: (rect.width - numberSize.width) / 2,
                y: (header.minY - numberSize.height) / 2 + 0.5
            ))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = date.formatted(date: .complete, time: .omitted)
        return image
    }
}
