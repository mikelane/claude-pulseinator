import Foundation
import Observation

struct TimePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

@Observable
class SigNozClient {
    var isAvailable: Bool = false
    var tokens: Double = 0
    var costUSD: Double = 0
    var sessions: Int = 0
    var linesChanged: Int = 0
    var commits: Int = 0
    var decisions: Int = 0
    var tokenSeries: [TimePoint] = []
    var costSeries: [TimePoint] = []
    var leverageSeries: [TimePoint] = []
    var selectedWindow: TimeWindow = .threeHours

    enum TimeWindow: String, CaseIterable {
        case oneHour = "1h"
        case threeHours = "3h"
        case twelveHours = "12h"
        case twentyFourHours = "24h"

        var milliseconds: Int64 {
            switch self {
            case .oneHour:         return 3_600_000
            case .threeHours:      return 10_800_000
            case .twelveHours:     return 43_200_000
            case .twentyFourHours: return 86_400_000
            }
        }

        // Scalar aggregation step — full window, one point
        var stepSeconds: Int {
            switch self {
            case .oneHour:         return 3600
            case .threeHours:      return 10800
            case .twelveHours:     return 43200
            case .twentyFourHours: return 86400
            }
        }

        // Series step — ~60 points across the window
        var seriesStepSeconds: Int {
            switch self {
            case .oneHour:         return 60
            case .threeHours:      return 180
            case .twelveHours:     return 720
            case .twentyFourHours: return 1440
            }
        }

        // For chartXAxis stride count in hours
        var strideHours: Int {
            switch self {
            case .oneHour:         return 1
            case .threeHours:      return 1
            case .twelveHours:     return 3
            case .twentyFourHours: return 6
            }
        }
    }

    private let baseURL = "http://127.0.0.1:8080"
    private let apiKey = "<YOUR_SIGNOZ_API_KEY>"

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func refresh() async {
        let endMs = Int64(Date().timeIntervalSince1970 * 1000)
        let startMs = endMs - selectedWindow.milliseconds
        let step = selectedWindow.stepSeconds
        let seriesStep = selectedWindow.seriesStepSeconds

        // Scalar queries — sequential, first one probes availability
        guard let tokenTotal = await queryScalar("claude_code.token.usage", start: startMs, end: endMs, step: step) else {
            isAvailable = false
            return
        }
        isAvailable = true
        tokens = tokenTotal

        if let v = await queryScalar("claude_code.cost.usage", start: startMs, end: endMs, step: step) {
            costUSD = v
        }
        if let v = await queryScalar("claude_code.session.count", start: startMs, end: endMs, step: step) {
            sessions = Int(v)
        }
        if let v = await queryScalar("claude_code.lines_of_code.count", start: startMs, end: endMs, step: step) {
            linesChanged = Int(v)
        }
        if let v = await queryScalar("claude_code.commit.count", start: startMs, end: endMs, step: step) {
            commits = Int(v)
        }
        if let v = await queryScalar("claude_code.code_edit_tool.decision", start: startMs, end: endMs, step: step) {
            decisions = Int(v)
        }

        // Time-series queries
        tokenSeries = await querySeries("claude_code.token.usage", start: startMs, end: endMs, step: seriesStep)
        costSeries = await querySeries("claude_code.cost.usage", start: startMs, end: endMs, step: seriesStep)
        leverageSeries = await queryLeverageSeries(start: startMs, end: endMs, step: seriesStep)
    }

    // MARK: - Scalar (single aggregated value)

    private func queryScalar(_ metricKey: String, start: Int64, end: Int64, step: Int) async -> Double? {
        let raw = await queryMetric(
            metricKey,
            start: start, end: end, step: step,
            panelType: "value", reduceTo: "sum",
            filters: emptyFilters()
        )
        return raw?.first?.value
    }

    // MARK: - Series (multiple time points)

