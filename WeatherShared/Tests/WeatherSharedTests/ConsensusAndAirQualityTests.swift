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

    /// Verbatim shape of a live AirNow response (Seattle, 2026-07-04 —
    /// the July 4th fireworks PM2.5 spike).
    private let liveCSV = """
    "DateObserved","HourObserved","LocalTimeZone","ReportingArea","StateCode","Latitude","Longitude","ParameterName","AQI","CategoryNumber","CategoryName"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","O3","18","1","Good"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","PM2.5","202","5","Very Unhealthy"
    "2026-07-04","21","PST","Seattle-Bellevue-Kent Valley","WA","47.562","-122.3405","PM10","95","2","Moderate"
    """

    @Test("parses live response shape")
    func parsesLiveShape() {
        let rows = AirNowClient.parseCSV(liveCSV)
        #expect(rows.count == 3)
        #expect(rows[0].parameterName == "O3")
        #expect(rows[0].aqi == 18)
        #expect(rows[1].parameterName == "PM2.5")
        #expect(rows[1].aqi == 202)
        #expect(rows[1].categoryNumber == 5)
        #expect(rows[0].reportingArea == "Seattle-Bellevue-Kent Valley")
        #expect(rows[0].localTimeZone == "PST")
        #expect(rows[0].hourObserved == 21)
    }

    @Test("header-only response is empty")
    func headerOnly() {
        let header = "\"DateObserved\",\"HourObserved\",\"LocalTimeZone\",\"ReportingArea\",\"StateCode\",\"Latitude\",\"Longitude\",\"ParameterName\",\"AQI\",\"CategoryNumber\",\"CategoryName\""
        #expect(AirNowClient.parseCSV(header).isEmpty)
        #expect(AirNowClient.parseCSV("").isEmpty)
    }

    @Test("malformed rows are skipped, not fatal")
    func malformedRowsSkipped() {
        let mixed = liveCSV + "\n\"garbage\",\"row\"\n\"2026-07-04\",\"NaN\",\"PST\",\"X\",\"WA\",\"0\",\"0\",\"O3\",\"not-a-number\",\"1\",\"Good\""
        #expect(AirNowClient.parseCSV(mixed).count == 3)
    }

    @Test("CRLF line endings parse identically")
    func crlfHandled() {
        let crlf = liveCSV.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(AirNowClient.parseCSV(crlf).count == 3)
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
