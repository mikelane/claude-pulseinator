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

    private func limitNSColor(for limit: LimitWindow?) -> NSColor {
        guard let limit = limit else { return .systemGreen }

        let windowSeconds: Double
        switch limit.label {
        case "5-hour": windowSeconds = 5 * 3600
        case "7-day":  windowSeconds = 7 * 24 * 3600
        default:       windowSeconds = 0
        }

        if let resetsAt = limit.resetsAt, windowSeconds > 0 {
            let secondsRemaining = max(0, resetsAt.timeIntervalSinceNow)
            let elapsedPct = (windowSeconds - secondsRemaining) / windowSeconds * 100
            let paceDelta = limit.utilization - elapsedPct
            if paceDelta <= 0  { return .systemGreen }
            if paceDelta <= 15 { return .systemOrange }
            return .systemRed
        }

        switch limit.utilization {
        case ..<75:   return .systemGreen
        case 75..<90: return .systemOrange
        default:      return .systemRed
        }
    }

    private func limitBarsImage(for limits: [LimitWindow]) -> NSImage {
        let barW: CGFloat = 5
        let barH: CGFloat = 14
        let gap: CGFloat = 3
        let imgW = barW * 2 + gap

        let image = NSImage(size: NSSize(width: imgW, height: barH), flipped: false) { _ in
            for (i, label) in ["5-hour", "7-day"].enumerated() {
                let limit = limits.first(where: { $0.label == label })
                let util = limit?.utilization ?? 0
                let t = CGFloat(max(0, min(100, util))) / 100
                let x = CGFloat(i) * (barW + gap)

                // Track
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: barH),
                             xRadius: 1.5, yRadius: 1.5).fill()

                // Fill — pace-based color matching statusline
                let fillH = max(2, barH * t)
                limitNSColor(for: limit).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: fillH),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
