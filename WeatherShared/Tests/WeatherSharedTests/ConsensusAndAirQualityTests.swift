import Foundation
import Testing
@testable import WeatherShared

@Suite("applyConsensusOverride")
struct ConsensusOverrideTests {

    private func consensus(_ nws: SkyCover?, _ metar: SkyCover?) -> SkyConsensus {
        SkyConsensus(nws: nws, metar: metar)
    }

    @Test("both CLR overrides cloudy to clear")
    func overridesToClear() {
        let result = applyConsensusOverride(base: .cloudy, consensus: consensus(.clear, .clear), wkCloudCoverPct: 50)
        #expect(result == .clear)
    }

    @Test("both overcast overrides clear to cloudy")
    func overridesToCloudy() {
        let result = applyConsensusOverride(base: .clear, consensus: consensus(.overcast, .broken), wkCloudCoverPct: 50)
        #expect(result == .cloudy)
    }

    @Test("CLR + FEW is partly cloudy, not clear")
    func fewIsNotClear() {
        let result = applyConsensusOverride(base: .cloudy, consensus: consensus(.clear, .few), wkCloudCoverPct: 50)
        #expect(result == .partlyCloudy)
    }

    @Test("WK high-confidence cloudy blocks the override")
    func highConfidenceGuard() {
        let result = applyConsensusOverride(base: .cloudy, consensus: consensus(.clear, .clear), wkCloudCoverPct: 85)
        #expect(result == .cloudy)
    }

    @Test("WK low-confidence clear blocks the override")
    func lowConfidenceGuard() {
        let result = applyConsensusOverride(base: .clear, consensus: consensus(.overcast, .overcast), wkCloudCoverPct: 10)
        #expect(result == .clear)
    }

    @Test("straddling sources produce no override")
    func straddleNoOverride() {
        let result = applyConsensusOverride(base: .clear, consensus: consensus(.few, .broken), wkCloudCoverPct: 50)
        #expect(result == .clear)
    }

    @Test("precipitation tags always pass through")
    func precipPassThrough() {
        for base in [WeatherConditionTag.rain, .snow, .thunderstorm, .fog, .wind] {
            let result = applyConsensusOverride(base: base, consensus: consensus(.clear, .clear), wkCloudCoverPct: 50)
            #expect(result == base)
        }
    }

    @Test("missing or obscured sources produce no override")
    func missingSources() {
        #expect(applyConsensusOverride(base: .cloudy, consensus: consensus(nil, .clear), wkCloudCoverPct: 50) == .cloudy)
        #expect(applyConsensusOverride(base: .cloudy, consensus: consensus(.clear, nil), wkCloudCoverPct: 50) == .cloudy)
        #expect(applyConsensusOverride(base: .cloudy, consensus: consensus(.obscured, .clear), wkCloudCoverPct: 50) == .cloudy)
    }
}

@Suite("AirNowClient CSV parsing")
struct AirNowCSVTests {

    /// Verbatim shape of the legacy `latLong/current` response (Seattle,
    /// 2026-07-04 — the July 4th fireworks PM2.5 spike). The app no longer
    /// calls this service, but the parser stays compatible with its column
    /// names, and this pins that.
    private let liveCSV = """
    "DateObserved","HourObserved","LocalTimeZone","ReportingArea","StateCode","Latitude","Longitude","ParameterName","AQI","CategoryNumber","CategoryName"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","O3","18","1","Good"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","PM2.5","202","5","Very Unhealthy"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","PM10","95","2","Moderate"
    """

    /// Verbatim shape of the June 2026 `current/ziplatlong` response (captured
    /// live for San Francisco). Note the renamed columns, the `"10:00"` hour,
    /// the bare unquoted AQI, and the absent StateCode / CategoryNumber.
    private let liveCSV2026 = """
    "DateObserved","HourObserved","LocalTimeZone","ReportingAreaName","SiteID","SiteName","ParameterName","NowcastAQI","AqiCategoryName","ReportingAgency","LookupBehavior","ConsideredMonitors","LookupBoundary"
    "2026-09-06","10:00","PDT","San Francisco","060750005","San Francisco","PM2.5",4,"Good","Bay Area Air District","Closest Reading By Pollutant","All","50 Miles"
    "2026-09-06","10:00","PDT","San Francisco","060750005","San Francisco","OZONE",26,"Good","Bay Area Air District","Closest Reading By Pollutant","All","50 Miles"
    """

