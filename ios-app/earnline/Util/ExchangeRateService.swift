import Foundation

/// Fetches the current exchange rate for the Settings "Fetch current rate"
/// button. open.er-api.com is keyless and — unlike the ECB feeds — quotes RUB
/// and UAH, which are first-class currencies here. Never called automatically:
/// whatever the user types stays authoritative.
enum ExchangeRateService {
    enum FetchError: LocalizedError, Equatable {
        case unsupportedPair(String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .unsupportedPair(let code):
                return String(localized: "No rate available for \(code).")
            case .malformedResponse:
                return String(localized: "The rate service sent an unexpected response.")
            }
        }
    }

    private struct Response: Decodable {
        let result: String
        let rates: [String: Double]
    }

    /// Secondary units per 1 base unit — the exact shape `AppModel.rate`
    /// stores. Rounded to 4 decimals so inverse pairs (e.g. RUB→USD ≈ 0.012)
    /// keep their precision while the field stays readable.
    static func fetch(base: String, secondary: String,
                      session: URLSession = .shared) async throws -> Double {
        let url = URL(string: "https://open.er-api.com/v6/latest/\(base)")!
        let (data, _) = try await session.data(from: url)
        return try rate(from: data, secondary: secondary)
    }

    /// Decode + validate a response payload (split out for tests).
    static func rate(from data: Data, secondary: String) throws -> Double {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.result == "success" else {
            throw FetchError.malformedResponse
        }
        guard let rate = response.rates[secondary], rate.isFinite, rate > 0 else {
            throw FetchError.unsupportedPair(secondary)
        }
        return (rate * 10_000).rounded() / 10_000
    }
}
