import SwiftUI
import AppKit

@main
struct PulseinatorApp: App {
    @State private var data = DataProvider()
    @State private var signoz = SigNozClient()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(data: data, signoz: signoz)
        } label: {
            Image(nsImage: limitBarsImage(for: data.usageLimits))
        }
        .menuBarExtraStyle(.window)
    }

    private func limitBarsImage(for limits: [LimitWindow]) -> NSImage {
        let barW: CGFloat = 5
        let barH: CGFloat = 14
        let gap: CGFloat = 3
        let imgW = barW * 2 + gap

        let image = NSImage(size: NSSize(width: imgW, height: barH), flipped: false) { _ in
            for (i, label) in ["5-hour", "7-day"].enumerated() {
                let util = limits.first(where: { $0.label == label })?.utilization ?? 0
                let t = CGFloat(max(0, min(100, util))) / 100
                let x = CGFloat(i) * (barW + gap)

                // Track
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: barH),
                             xRadius: 1.5, yRadius: 1.5).fill()

                // Fill — green → yellow → orange → red via hue lerp
                let fillH = max(2, barH * t)
                NSColor(hue: 0.33 * (1 - t), saturation: 0.9, brightness: 0.75, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: fillH),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
