import Foundation
import Observation

struct ModelStat: Identifiable {
    let id = UUID()
    let name: String
    let tokens: Int
    let color: String
}

struct StatsCache: Decodable {
    let lastComputedDate: String?
    let dailyActivity: [DayActivity]?
    let dailyModelTokens: [DayModelTokens]?
    let modelUsage: [String: ModelUsageStats]?
    let totalSessions: Int?
    let totalMessages: Int?
    let firstSessionDate: String?
}

struct DayActivity: Decodable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int
}

struct DayModelTokens: Decodable {
    let date: String
    let tokensByModel: [String: Int]
}

struct ModelUsageStats: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
}

struct AnthropicUsageResponse: Decodable {
    let data: [AnthropicUsageEntry]?
}

struct AnthropicUsageEntry: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case model
    }
}

@Observable
class DataProvider {
    var todayMessages: Int = 0
    var todayTokens: Int = 0
    var todaySessions: Int = 0
    var todayDate: String = "—"
    var weekMessages: Int = 0
    var weekTokens: Int = 0
    var modelBreakdown: [ModelStat] = []
    var lifetimeSessions: Int = 0
    var lifetimeMessages: Int = 0
    var firstSessionDate: String = "—"
    var dataSource: String = "Local"
    var lastUpdated: Date = Date()
    var isLoading: Bool = false

    private let statsCachePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/stats-cache.json"
    }()

    private let promPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/metrics/claude.prom"
    }()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let adminKey = ProcessInfo.processInfo.environment["ANTHROPIC_ADMIN_KEY"]

        if let key = adminKey, !key.isEmpty {
            await loadFromAnthropicAPI(apiKey: key)
        } else {
            loadFromLocalFiles()
        }

        lastUpdated = Date()
    }

    private func loadFromLocalFiles() {
        loadFromStatsCache()
        mergeFromProm()
        dataSource = "Local"
    }

    private func loadFromStatsCache() {
        guard FileManager.default.fileExists(atPath: statsCachePath),
              let data = FileManager.default.contents(atPath: statsCachePath) else {
            return
        }

        guard let stats = try? JSONDecoder().decode(StatsCache.self, from: data) else {
            return
        }

        // Most recent day: sort by date string (ISO format sorts lexicographically)
        if let mostRecent = stats.dailyActivity?.sorted(by: { $0.date > $1.date }).first {
            todayMessages = mostRecent.messageCount
            todaySessions = mostRecent.sessionCount
            todayDate = formatShortDate(mostRecent.date)
        }

        // Today's tokens: sum tokensByModel for the most recent date
        if let mostRecentDate = stats.dailyActivity?.sorted(by: { $0.date > $1.date }).first?.date,
           let dayTokens = stats.dailyModelTokens?.first(where: { $0.date == mostRecentDate }) {
            todayTokens = dayTokens.tokensByModel.values.reduce(0, +)
        }

        // Week: last 7 days relative to lastComputedDate
        let cutoffDate = weekCutoffDate(from: stats.lastComputedDate)
        let weekActivities = stats.dailyActivity?.filter { $0.date >= cutoffDate } ?? []
        weekMessages = weekActivities.reduce(0) { $0 + $1.messageCount }

        let weekTokenEntries = stats.dailyModelTokens?.filter { $0.date >= cutoffDate } ?? []
        weekTokens = weekTokenEntries.reduce(0) { total, entry in
            total + entry.tokensByModel.values.reduce(0, +)
        }

        // Model breakdown: sum input + output tokens per model, sort descending
        if let usage = stats.modelUsage {
            let palette = ["blue", "purple", "green", "orange", "red", "teal"]
            modelBreakdown = usage
                .map { name, stat in
                    (name: name, tokens: (stat.inputTokens ?? 0) + (stat.outputTokens ?? 0))
                }
                .sorted { $0.tokens > $1.tokens }
                .enumerated()
                .map { index, pair in
                    ModelStat(name: pair.name, tokens: pair.tokens, color: palette[index % palette.count])
                }
        }

        // Lifetime
        lifetimeSessions = stats.totalSessions ?? 0
        lifetimeMessages = stats.totalMessages ?? 0
        firstSessionDate = formatFirstSessionDate(stats.firstSessionDate)
    }

    private func weekCutoffDate(from lastComputedDate: String?) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let anchor: Date
        if let dateStr = lastComputedDate, let parsed = formatter.date(from: dateStr) {
            anchor = parsed
        } else {
            anchor = Date()
        }

        let cutoff = calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        return formatter.string(from: cutoff)
    }

    private func formatShortDate(_ isoDate: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"

        let output = DateFormatter()
        output.dateFormat = "MMM d"

        guard let date = input.date(from: isoDate) else { return isoDate }
        return output.string(from: date)
    }

    private func formatFirstSessionDate(_ rawDate: String?) -> String {
        guard let raw = rawDate else { return "—" }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackISO = ISO8601DateFormatter()
        fallbackISO.formatOptions = [.withInternetDateTime]

        let date = iso.date(from: raw) ?? fallbackISO.date(from: raw)
        guard let date else { return raw }

        let output = DateFormatter()
        output.dateFormat = "MMM d, yyyy"
        return output.string(from: date)
    }

    private func mergeFromProm() {
        guard FileManager.default.fileExists(atPath: promPath),
              let content = try? String(contentsOfFile: promPath, encoding: .utf8) else {
            return
        }

        var promMessages = 0
        var promTokens = 0
        var promSessions = 0

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: " ")
            guard parts.count >= 2, let value = Double(parts.last ?? "") else { continue }

            let metricWithLabels = parts[0]

            if metricWithLabels.contains("claude_messages_total") {
                promMessages += Int(value)
            } else if metricWithLabels.contains("claude_tokens_total") {
                promTokens += Int(value)
            } else if metricWithLabels.contains("claude_sessions_total") {
                promSessions += Int(value)
            }
        }

        if promMessages > 0 { todayMessages = promMessages }
        if promTokens > 0 { todayTokens = promTokens }
        if promSessions > 0 { todaySessions = promSessions }
    }

    private func loadFromAnthropicAPI(apiKey: String) async {
        let baseURL = "https://api.anthropic.com"
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            return config
        }())

        var totalInputTokens = 0
        var totalOutputTokens = 0
        var modelMap: [String: Int] = [:]

        if let url = URL(string: "\(baseURL)/v1/organizations/usage_report/messages") {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            if let (data, _) = try? await session.data(for: request),
               let response = try? JSONDecoder().decode(AnthropicUsageResponse.self, from: data) {
                for entry in response.data ?? [] {
                    let input = entry.inputTokens ?? 0
                    let output = entry.outputTokens ?? 0
                    totalInputTokens += input
                    totalOutputTokens += output

                    if let model = entry.model {
                        modelMap[model, default: 0] += input + output
                    }
                }
            }
        }

        todayTokens = totalInputTokens + totalOutputTokens

        let palette = ["blue", "purple", "green", "orange", "red", "teal"]
        modelBreakdown = modelMap.sorted { $0.value > $1.value }.enumerated().map { index, pair in
            ModelStat(name: pair.key, tokens: pair.value, color: palette[index % palette.count])
        }

        dataSource = "API"
    }
}
