import Foundation
import Observation

struct ModelStat: Identifiable {
    let id = UUID()
    let name: String
    let tokens: Int
    let color: String
}

struct StatsCache: Decodable {
    let totalMessages: Int?
    let totalTokens: Int?
    let totalSessions: Int?
    let weekMessages: Int?
    let weekTokens: Int?
    let lifetimeSessions: Int?
    let lifetimeMessages: Int?
    let firstSessionDate: String?
    let modelBreakdown: [ModelStatRaw]?

    enum CodingKeys: String, CodingKey {
        case totalMessages = "total_messages"
        case totalTokens = "total_tokens"
        case totalSessions = "total_sessions"
        case weekMessages = "week_messages"
        case weekTokens = "week_tokens"
        case lifetimeSessions = "lifetime_sessions"
        case lifetimeMessages = "lifetime_messages"
        case firstSessionDate = "first_session_date"
        case modelBreakdown = "model_breakdown"
    }
}

struct ModelStatRaw: Decodable {
    let name: String?
    let tokens: Int?
    let color: String?
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

        let decoder = JSONDecoder()
        guard let stats = try? decoder.decode(StatsCache.self, from: data) else {
            return
        }

        todayMessages = stats.totalMessages ?? 0
        todayTokens = stats.totalTokens ?? 0
        todaySessions = stats.totalSessions ?? 0
        weekMessages = stats.weekMessages ?? 0
        weekTokens = stats.weekTokens ?? 0
        lifetimeSessions = stats.lifetimeSessions ?? 0
        lifetimeMessages = stats.lifetimeMessages ?? 0
        firstSessionDate = stats.firstSessionDate ?? "—"

        if let breakdown = stats.modelBreakdown {
            let palette = ["blue", "purple", "green", "orange", "red", "teal"]
            modelBreakdown = breakdown.enumerated().compactMap { index, raw in
                guard let name = raw.name else { return nil }
                return ModelStat(
                    name: name,
                    tokens: raw.tokens ?? 0,
                    color: raw.color ?? palette[index % palette.count]
                )
            }
        }
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
