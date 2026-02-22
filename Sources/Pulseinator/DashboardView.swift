import SwiftUI

struct DashboardView: View {
    @State private var data = DataProvider()
    @State private var signoz = SigNozClient()

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                usageSummarySection
                modelBreakdownSection
                signozSection
                bottomBar
            }
            .padding(12)
        }
        .frame(width: 380)
        .task {
            await refresh()
        }
    }

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(data.dataSource)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        data.dataSource == "API"
                            ? Color.green.opacity(0.2)
                            : Color.orange.opacity(0.2)
                    )
                    .foregroundStyle(
                        data.dataSource == "API" ? Color.green : Color.orange
                    )
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                UsageCard(
                    title: "Messages",
                    value: formatted(data.todayMessages),
                    subtitle: "today",
                    accentColor: .blue
                )
                UsageCard(
                    title: "Sessions",
                    value: formatted(data.todaySessions),
                    subtitle: "today",
                    accentColor: .purple
                )
                UsageCard(
                    title: "Tokens",
                    value: compactFormatted(data.todayTokens),
                    subtitle: "today",
                    accentColor: .teal
                )
            }

            HStack(spacing: 16) {
                weekStat(label: "Week messages", value: formatted(data.weekMessages))
                Divider().frame(height: 16)
                weekStat(label: "Week tokens", value: compactFormatted(data.weekTokens))
                Spacer()
                if data.isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
    }

    private var modelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model Breakdown")
                .font(.headline)

            if data.modelBreakdown.isEmpty {
                Text("No model data available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let maxTokens = data.modelBreakdown.map(\.tokens).max() ?? 1

                ForEach(data.modelBreakdown) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(shortModelName(stat.name))
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(compactFormatted(stat.tokens))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForName(stat.color).opacity(0.7))
                                .frame(
                                    width: geo.size.width * CGFloat(stat.tokens) / CGFloat(max(maxTokens, 1)),
                                    height: 4
                                )
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    private var signozSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SigNoz")
                    .font(.headline)
                Spacer()
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
            }

            if signoz.isAvailable {
                HStack(spacing: 8) {
                    UsageCard(
                        title: "Services",
                        value: "\(signoz.services.count)",
                        subtitle: "active",
                        accentColor: .indigo
                    )
                    UsageCard(
                        title: "Errors",
                        value: "\(signoz.errorCount)",
                        subtitle: signoz.selectedWindow.rawValue,
                        accentColor: signoz.errorCount > 0 ? .red : .green
                    )
                    UsageCard(
                        title: "Traces",
                        value: compactFormatted(signoz.traceCount),
                        subtitle: signoz.selectedWindow.rawValue,
                        accentColor: .cyan
                    )
                }
            } else {
                Text("SigNoz offline")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        Text("\(formatted(data.lifetimeSessions)) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatted(data.lifetimeMessages)) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if data.firstSessionDate != "—" {
                        Text("Since \(data.firstSessionDate)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Updated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(data.lastUpdated, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func weekStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        case 0..<1_000: return "\(value)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(value) / 1_000)
        default: return String(format: "%.1fM", Double(value) / 1_000_000)
        }
    }

    private func shortModelName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " '")
            .appending(name.contains("-20") ? "" : "")
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "teal": return .teal
        case "indigo": return .indigo
        case "cyan": return .cyan
        default: return .blue
        }
    }
}
