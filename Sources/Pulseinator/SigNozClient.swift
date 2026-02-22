import Foundation
import Observation

@Observable
class SigNozClient {
    var isAvailable: Bool = false
    var services: [String] = []
    var errorCount: Int = 0
    var traceCount: Int = 0
    var selectedWindow: TimeWindow = .oneHour

    enum TimeWindow: String, CaseIterable {
        case oneHour = "1h"
        case threeHours = "3h"
        case twelveHours = "12h"
        case twentyFourHours = "24h"
    }

    private let baseURL = "http://127.0.0.1:8080"
    private let apiKey = "<YOUR_SIGNOZ_API_KEY>"

    private var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func refresh() async {
        await checkAvailability()
        guard isAvailable else { return }
        await fetchMetrics()
    }

    private func checkAvailability() async {
        guard let url = URL(string: "\(baseURL)/api/v1/services") else {
            isAvailable = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "SIGNOZ-API-KEY")

        guard let (data, response) = try? await urlSession.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            isAvailable = false
            return
        }

        isAvailable = true

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let serviceList = json["data"] as? [[String: Any]] {
            services = serviceList.compactMap { $0["serviceName"] as? String }
        } else if let serviceArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
            services = serviceArray
        }
    }

    private func fetchMetrics() async {
        let endTime = Int(Date().timeIntervalSince1970 * 1000)
        let startTime = endTime - windowMilliseconds

        if let url = URL(string: "\(baseURL)/api/v1/traces?start=\(startTime)&end=\(endTime)&limit=1") {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "SIGNOZ-API-KEY")

            if let (data, _) = try? await urlSession.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let total = json["total"] as? Int {
                    traceCount = total
                } else if let traces = json["data"] as? [[String: Any]] {
                    traceCount = traces.count
                }
            }
        }

        if let url = URL(string: "\(baseURL)/api/v1/errors?start=\(startTime)&end=\(endTime)&limit=1") {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "SIGNOZ-API-KEY")

            if let (data, _) = try? await urlSession.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let total = json["total"] as? Int {
                    errorCount = total
                } else if let errors = json["data"] as? [[String: Any]] {
                    errorCount = errors.count
                }
            }
        }
    }

    private var windowMilliseconds: Int {
        switch selectedWindow {
        case .oneHour: return 3_600_000
        case .threeHours: return 10_800_000
        case .twelveHours: return 43_200_000
        case .twentyFourHours: return 86_400_000
        }
    }
}
