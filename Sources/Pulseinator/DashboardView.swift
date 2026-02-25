import SwiftUI
import Charts

struct DashboardView: View {
    @State private var data = DataProvider()
    @State private var signoz = SigNozClient()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                topRow
                Divider()
                tokenChart
                if !signoz.leverageSeries.isEmpty {
                    leverageChart
                }
                costChart
                Divider()
                signozBar
                lifetimeBar
            }
            .padding(16)
        .frame(width: 720)
        .background(.ultraThinMaterial)
        .task { await refresh() }
        .onReceive(timer) { _ in Task { await refresh() } }
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack(alignment: .top, spacing: 16) {
            usageLimitsPanel
                .frame(maxWidth: .infinity)
            Divider()
            todayPanel
                .frame(maxWidth: .infinity)
            Divider()
            modelsPanel
                .frame(maxWidth: .infinity)
        }
        .frame(height: 200)
    }

    private var usageLimitsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Limits")
                .font(.headline)

            if data.usageLimits.isEmpty {
                Text("Keychain token unavailable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(data.usageLimits, id: \.label) { limit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(limit.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(limit.utilization))%")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(limitColor(limit.utilization))
                        }
                        ProgressView(value: limit.utilization / 100)
                            .progressViewStyle(.linear)
                            .tint(limitColor(limit.utilization))
                        if let resetsAt = limit.resetsAt {
                            Text(resetCountdown(resetsAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var todayPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today  •  \(data.todayDate)")
                    .font(.headline)
                Spacer()
                sourceBadge
                if data.isLoading {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            statRow(label: "Messages", value: formatted(data.todayMessages))
            statRow(label: "Sessions", value: formatted(data.todaySessions))
            statRow(label: "Tokens", value: compactFormatted(data.todayTokens))

            Divider()

            statRow(label: "Week messages", value: formatted(data.weekMessages))
            statRow(label: "Week tokens", value: compactFormatted(data.weekTokens))
        }
    }

    private var sourceBadge: some View {
        Text(data.dataSource)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(data.dataSource == "API" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(data.dataSource == "API" ? Color.green : Color.orange)
            .clipShape(Capsule())
    }

    private var modelsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Models")
                .font(.headline)

            if data.modelBreakdown.isEmpty {
                Text("No model data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Chart(data.modelBreakdown) { model in
                    BarMark(x: .value("Tokens", model.tokens))
                        .foregroundStyle(by: .value("Model", shortModelName(model.name)))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 28)

                ForEach(data.modelBreakdown) { model in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForName(model.color))
                            .frame(width: 6, height: 6)
                        Text(shortModelName(model.name))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(compactFormatted(model.tokens))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Full-width Charts

    private var tokenChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Token Usage (\(signoz.selectedWindow.rawValue))")
                .font(.headline)

            if signoz.tokenSeries.isEmpty {
                noDataPlaceholder
            } else {
                Chart(signoz.tokenSeries) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(.blue.opacity(0.25))
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: signoz.selectedWindow.strideHours)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(compactFormatted(Int(v)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var leverageChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Leverage — CLI:User time ratio (\(signoz.selectedWindow.rawValue))")
                .font(.headline)

            Chart(signoz.leverageSeries) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Ratio", point.value)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Ratio", point.value)
                )
                .foregroundStyle(.green.opacity(0.15))
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: signoz.selectedWindow.strideHours)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.1f×", v))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    private var costChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cost (\(signoz.selectedWindow.rawValue))")
                .font(.headline)

            if signoz.costSeries.isEmpty {
                noDataPlaceholder
            } else {
                Chart(signoz.costSeries) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("USD", point.value)
                    )
                    .foregroundStyle(.purple.opacity(0.25))
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("USD", point.value)
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: signoz.selectedWindow.strideHours)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "$%.2f", v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var noDataPlaceholder: some View {
        Text("No SigNoz data")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - SigNoz Bar

    private var signozBar: some View {
        HStack(spacing: 12) {
            Picker("Window", selection: $signoz.selectedWindow) {
                ForEach(SigNozClient.TimeWindow.allCases, id: \.self) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: signoz.selectedWindow) {
                Task { await signoz.refresh() }
            }

            if signoz.isAvailable {
                Divider().frame(height: 20)
                signozStat(label: "Sessions", value: "\(signoz.sessions)")
                signozStat(label: "Tokens", value: compactFormatted(Int(signoz.tokens)))
                signozStat(label: "Cost", value: String(format: "$%.2f", signoz.costUSD))
                signozStat(label: "Lines", value: formatted(signoz.linesChanged))
                signozStat(label: "Commits", value: "\(signoz.commits)")
                signozStat(label: "Decisions", value: "\(signoz.decisions)")
            } else {
                Text("SigNoz offline")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    // MARK: - Lifetime Bar

    private var lifetimeBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text(formatted(data.lifetimeSessions))
                    .font(.body).fontWeight(.semibold)
                Text("sessions")
                    .font(.caption).foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(formatted(data.lifetimeMessages))
                    .font(.body).fontWeight(.semibold)
                Text("messages")
                    .font(.caption).foregroundStyle(.secondary)
                if data.firstSessionDate != "—" {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Since \(data.firstSessionDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(data.lastUpdated, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
    }

    private func signozStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
        }
    }

    private func refresh() async {
        async let dataRefresh: () = data.refresh()
        async let signozRefresh: () = signoz.refresh()
        _ = await (dataRefresh, signozRefresh)
    }

    private func formatted(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func compactFormatted(_ value: Int) -> String {
        switch value {
        case 0..<1_000:       return "\(value)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(value) / 1_000)
        default:              return String(format: "%.1fM", Double(value) / 1_000_000)
        }
    }

    private func shortModelName(_ name: String) -> String {
        name.replacingOccurrences(of: "claude-", with: "")
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "purple": return .purple
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "teal":   return .teal
        case "indigo": return .indigo
        case "cyan":   return .cyan
        default:       return .blue
        }
    }

    private func limitColor(_ utilization: Double) -> Color {
        switch utilization {
        case ..<50:   return .green
        case 50..<80: return .yellow
        default:      return .red
        }
    }

    private func resetCountdown(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "resetting…" }
        let totalHours = Int(seconds) / 3600
        let days = totalHours / 24
        let hours = totalHours % 24
        let minutes = (Int(seconds) % 3600) / 60

        let countdown: String
        if days > 0 {
            countdown = "resets in \(days)d \(hours)h"
        } else if hours > 0 {
            countdown = "resets in \(hours)h \(minutes)m"
        } else {
            countdown = "resets in \(minutes)m"
        }

        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mma"
        } else {
            formatter.dateFormat = "MMM d, h:mma"
        }
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"

        return "\(countdown) · \(formatter.string(from: date))"
    }
}