    private func querySeries(_ metricKey: String, start: Int64, end: Int64, step: Int) async -> [TimePoint] {
        return await queryMetric(
            metricKey,
            start: start, end: end, step: step,
            panelType: "graph", reduceTo: "sum",
            filters: emptyFilters()
        ) ?? []
    }

    private func queryLeverageSeries(start: Int64, end: Int64, step: Int) async -> [TimePoint] {
        let cliFilter = makeFilter(key: "type", value: "cli")
        let userFilter = makeFilter(key: "type", value: "user")

        let cliPoints = await queryMetric(
            "claude_code.active_time.total",
            start: start, end: end, step: step,
            panelType: "graph", reduceTo: "sum",
            filters: cliFilter
        ) ?? []

        let userPoints = await queryMetric(
            "claude_code.active_time.total",
            start: start, end: end, step: step,
            panelType: "graph", reduceTo: "sum",
            filters: userFilter
        ) ?? []

        // Zip by timestamp, compute cli/user ratio, skip where user==0
        let userByDate = Dictionary(userPoints.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        let result = cliPoints.compactMap { cli -> TimePoint? in
            guard let user = userByDate[cli.date], user > 0 else { return nil }
            return TimePoint(date: cli.date, value: cli.value / user)
        }
        return result
    }

    // MARK: - Core query

    private func queryMetric(
        _ metricKey: String,
        start: Int64,
        end: Int64,
        step: Int,
        panelType: String,
        reduceTo: String,
        filters: [String: Any]
    ) async -> [TimePoint]? {
        guard let url = URL(string: "\(baseURL)/api/v4/query_range") else { return nil }

        let body: [String: Any] = [
            "start": start,
            "end": end,
            "step": step,
            "variables": [:] as [String: Any],
            "compositeQuery": [
                "queryType": "builder",
                "panelType": panelType,
                "builderQueries": [
                    "A": [
                        "aggregateAttribute": [
                            "dataType": "float64",
                            "isColumn": true,
                            "key": metricKey,
                            "type": "Sum"
                        ],
                        "aggregateOperator": "sum",
                        "dataSource": "metrics",
                        "disabled": false,
                        "expression": "A",
                        "filters": filters,
                        "groupBy": [] as [Any],
                        "queryName": "A",
                        "reduceTo": reduceTo,
                        "spaceAggregation": "sum",
                        "stepInterval": step,
                        "timeAggregation": "sum"
                    ]
                ]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "SIGNOZ-API-KEY")

        guard let (data, response) = try? await urlSession.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let results = dataObj["result"] as? [[String: Any]],
              let firstResult = results.first,
              let series = firstResult["series"] as? [[String: Any]],
              let firstSeries = series.first,
              let values = firstSeries["values"] as? [[String: Any]] else { return nil }

        let points = values.compactMap { entry -> TimePoint? in
            guard let tsRaw = entry["timestamp"],
                  let valueStr = entry["value"] as? String,
                  let parsed = Double(valueStr) else { return nil }

            let tsMs: Int64
            if let tsInt = tsRaw as? Int64 {
                tsMs = tsInt
            } else if let tsInt = tsRaw as? Int {
                tsMs = Int64(tsInt)
            } else if let tsDouble = tsRaw as? Double {
                tsMs = Int64(tsDouble)
            } else {
                return nil
            }

            let date = Date(timeIntervalSince1970: TimeInterval(tsMs) / 1000)
            return TimePoint(date: date, value: parsed)
        }

        return points.isEmpty ? nil : points
    }

    // MARK: - Filter helpers

    private func emptyFilters() -> [String: Any] {
        ["items": [] as [Any], "op": "AND"]
    }

    private func makeFilter(key: String, value: String) -> [String: Any] {
        [
            "items": [
                [
                    "key": [
                        "dataType": "string",
                        "isColumn": false,
                        "key": key,
                        "type": "tag"
                    ],
                    "op": "=",
                    "value": value
                ]
            ],
            "op": "AND"
        ]
    }
}
