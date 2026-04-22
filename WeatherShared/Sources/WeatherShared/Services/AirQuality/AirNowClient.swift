import Foundation

/// Errors surfaced by AirNowClient. `outsideCoverage` is used when the API
/// returns 200 but no readings, matching how NWSClient distinguishes cacheable
/// "no data here" from transient failures.
public enum AirNowError: Error {
    case missingKey        // caller-side: no API key configured
    case unauthorized      // server returned 401/403 — key is invalid or revoked
    case outsideCoverage   // 200 OK with empty body — no reporting area within radius
    case transient         // 5xx, timeout, network failure
    case decode            // unexpected response shape
}

/// One AirNow observation row. Both the `current` and `historical` endpoints
/// return one row per pollutant per observation. AirNow's *free* historical
/// endpoint returns a daily aggregate (the peak AQI reported that day per
/// pollutant), not hourly data — we use it only to produce the
/// "compared to yesterday" line under the gauge, not a trend chart.
public struct AirNowReading: Sendable {
    public let dateObserved: String   // "yyyy-MM-dd"
    public let hourObserved: Int      // 0-23 local time (0 in daily-historical rows)
    public let localTimeZone: String  // "PST", "EDT", etc.
    public let reportingArea: String?
    public let stateCode: String?
    public let parameterName: String  // "O3", "OZONE", "PM2.5", "PM10", "CO", "NO2", "SO2"
    public let aqi: Int
    public let categoryNumber: Int    // 1-6 (Good..Hazardous)
    public let categoryName: String   // "Good", "Moderate", etc.
}

/// Stateless HTTP client for www.airnowapi.org.
///
/// **Format choice: CSV, not JSON.** AirNow's JSON backend has been
/// intermittently returning HTTP 504 Gateway Timeout (verified by hitting the
/// endpoint directly: JSON → 504 after ~15s, CSV → 200 in <1s). CSV is served
/// by a different backend process and is reliable. We parse the small tabular
/// response by hand to avoid pulling in a CSV dependency.
public struct AirNowClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Current observation at a lat/lon. Returns 0..n rows (one per pollutant
    /// reporting at the nearest monitor). Throws `outsideCoverage` when the
    /// response is 200 OK but empty (outside any reporting area within radius).
    public func fetchCurrentObservation(
        lat: Double,
        lon: Double,
        apiKey: String
    ) async throws -> [AirNowReading] {
        let url = try buildURL(
            path: "aq/observation/latLong/current",
            lat: lat,
            lon: lon,
            extraItems: [URLQueryItem(name: "distance", value: "25")],
            apiKey: apiKey
        )
        let readings = try await fetchAndParse(url: url)
        if readings.isEmpty { throw AirNowError.outsideCoverage }
        return readings
    }

    /// Historical observation for the day containing `date`. AirNow's free
    /// historical endpoint is a daily aggregate — every row it returns has
    /// `HourObserved = 0` and reflects that day's AQI peak per pollutant.
    /// Callers use this only for yesterday-vs-today comparisons.
    public func fetchHistoricalObservation(
        lat: Double,
        lon: Double,
        date: Date,
        apiKey: String
    ) async throws -> [AirNowReading] {
        let dateParam = Self.historicalDateParam(for: date)
        let url = try buildURL(
            path: "aq/observation/latLong/historical",
            lat: lat,
            lon: lon,
            extraItems: [
                URLQueryItem(name: "date", value: dateParam),
                URLQueryItem(name: "distance", value: "25")
            ],
            apiKey: apiKey
        )
        // Historical can legitimately return an empty body for some days/locations.
        // Don't treat empty as outsideCoverage here — the caller decides.
        return try await fetchAndParse(url: url)
    }

    // MARK: - Private

    private func buildURL(
        path: String,
        lat: Double,
        lon: Double,
        extraItems: [URLQueryItem],
        apiKey: String
    ) throws -> URL {
        var components = URLComponents(string: "https://www.airnowapi.org/\(path)")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "text/csv"),
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "API_KEY", value: apiKey)
        ]
        items.append(contentsOf: extraItems)
        components?.queryItems = items
        guard let url = components?.url else { throw AirNowError.decode }
        return url
    }

    private func fetchAndParse(url: URL) async throws -> [AirNowReading] {
        var request = URLRequest(url: url)
        request.setValue(AirNowClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConstants.airNowHTTPTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AirNowError.transient
        }

        guard let http = response as? HTTPURLResponse else { throw AirNowError.transient }
        switch http.statusCode {
        case 200..<300: break
        case 400, 404: throw AirNowError.outsideCoverage
        case 401, 403: throw AirNowError.unauthorized
        case 500..<600: throw AirNowError.transient
        default: throw AirNowError.transient
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw AirNowError.decode
        }
        return Self.parseCSV(text)
    }

    /// AirNow's historical endpoint wants the date as `YYYY-MM-DDTHH-0000`.
    /// The hour is ignored by the free endpoint (data is daily), but the
    /// `THH-0000` suffix is still required for the URL to validate.
    ///
    /// Format in device-local time: AirNow interprets the date string as the
    /// calendar day at the requested lat/lon, which is effectively the
    /// location's local day. When the user is at that location, device-local
    /// matches location-local. Formatting in UTC instead would shift the
    /// calendar day by up to 12h and misreport "yesterday" near local midnight.
    private static func historicalDateParam(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH'-0000'"
        return formatter.string(from: date)
    }

    // MARK: - CSV parsing

    /// Minimal CSV parser for AirNow's fixed response shape. Columns are
    /// always quoted, comma-separated, with a single header row:
    ///
    ///   "DateObserved","HourObserved","LocalTimeZone","ReportingArea",
    ///   "StateCode","Latitude","Longitude","ParameterName","AQI",
    ///   "CategoryNumber","CategoryName"
    ///
    /// Silently skips rows that don't parse rather than throwing, because a
    /// single malformed row from AirNow shouldn't nuke the entire fetch.
    static func parseCSV(_ text: String) -> [AirNowReading] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        var readings: [AirNowReading] = []
        // Skip index 0 (header row).
        for line in lines.dropFirst() {
            let fields = splitCSVRow(String(line))
            guard fields.count >= 11 else { continue }
            guard let aqi = Int(fields[8]),
                  let categoryNum = Int(fields[9]),
                  let hour = Int(fields[1]) else { continue }
            let date = fields[0].trimmingCharacters(in: .whitespaces)
            readings.append(AirNowReading(
                dateObserved: date,
                hourObserved: hour,
                localTimeZone: fields[2],
                reportingArea: fields[3].isEmpty ? nil : fields[3],
                stateCode: fields[4].isEmpty ? nil : fields[4],
                parameterName: fields[7],
                aqi: aqi,
                categoryNumber: categoryNum,
                categoryName: fields[10]
            ))
        }
        return readings
    }

    /// Splits one CSV row, handling quoted values. AirNow's output is
    /// well-formed (every field quoted, no embedded commas in data fields,
    /// no embedded quotes), so this doesn't need to be an RFC 4180-complete
    /// parser — just strip the wrapping quotes.
    private static func splitCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else if char == "\r" {
                // ignore CR at end of line on Windows-style responses
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    /// Matches the User-Agent convention used by NWSClient and METARClient.
    private static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "1.0"
        return "TheDamnWeather/\(version) (iOS; \(AppConstants.nwsSupportEmail))"
    }()
}
