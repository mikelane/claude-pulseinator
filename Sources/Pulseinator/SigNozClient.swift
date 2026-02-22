import Foundation
import Observation

@Observable
class SigNozClient {
    var isAvailable: Bool = false
    var tokens: Double = 0
    var costUSD: Double = 0
    var sessions: Int = 0
    var linesChanged: Int = 0
    var commits: Int = 0
    var decisions: Int = 0
    var selectedWindow: TimeWindow = .threeHours

    enum TimeWindow: String, CaseIterable {
        case oneHour = "1h"
        case threeHours = "3h"
        case twelveHours = "12h"
        case twentyFourHours = "24h"

        var milliseconds: Int64 {
            switch self {
            case .oneHour:        return 3_600_000
            case .threeHours:     return 10_800_000
            case .twelveHours:    return 43_200_000
            case .twentyFourHours: return 86_400_000
            }
        }

        var stepSeconds: Int {
            switch self {
            case .oneHour:        return 3600
            case .threeHours:     return 10800
            case .twelveHours:    return 43200
            case .twentyFourHours: return 86400
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

        guard let first = await queryMetric("claude_code.token.usage", start: startMs, end: endMs, step: step) else {
            isAvailable = false
            return
        }
        isAvailable = true
        tokens = first

        if let v = await queryMetric("claude_code.cost.usage", start: startMs, end: endMs, step: step) {
            costUSD = v
        }
        if let v = await queryMetric("claude_code.session.count", start: startMs, end: endMs, step: step) {
            sessions = Int(v)
        }
        if let v = await queryMetric("claude_code.lines_of_code.count", start: startMs, end: endMs, step: step) {
            linesChanged = Int(v)
        }
        if let v = await queryMetric("claude_code.commit.count", start: startMs, end: endMs, step: step) {
            commits = Int(v)
        }
        if let v = await queryMetric("claude_code.code_edit_tool.decision", start: startMs, end: endMs, step: step) {
            decisions = Int(v)
        }
    }

    private func queryMetric(_ metricKey: String, start: Int64, end: Int64, step: Int) async -> Double? {
        guard let url = URL(string: "\(baseURL)/api/v4/query_range") else { return nil }

        let body: [String: Any] = [
            "start": start,
            "end": end,
            "step": step,
            "variables": [:] as [String: Any],
            "compositeQuery": [
                "queryType": "builder",
                "panelType": "value",
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
                        "filters": ["items": [] as [Any], "op": "AND"],
                        "groupBy": [] as [Any],
                        "queryName": "A",
                        "reduceTo": "sum",
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
              let values = firstSeries["values"] as? [[String: Any]],
              let firstValue = values.first,
              let valueStr = firstValue["value"] as? String,
              let parsed = Double(valueStr) else { return nil }

        return parsed
    }
}