    @Test("parses legacy response shape")
    func parsesLiveShape() {
        let rows = AirNowClient.parseCSV(liveCSV)
        #expect(rows.count == 3)
        #expect(rows[0].parameterName == "O3")
        #expect(rows[0].aqi == 18)
        #expect(rows[1].parameterName == "PM2.5")
        #expect(rows[1].aqi == 202)
        #expect(rows[1].categoryNumber == 5)
        #expect(rows[0].reportingArea == "Seattle-Bellevue-Kent Valley")
        #expect(rows[0].stateCode == "WA")
        #expect(rows[0].localTimeZone == "PST")
        #expect(rows[0].hourObserved == 21)
    }

    @Test("parses 2026 response shape")
    func parses2026Shape() {
        let rows = AirNowClient.parseCSV(liveCSV2026)
        #expect(rows.count == 2)
        // NowcastAQI resolves as the AQI column, unquoted.
        #expect(rows[0].parameterName == "PM2.5")
        #expect(rows[0].aqi == 4)
        #expect(rows[1].parameterName == "OZONE")
        #expect(rows[1].aqi == 26)
        // ReportingAreaName / AqiCategoryName resolve to the same fields.
        #expect(rows[0].reportingArea == "San Francisco")
        #expect(rows[0].categoryName == "Good")
        // "10:00" reduces to hour 10; SiteName must not be mistaken for the area.
        #expect(rows[0].hourObserved == 10)
        #expect(rows[0].localTimeZone == "PDT")
        // Columns the 2026 schema dropped.
        #expect(rows[0].stateCode == nil)
        #expect(rows[0].categoryNumber == nil)
    }

    /// Verbatim shape of the daily `historical/state` response. It has no
    /// HourObserved column at all, and carries StateCode but no SiteID.
    private let dailyCSV = """
    "DateObserved","StateCode","ReportingAreaName","ParameterName","DailyAQI","DailyAQICategoryName"
    "2026-09-05","CA","San Francisco","OZONE",26,"Good"
    "2026-09-05","CA","San Francisco","PM2.5",24,"Good"
    "2026-09-05","CA","Redwood City","PM2.5",28,"Good"
    """

    @Test("parses daily historical-by-state shape")
    func parsesDailyShape() {
        let rows = AirNowClient.parseCSV(dailyCSV)
        // The absent HourObserved column must not skip every row.
        #expect(rows.count == 3)
        #expect(rows[0].parameterName == "OZONE")
        #expect(rows[0].aqi == 26)          // DailyAQI resolves as the AQI column
        #expect(rows[0].hourObserved == 0)  // no hour column -> daily rows are hour 0
        #expect(rows[0].stateCode == "CA")
        #expect(rows[0].reportingArea == "San Francisco")
        #expect(rows[0].categoryName == "Good")
        #expect(rows[2].reportingArea == "Redwood City")
        #expect(rows[0].siteID == nil)
    }

    /// A row whose hour column is present but unparseable is still malformed
    /// and must be skipped — "no hour column" and "bad hour value" differ.
    @Test("missing hour column differs from bad hour value")
    func hourColumnAbsentVsInvalid() {
        let badHour = """
        "DateObserved","HourObserved","LocalTimeZone","ReportingAreaName","ParameterName","NowcastAQI"
        "2026-09-06","NaN","PDT","San Francisco","PM2.5",4
        """
        #expect(AirNowClient.parseCSV(badHour).isEmpty)
    }

    @Test("2026 current rows expose SiteID")
    func siteIDParsed() {
        #expect(AirNowClient.parseCSV(liveCSV2026).first?.siteID == "060750005")
        // Blank SiteID (areas aggregating several sites) must read as nil.
        let blankSite = """
        "DateObserved","HourObserved","LocalTimeZone","ReportingAreaName","SiteID","SiteName","ParameterName","NowcastAQI"
        "2026-09-06","13:00","EDT","Boston Metro",,,"PM2.5",24
        """
        let rows = AirNowClient.parseCSV(blankSite)
        #expect(rows.count == 1)
        #expect(rows[0].siteID == nil)
        #expect(rows[0].reportingArea == "Boston Metro")
    }

    @Test("2026 rows feed the same pollutant mapping")
    func pollutantMappingAcrossSchemas() {
        // "O3" (legacy) and "OZONE" (2026) must land on the same pollutant,
        // otherwise ozone silently disappears after the migration.
        #expect(Pollutant(airNowName: "O3") == Pollutant(airNowName: "OZONE"))
        #expect(Pollutant(airNowName: "OZONE") != nil)
    }

    @Test("header-only response is empty")
    func headerOnly() {
        let header = "\"DateObserved\",\"HourObserved\",\"LocalTimeZone\",\"ReportingArea\",\"StateCode\",\"Latitude\",\"Longitude\",\"ParameterName\",\"AQI\",\"CategoryNumber\",\"CategoryName\""
        #expect(AirNowClient.parseCSV(header).isEmpty)
        #expect(AirNowClient.parseCSV("").isEmpty)
        #expect(AirNowClient.parseCSV(String(liveCSV2026.split(whereSeparator: \.isNewline)[0])).isEmpty)
    }

