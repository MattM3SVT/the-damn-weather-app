import Foundation

/// Errors surfaced by METARClient. METAR doesn't have an "outside coverage" concept
/// (global) so everything non-success is treated as transient.
public enum METARError: Error {
    case transient
    case decode
}

/// Stateless HTTP client for aviationweather.gov METAR JSON endpoint.
public struct METARClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the latest METAR for an ICAO station and derives the dominant SkyCover.
    /// Returns nil when data is unavailable or stale.
    public func fetchSkyCover(icao: String) async throws -> SkyCover? {
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: icao),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw METARError.decode }

        var request = URLRequest(url: url)
        request.setValue(METARClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConstants.crossCheckHTTPTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw METARError.transient
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw METARError.transient
        }

        let observations: [METARObservation]
        do {
            observations = try JSONDecoder().decode([METARObservation].self, from: data)
        } catch {
            throw METARError.decode
        }

        guard let obs = observations.first else { return nil }

        // Freshness filter. METAR `reportTime` is epoch seconds (Unix time).
        if let reportEpoch = obs.obsTime {
            let reported = Date(timeIntervalSince1970: TimeInterval(reportEpoch))
            if Date().timeIntervalSince(reported) > AppConstants.observationMaxStaleness {
                return nil
            }
        }

        // Dominant cover = highest coverage across all layers. If `clouds` is empty,
        // the aircraft reported CAVOK / clear sky — treat as clear.
        guard let clouds = obs.clouds else { return nil }
        if clouds.isEmpty { return .clear }
        let covers = clouds.compactMap { SkyCover.parse($0.cover) }
        return covers.max()
    }

    private static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        return "TheDamnWeather/\(version) (iOS; \(AppConstants.nwsSupportEmail))"
    }()
}

// MARK: - Decodable

private struct METARObservation: Decodable {
    let obsTime: Int?       // Unix epoch seconds
    let clouds: [Cloud]?
}

private struct Cloud: Decodable {
    let cover: String?
}
