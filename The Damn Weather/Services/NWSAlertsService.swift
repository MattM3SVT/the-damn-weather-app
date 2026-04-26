import Foundation
import CoreLocation
import WeatherShared
import os.log

nonisolated private let nwsAlertsLog = Logger(subsystem: "DamnWeather", category: "NWSAlerts")

/// Detailed alert data fetched directly from `api.weather.gov/alerts/active`.
/// WeatherKit only exposes a short summary plus a web `detailsURL`, so we
/// pull the full NWS-issued text from NWS and match it back to the
/// corresponding WeatherKit alert by event name. US-only — non-US locations
/// will return an empty array and the UI falls back to the WeatherKit web view.
struct NWSAlertDetail: Sendable {
    let event: String           // "Frost Advisory"
    let severity: String        // "Minor" | "Moderate" | "Severe" | "Extreme" | "Unknown"
    let headline: String?       // Long form ("Frost Advisory issued April 25 at 6:39PM PDT…")
    let description: String?    // Full body — `* WHAT…  * WHERE…  * WHEN…`
    let instruction: String?    // Recommended actions
    let areaDesc: String?       // Affected counties / zones
    let onset: Date?
    let ends: Date?
    let expires: Date?
}

/// Fetches detailed alert data from NWS for a given location. Caches per
/// quantized location for the same TTL as the observation cross-check (30 min).
/// All errors degrade silently to an empty array — the UI then falls back to
/// the WeatherKit web view.
actor NWSAlertsService {
    private let session: URLSession
    private var cache: [String: CacheEntry] = [:]

    private struct CacheEntry {
        let alerts: [NWSAlertDetail]
        let fetchedAt: Date
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchActiveAlerts(for location: CLLocation) async -> [NWSAlertDetail] {
        let key = cacheKey(for: location)
        if let entry = cache[key],
           Date().timeIntervalSince(entry.fetchedAt) < AppConstants.observationCacheTTL {
            return entry.alerts
        }

        do {
            let alerts = try await fetchFromNetwork(for: location)
            cache[key] = CacheEntry(alerts: alerts, fetchedAt: Date())
            return alerts
        } catch {
            nwsAlertsLog.warning("NWS alerts fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    private func fetchFromNetwork(for location: CLLocation) async throws -> [NWSAlertDetail] {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let path = String(format: "https://api.weather.gov/alerts/active?point=%.4f,%.4f", lat, lon)
        guard let url = URL(string: path) else { return [] }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConstants.crossCheckHTTPTimeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return [] }
        // 404 = outside NWS coverage (most non-US locations). Other non-2xx are
        // transient. Either way: empty result, UI falls back to web view.
        guard (200..<300).contains(http.statusCode) else { return [] }

        let decoded = try JSONDecoder.iso8601FlexibleAlerts.decode(AlertsResponse.self, from: data)
        return decoded.features.map(NWSAlertDetail.init(from:))
    }

    private func cacheKey(for location: CLLocation) -> String {
        // Quantize to ~5km so neighboring requests share a cache entry.
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }

    /// NWS requires an identifying User-Agent — see api.weather.gov terms.
    private static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return "TheDamnWeather/\(version) (iOS; \(AppConstants.nwsSupportEmail))"
    }()
}

// MARK: - Decodables
//
// All marked `nonisolated` so they can be decoded / used from inside the
// `NWSAlertsService` actor. Without this, the main-app target's default
// MainActor isolation propagates to these types and the actor can't decode
// them cross-isolation.

private nonisolated struct AlertsResponse: Decodable {
    let features: [AlertFeature]
}

private nonisolated struct AlertFeature: Decodable {
    let properties: AlertProperties
}

private nonisolated struct AlertProperties: Decodable {
    let event: String
    let severity: String
    let headline: String?
    let description: String?
    let instruction: String?
    let areaDesc: String?
    let onset: Date?
    let ends: Date?
    let expires: Date?
}

nonisolated private extension NWSAlertDetail {
    init(from feature: AlertFeature) {
        let p = feature.properties
        self.init(
            event: p.event,
            severity: p.severity,
            headline: p.headline,
            description: p.description,
            instruction: p.instruction,
            areaDesc: p.areaDesc,
            onset: p.onset,
            ends: p.ends,
            expires: p.expires
        )
    }
}

nonisolated private extension JSONDecoder {
    /// NWS timestamps look like "2026-04-25T18:39:00-07:00". A few endpoints
    /// emit fractional seconds. Accept both.
    static let iso8601FlexibleAlerts: JSONDecoder = {
        let d = JSONDecoder()
        // Construct a fresh formatter inside each decode call rather than
        // capturing one — `ISO8601DateFormatter` isn't Sendable.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: str) { return date }
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
