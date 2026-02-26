import SwiftUI

@main
struct PulseinatorApp: App {
    @State private var data = DataProvider()
    @State private var signoz = SigNozClient()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(data: data, signoz: signoz)
        } label: {
            LimitBarsLabel(limits: data.usageLimits)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar label

struct LimitBarsLabel: View {
    let limits: [LimitWindow]

    var body: some View {
        HStack(spacing: 3) {
            MiniBar(utilization: limits.first(where: { $0.label == "5-hour" })?.utilization ?? 0)
            MiniBar(utilization: limits.first(where: { $0.label == "7-day" })?.utilization ?? 0)
        }
        .frame(width: 16, height: 14)
    }
}

struct MiniBar: View {
    let utilization: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.2))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor)
                    .frame(height: geo.size.height * max(0.04, utilization / 100))
            }
        }
    }

    private var barColor: Color {
        let t = max(0, min(100, utilization)) / 100
        return Color(hue: 0.33 * (1 - t), saturation: 0.85, brightness: 0.95)
    }
}
