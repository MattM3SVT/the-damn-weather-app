import Foundation

/// Errors surfaced by NWSClient. Distinguishes "not covered" (cacheable) from
/// "transient" (don't cache; retry on next foreground).
public enum NWSError: Error {
    case outsideCoverage   // HTTP 404 from /points — NWS doesn't serve this lat/lon
    case transient         // 5xx, timeout, network failure
    case decode            // unexpected JSON
}

/// Stateless HTTP client for api.weather.gov. All methods throw — the orchestrator
/// translates thrown errors into SkyConsensus nil fields.
public struct NWSClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 1. points → observationStations URL

    /// Resolves `/points/{lat},{lon}` and returns the URL of the stations list for that grid cell.
    public func fetchObservationStationsURL(lat: Double, lon: Double) async throws -> URL {
        let path = String(format: "https://api.weather.gov/points/%.4f,%.4f", lat, lon)
        guard let url = URL(string: path) else { throw NWSError.decode }
        let (data, response) = try await perform(url: url)
        try validateStatus(response)
        do {
            let decoded = try JSONDecoder().decode(NWSPoint.self, from: data)
            return decoded.properties.observationStations
        } catch {
            throw NWSError.decode
        }
    }

    // MARK: - 2. stations → nearest ASOS-class ICAO

    /// Pulls the stations list (ordered by distance) and returns the nearest station ID
    /// whose provider is ASOS-class and whose identifier is a 4-character ICAO.
    /// Returns nil when no station in the list qualifies.
    public func fetchNearestICAO(from stationsURL: URL) async throws -> String? {
        let (data, response) = try await perform(url: stationsURL)
        try validateStatus(response)
        let collection: StationsCollection
        do {
            collection = try JSONDecoder().decode(StationsCollection.self, from: data)
        } catch {
            throw NWSError.decode
        }
        let asosClass: Set<String> = ["ASOS", "ASOS-HFM", "AWOS"]
        for feature in collection.features {
            let id = feature.properties.stationIdentifier
            let provider = feature.properties.provider ?? ""
            guard id.count == 4, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
            if asosClass.contains(provider) {
                return id
            }
        }
        return nil
    }

    // MARK: - 3. latest observation → SkyCover

    /// Fetches the latest observation for an ICAO station and derives the dominant
    /// SkyCover. Returns nil when data is unavailable: null cloudLayers, all amounts
    /// null, timestamp older than 2h, etc.
    public func fetchSkyCover(stationID: String) async throws -> SkyCover? {
        let path = "https://api.weather.gov/stations/\(stationID)/observations/latest"
        guard let url = URL(string: path) else { throw NWSError.decode }
        let (data, response) = try await perform(url: url)
        try validateStatus(response)
        let observation: Observation
        do {
            observation = try JSONDecoder.iso8601Flexible.decode(Observation.self, from: data)
        } catch {
            throw NWSError.decode
        }

        // Freshness filter: reject observations older than 2h.
        if let ts = observation.properties.timestamp,
           Date().timeIntervalSince(ts) > AppConstants.observationMaxStaleness {
            return nil
        }

        // Null cloudLayers = sensor didn't report sky. No data.
        guard let layers = observation.properties.cloudLayers else { return nil }

        // Empty cloudLayers + non-nil timestamp is a positive "clear sky" signal.
        if layers.isEmpty { return .clear }

        // Dominant cover = highest coverage reported across all layers.
        let covers = layers.compactMap { SkyCover.parse($0.amount) }
        return covers.max()
    }

    // MARK: - Private

    private func perform(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(NWSClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConstants.crossCheckHTTPTimeout
        do {
            return try await session.data(for: request)
        } catch {
            throw NWSError.transient
        }
    }

    private func validateStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw NWSError.transient }
        switch http.statusCode {
        case 200..<300: return
        case 404:       throw NWSError.outsideCoverage
        case 500..<600: throw NWSError.transient
        default:        throw NWSError.transient
        }
    }

    /// Built once at init from bundle info. Format required by api.weather.gov:
    /// "App/version (platform; contact)". Falls back to a hardcoded version
    /// rather than "unknown" so the widget-extension bundle (which can report
    /// a differently-keyed `CFBundleShortVersionString`) still advertises a
    /// real version to NWS. NWS requires an identifying UA string.
    private static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "1.0"
        return "TheDamnWeather/\(version) (iOS; \(AppConstants.nwsSupportEmail))"
    }()
}

// MARK: - Decodables (NWS GeoJSON shapes)

private struct NWSPoint: Decodable {
    let properties: NWSPointProperties
}

private struct NWSPointProperties: Decodable {
    let observationStations: URL
}

private struct StationsCollection: Decodable {
    let features: [StationFeature]
}

private struct StationFeature: Decodable {
    let properties: StationProperties
}

private struct StationProperties: Decodable {
    let stationIdentifier: String
    let provider: String?
}

private struct Observation: Decodable {
    let properties: ObservationProperties
}

private struct ObservationProperties: Decodable {
    let timestamp: Date?
    let cloudLayers: [CloudLayer]?
}

private struct CloudLayer: Decodable {
    let amount: String?
}

private extension JSONDecoder {
    /// Handles NWS timestamps like "2026-04-20T15:53:00+00:00" (ISO 8601 with offset).
    static let iso8601Flexible: JSONDecoder = {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            // Fallback: try with fractional seconds
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable date: \(str)"
            )
        }
        return d
    }()
}