    @Test("malformed rows are skipped, not fatal")
    func malformedRowsSkipped() {
        let mixed = liveCSV + "\n\"garbage\",\"row\"\n\"2026-07-04\",\"NaN\",\"PST\",\"X\",\"WA\",\"0\",\"0\",\"O3\",\"not-a-number\",\"1\",\"Good\""
        #expect(AirNowClient.parseCSV(mixed).count == 3)
    }

    @Test("CRLF line endings parse identically")
    func crlfHandled() {
        #expect(AirNowClient.parseCSV(liveCSV.replacingOccurrences(of: "\n", with: "\r\n")).count == 3)
        #expect(AirNowClient.parseCSV(liveCSV2026.replacingOccurrences(of: "\n", with: "\r\n")).count == 2)
    }

    @Test("hour parsing accepts both schemas' formats")
    func hourParsing() {
        #expect(AirNowClient.parseHour("21") == 21)
        #expect(AirNowClient.parseHour("10:00") == 10)
        #expect(AirNowClient.parseHour("0") == 0)
        #expect(AirNowClient.parseHour("00:00") == 0)
        #expect(AirNowClient.parseHour("NaN") == nil)
        #expect(AirNowClient.parseHour("24") == nil)
        #expect(AirNowClient.parseHour("") == nil)
    }

    /// The 2026 services report "no monitors in range" as HTTP 200 with this
    /// body instead of the legacy empty body, so a 2xx status alone no longer
    /// means there is data.
    @Test("WebServiceError body maps to the right error")
    func webServiceErrorBody() {
        let noData = """
        WebServiceError
        "There are no observations available for the requested latitude/longitude: No observations were found for all monitors within 50 miles."
        """
        #expect(AirNowClient.webServiceError(in: noData) == .outsideCoverage)

        // Anything else at 200 must stay transient, so a server-side hiccup
        // isn't cached as "this location has no air quality data".
        #expect(AirNowClient.webServiceError(in: "WebServiceError\n\"Invalid Request.\"") == .transient)

        // A normal CSV body is not an error.
        #expect(AirNowClient.webServiceError(in: liveCSV2026) == nil)
        #expect(AirNowClient.webServiceError(in: liveCSV) == nil)
    }
}

@Suite("AirNow state resolution")
struct AirNowStateResolutionTests {

    /// Verbatim shape of the `forecast/current` response, used only to learn
    /// which state a reporting area belongs to.
    private let forecastCSV = """
    "DateIssue","DateValid","ReportingArea","ReportingAreaCode","StateCode","ParameterName","Aqi","ForecastAgency","CategoryNumber","CategoryName","ActionDay","Discussion"
    "2026-09-04","2026-09-06","Boston Metro","ma001","MA","PM2.5",-1,"Massachusetts Dept. of Environmental Protection",1,"Good",false,""
    "2026-09-04","2026-09-06","Boston Metro","ma001","MA","OZONE",-1,"Massachusetts Dept. of Environmental Protection",1,"Good",false,""
    """

    @Test("reads area and state off the forecast response")
    func parsesForecastArea() {
        let parsed = AirNowClient.parseForecastArea(forecastCSV)
        #expect(parsed?.reportingArea == "Boston Metro")
        #expect(parsed?.stateCode == "MA")
    }

    @Test("forecast parse tolerates missing or empty responses")
    func forecastEdgeCases() {
        #expect(AirNowClient.parseForecastArea("") == nil)
        // Header with no rows — areas that report observations but no forecast.
        #expect(AirNowClient.parseForecastArea(String(forecastCSV.split(whereSeparator: \.isNewline)[0])) == nil)
        // A response without the columns we need.
        #expect(AirNowClient.parseForecastArea("\"Foo\",\"Bar\"\n\"1\",\"2\"") == nil)
    }

    /// Site ids appear in two lengths: nine digits, and twelve with a leading
    /// 840 country code. Both must yield the same state.
    @Test("derives state from both site id formats")
    func siteIDFormats() {
        #expect(AirNowClient.stateCode(forSiteID: "360470118") == "NY")     // 9-digit
        #expect(AirNowClient.stateCode(forSiteID: "840060731026") == "CA")  // 840-prefixed
        #expect(AirNowClient.stateCode(forSiteID: "020200018") == "AK")
        #expect(AirNowClient.stateCode(forSiteID: "720330004") == "PR")
        #expect(AirNowClient.stateCode(forSiteID: "110010043") == "DC")
        #expect(AirNowClient.stateCode(forSiteID: "150031001") == "HI")
    }

