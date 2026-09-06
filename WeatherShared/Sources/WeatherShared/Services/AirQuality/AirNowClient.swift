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
    public let stateCode: String?     // nil on the 2026 current endpoint — column was dropped
    public let siteID: String?        // AQS site id, 2026 current endpoint only; often blank
    public let parameterName: String  // "O3", "OZONE", "PM2.5", "PM10", "CO", "NO2", "SO2"
    public let aqi: Int
    public let categoryNumber: Int?   // 1-6 (Good..Hazardous); nil on the 2026 endpoints
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
    /// reporting at the nearest monitor). Throws `outsideCoverage` when AirNow
    /// reports no monitors in range.
    ///
    /// Uses the June 2026 replacement service. The old
    /// `aq/observation/latLong/current` retires 2026-09-30. Note there is no
    /// `distance` parameter any more: the new service always uses a fixed
    /// 50-mile lookup boundary (verified live — passing `distance=5` returns
    /// the same rows, still labelled `LookupBoundary = "50 Miles"`).
    public func fetchCurrentObservation(
        lat: Double,
        lon: Double,
        apiKey: String
    ) async throws -> [AirNowReading] {
        let url = try buildURL(
            path: "aq/observation/current/ziplatlong",
            lat: lat,
            lon: lon,
            extraItems: [],
            apiKey: apiKey
        )
        let readings = try await fetchAndParse(url: url)
        if readings.isEmpty { throw AirNowError.outsideCoverage }
        return readings
    }

    /// Yesterday's daily AQI for every reporting area in `stateCode`, from the
    /// June 2026 replacement for the retiring lat/long historical service.
    ///
    /// There is no lat/long historical service any more, so callers resolve the
    /// state themselves and filter the response down to their reporting area
    /// (see `AirQualityService.fetchHistorical`). Responses are small enough to
    /// fetch whole — California, the largest, is ~14 KB across 133 areas.
    ///
    /// `stateCode` is the USPS two-letter code ("CA", "PR", "DC"); the service
    /// rejects FIPS numerics. Returns 0..n rows; an empty result is normal for
    /// a state with no reporting that day and is not an error.
    public func fetchHistoricalDailyObservations(
        stateCode: String,
        date: Date,
        apiKey: String
    ) async throws -> [AirNowReading] {
        let day = Self.dayParam(for: date)
        let url = try buildURL(
            path: "aq/observation/historical/state",
            items: [
                URLQueryItem(name: "stateCode", value: stateCode),
                // The service requires a range; a single day is start == end.
                URLQueryItem(name: "startDate", value: day),
                URLQueryItem(name: "endDate", value: day)
            ],
            apiKey: apiKey
        )
        return try await fetchAndParse(url: url)
    }

    /// The reporting area and its USPS state code for a lat/lon, read off the
    /// current-forecast service.
    ///
    /// This exists only to resolve the state that
    /// `fetchHistoricalDailyObservations` needs. It's the authoritative answer
    /// because it's AirNow's own reporting-area-to-state mapping: the nearest
    /// *monitor* can sit in a different state than the reporting area it feeds
    /// (Memphis is served by a monitor in Arkansas), so deriving the state from
    /// a monitor id gets cross-border metros wrong.
    ///
    /// Returns nil when the area has no forecast at all — true for Anchorage
    /// and San Juan, which report observations but no forecast.
    public func fetchReportingAreaState(
        lat: Double,
        lon: Double,
        apiKey: String
    ) async throws -> (reportingArea: String, stateCode: String)? {
        let url = try buildURL(
            path: "aq/forecast/current",
            items: [
                URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
                URLQueryItem(name: "longitude", value: String(format: "%.4f", lon))
            ],
            apiKey: apiKey
        )
        let text = try await fetchText(url: url)
        if let failure = Self.webServiceError(in: text) { throw failure }
        return Self.parseForecastArea(text)
    }

    // MARK: - Private

    private func buildURL(
        path: String,
        lat: Double,
        lon: Double,
        extraItems: [URLQueryItem],
        apiKey: String
    ) throws -> URL {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon))
        ]
        items.append(contentsOf: extraItems)
        return try buildURL(path: path, items: items, apiKey: apiKey)
    }

    private func buildURL(
        path: String,
        items extraItems: [URLQueryItem],
        apiKey: String
    ) throws -> URL {
        var components = URLComponents(string: "https://www.airnowapi.org/\(path)")
        var items: [URLQueryItem] = [URLQueryItem(name: "format", value: "text/csv")]
        items.append(contentsOf: extraItems)
        items.append(URLQueryItem(name: "API_KEY", value: apiKey))
        components?.queryItems = items
        guard let url = components?.url else { throw AirNowError.decode }
        return url
    }

    /// `startDate`/`endDate` on the historical service are plain `yyyy-MM-dd`.
    /// Formatted in device-local time because AirNow treats the date as the
    /// location's local calendar day; formatting in UTC would shift it by up
    /// to 12h and misreport "yesterday" near local midnight.
    private static func dayParam(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Pulls `ReportingArea` + `StateCode` off the first forecast row. The
    /// forecast schema is unrelated to the observation one (it has no hour or
    /// AQI-per-observation columns), so it gets its own small parse rather
    /// than going through `parseCSV`.
    static func parseForecastArea(_ text: String) -> (reportingArea: String, stateCode: String)? {
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard lines.count > 1 else { return nil }

        var columns: [String: Int] = [:]
        for (index, name) in splitCSVRow(String(lines[0])).enumerated() {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty, columns[key] == nil { columns[key] = index }
        }
        guard let areaIndex = columns["reportingarea"],
              let stateIndex = columns["statecode"] else { return nil }

        for line in lines.dropFirst() {
            let fields = splitCSVRow(String(line))
            guard areaIndex < fields.count, stateIndex < fields.count else { continue }
            let area = fields[areaIndex].trimmingCharacters(in: .whitespaces)
            let state = fields[stateIndex].trimmingCharacters(in: .whitespaces)
            if !area.isEmpty, !state.isEmpty { return (area, state) }
        }
        return nil
    }

    private func fetchAndParse(url: URL) async throws -> [AirNowReading] {
        let text = try await fetchText(url: url)
        if let failure = Self.webServiceError(in: text) { throw failure }
        return Self.parseCSV(text)
    }

    private func fetchText(url: URL) async throws -> String {
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
        return text
    }

    /// The 2026 services signal "no monitors in range" as HTTP 200 with a
    /// `WebServiceError` body rather than the empty body the legacy services
    /// returned, so a 2xx status alone no longer means there is data:
    ///
    ///     WebServiceError
    ///     "There are no observations available for the requested
    ///      latitude/longitude: No observations were found for all monitors
    ///      within 50 miles."
    ///
    /// Only the no-data message maps to `outsideCoverage` (which callers may
    /// cache). Any other `WebServiceError` at 200 is treated as `transient` so
    /// a server-side hiccup doesn't get cached as "this location has no air
    /// quality data". Returns nil when the body is a normal CSV response.
    static func webServiceError(in text: String) -> AirNowError? {
        let head = text.prefix(64)
        guard head.hasPrefix("WebServiceError") else { return nil }
        let lowered = text.lowercased()
        if lowered.contains("no observations") || lowered.contains("no data") {
            return .outsideCoverage
        }
        return .transient
    }

    // MARK: - CSV parsing

    /// Column aliases, lowercased. The June 2026 services renamed and reordered
    /// most columns, so we resolve fields by header name instead of by fixed
    /// index — that keeps one parser working across both schemas during the
    /// migration, and means a future reordering degrades to "column missing"
    /// rather than silently reading the wrong column.
    ///
    ///     legacy: DateObserved,HourObserved,LocalTimeZone,ReportingArea,
    ///             StateCode,Latitude,Longitude,ParameterName,AQI,
    ///             CategoryNumber,CategoryName
    ///     2026:   DateObserved,HourObserved,LocalTimeZone,ReportingAreaName,
    ///             SiteID,SiteName,ParameterName,NowcastAQI,AqiCategoryName,
    ///             ReportingAgency,LookupBehavior,ConsideredMonitors,
    ///             LookupBoundary
    ///     daily:  DateObserved,StateCode,ReportingAreaName,ParameterName,
    ///             DailyAQI,DailyAQICategoryName
    private enum Column {
        static let date = ["dateobserved"]
        static let hour = ["hourobserved"]
        static let timeZone = ["localtimezone"]
        static let area = ["reportingarea", "reportingareaname"]
        static let state = ["statecode"]
        static let site = ["siteid"]
        static let parameter = ["parametername"]
        static let aqi = ["aqi", "nowcastaqi", "dailyaqi"]
        static let categoryNumber = ["categorynumber"]
        static let categoryName = ["categoryname", "aqicategoryname", "dailyaqicategoryname"]
    }

    /// Minimal CSV parser for AirNow's tabular responses. Values may or may not
    /// be quoted (the 2026 services leave numeric columns bare), and there is a
    /// single header row which we use to locate each field by name.
    ///
    /// Silently skips rows that don't parse rather than throwing, because a
    /// single malformed row from AirNow shouldn't nuke the entire fetch.
    static func parseCSV(_ text: String) -> [AirNowReading] {
        // Split on any newline style. NOT `split(separator: "\n")` — Swift
        // treats "\r\n" as a single grapheme cluster, so that call would see
        // a CRLF response as one giant line and parse zero rows.
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }

        // Header name (lowercased, trimmed) -> column index.
        var columns: [String: Int] = [:]
        for (index, name) in splitCSVRow(String(lines[0])).enumerated() {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty, columns[key] == nil { columns[key] = index }
        }

        func field(_ fields: [String], _ aliases: [String]) -> String? {
            for alias in aliases {
                guard let index = columns[alias], index < fields.count else { continue }
                let value = fields[index].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
            return nil
        }

        // The daily schema has no hour column at all. That's a shape difference,
        // not a malformed row, so absent-entirely means hour 0 (matching how
        // the legacy daily endpoint reported it) while present-but-unparseable
        // still skips the row.
        let hasHourColumn = Column.hour.contains { columns[$0] != nil }

        var readings: [AirNowReading] = []
        // Skip index 0 (header row).
        for line in lines.dropFirst() {
            let fields = splitCSVRow(String(line))
            guard let date = field(fields, Column.date),
                  let parameter = field(fields, Column.parameter),
                  let aqi = field(fields, Column.aqi).flatMap(Int.init) else { continue }
            var hour = 0
            if hasHourColumn {
                guard let parsed = field(fields, Column.hour).flatMap(parseHour) else { continue }
                hour = parsed
            }
            readings.append(AirNowReading(
                dateObserved: date,
                hourObserved: hour,
                localTimeZone: field(fields, Column.timeZone) ?? "",
                reportingArea: field(fields, Column.area),
                stateCode: field(fields, Column.state),
                siteID: field(fields, Column.site),
                parameterName: parameter,
                aqi: aqi,
                categoryNumber: field(fields, Column.categoryNumber).flatMap(Int.init),
                categoryName: field(fields, Column.categoryName) ?? ""
            ))
        }
        return readings
    }

    /// `HourObserved` is a bare hour on the legacy services ("21") and a
    /// local wall-clock time on the 2026 ones ("10:00"). Both reduce to the
    /// hour; AirNow only ever reports on the hour. Returns nil for anything
    /// that isn't a valid 0-23 hour so the row gets skipped.
    static func parseHour(_ raw: String) -> Int? {
        let hourPart = raw.split(separator: ":", maxSplits: 1).first.map(String.init) ?? raw
        guard let hour = Int(hourPart), (0...23).contains(hour) else { return nil }
        return hour
    }

    /// USPS state code for an AQS site id, whose leading two digits after any
    /// country prefix are the state FIPS code. Two lengths occur in practice:
    /// nine digits (`360470118` — NY) and twelve with a leading `840` ISO
    /// country code (`840060731026` — CA), so we take the trailing nine.
    ///
    /// This is a *fallback* for `fetchReportingAreaState`, used only where a
    /// reporting area has no forecast. It answers "which state is this monitor
    /// in", which is not always "which state owns this reporting area" — the
    /// two differ for cross-border metros. Returns nil for a blank id (common;
    /// areas aggregating several sites report no single id), an unrecognised
    /// FIPS code, or a non-US site.
    static func stateCode(forSiteID siteID: String?) -> String? {
        guard let siteID else { return nil }
        let digits = siteID.filter(\.isNumber)
        guard digits.count >= 9 else { return nil }
        let fips = String(digits.suffix(9).prefix(2))
        return fipsToUSPS[fips]
    }

    /// State/territory FIPS to USPS. Only entries AirNow can report are needed,
    /// so foreign AQS codes (Canada, Mexico) are deliberately absent and
    /// resolve to nil.
    private static let fipsToUSPS: [String: String] = [
        "01": "AL", "02": "AK", "04": "AZ", "05": "AR", "06": "CA", "08": "CO",
        "09": "CT", "10": "DE", "11": "DC", "12": "FL", "13": "GA", "15": "HI",
        "16": "ID", "17": "IL", "18": "IN", "19": "IA", "20": "KS", "21": "KY",
        "22": "LA", "23": "ME", "24": "MD", "25": "MA", "26": "MI", "27": "MN",
        "28": "MS", "29": "MO", "30": "MT", "31": "NE", "32": "NV", "33": "NH",
        "34": "NJ", "35": "NM", "36": "NY", "37": "NC", "38": "ND", "39": "OH",
        "40": "OK", "41": "OR", "42": "PA", "44": "RI", "45": "SC", "46": "SD",
        "47": "TN", "48": "TX", "49": "UT", "50": "VT", "51": "VA", "53": "WA",
        "54": "WV", "55": "WI", "56": "WY", "60": "AS", "66": "GU", "69": "MP",
        "72": "PR", "78": "VI"
    ]

    /// Splits one CSV row, handling quoted values. AirNow's output is
    /// well-formed (no embedded commas in data fields, no embedded quotes), so
    /// this doesn't need to be an RFC 4180-complete parser — just strip the
    /// wrapping quotes where they're present. The 2026 services quote text
    /// columns but leave numeric ones bare, so quoting is per-field.
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