    @Test("unusable site ids resolve to nil rather than a wrong state")
    func siteIDFallbackLimits() {
        #expect(AirNowClient.stateCode(forSiteID: nil) == nil)
        #expect(AirNowClient.stateCode(forSiteID: "") == nil)        // blank is common
        #expect(AirNowClient.stateCode(forSiteID: "12345") == nil)   // too short
        #expect(AirNowClient.stateCode(forSiteID: "990010001") == nil) // not a US FIPS
    }
}

@Suite("AirNow timezone abbreviations")
struct AirNowTimeZoneTests {

    private func offset(_ abbr: String, on day: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let zone = AirQualityService.timezoneForAirNowAbbreviation(abbr),
              let date = formatter.date(from: day) else { return nil }
        return zone.secondsFromGMT(for: date) / 3600
    }

    /// Every abbreviation must resolve to a zone whose UTC offset is correct on
    /// the date observed, in both halves of the year. The 2026 services report
    /// the observed abbreviation rather than always reporting standard time,
    /// so these now have to hold in summer too.
    @Test("abbreviations resolve to the right UTC offset")
    func offsets() {
        #expect(offset("PDT", on: "2026-09-06") == -7)
        #expect(offset("PST", on: "2026-01-06") == -8)
        #expect(offset("CDT", on: "2026-09-06") == -5)
        #expect(offset("CST", on: "2026-01-06") == -6)
        #expect(offset("EDT", on: "2026-09-06") == -4)
        #expect(offset("EST", on: "2026-01-06") == -5)
        #expect(offset("HST", on: "2026-09-06") == -10)
        #expect(offset("HADT", on: "2026-09-06") == -9)
        #expect(offset("ChST", on: "2026-09-06") == 10)
        #expect(offset("SST", on: "2026-09-06") == -11)
    }

    /// Phoenix stays on -7 all year while Denver shifts, and the legacy feed
    /// reported "MST" for both. The 2026 feed distinguishes them, so MST and
    /// MDT must resolve to different zones.
    @Test("MST is Phoenix, MDT is Denver")
    func mountainTimeSplit() {
        #expect(offset("MST", on: "2026-09-06") == -7)
        #expect(offset("MST", on: "2026-01-06") == -7)
        #expect(offset("MDT", on: "2026-09-06") == -6)
    }

    /// Puerto Rico has no DST and the 2026 feed correctly reports AST in
    /// summer. Resolving that through Halifax would give -3 instead of -4.
    @Test("AST is Puerto Rico, ADT is Halifax")
    func atlanticSplit() {
        #expect(offset("AST", on: "2026-09-06") == -4)
        #expect(offset("AST", on: "2026-01-06") == -4)
        #expect(offset("ADT", on: "2026-09-06") == -3)
    }

    /// Alaska reports KST/KDT on the 2026 feed and AKT on the legacy one.
    /// None of those were matched before, so Alaskan observations silently
    /// fell back to the device's timezone.
    @Test("Alaska spellings all resolve")
    func alaskaSpellings() {
        #expect(offset("KDT", on: "2026-09-06") == -8)
        #expect(offset("KST", on: "2026-01-06") == -9)
        #expect(offset("AKT", on: "2026-01-06") == -9)
        #expect(offset("AKDT", on: "2026-09-06") == -8)
        #expect(offset("AKST", on: "2026-01-06") == -9)
    }

    @Test("unknown abbreviation falls back to nil")
    func unknownAbbreviation() {
        #expect(AirQualityService.timezoneForAirNowAbbreviation("XYZ") == nil)
        #expect(AirQualityService.timezoneForAirNowAbbreviation("") == nil)
    }
}

@Suite("AQI categories")
struct AQICategoryTests {
    @Test("EPA breakpoints")
    func breakpoints() {
        #expect(AirQualityCategory.from(aqi: 0) == .good)
        #expect(AirQualityCategory.from(aqi: 50) == .good)
        #expect(AirQualityCategory.from(aqi: 51) == .moderate)
        #expect(AirQualityCategory.from(aqi: 100) == .moderate)
        #expect(AirQualityCategory.from(aqi: 101) == .unhealthyForSensitive)
        #expect(AirQualityCategory.from(aqi: 150) == .unhealthyForSensitive)
        #expect(AirQualityCategory.from(aqi: 151) == .unhealthy)
        #expect(AirQualityCategory.from(aqi: 202) == .veryUnhealthy)
        #expect(AirQualityCategory.from(aqi: 301) == .hazardous)
    }
}
