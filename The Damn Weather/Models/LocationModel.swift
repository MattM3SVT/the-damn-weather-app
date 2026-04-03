import Foundation
import SwiftData
import CoreLocation

@Model
final class SavedLocation {
    var name: String
    var state: String
    var country: String
    var latitude: Double
    var longitude: Double
    var isCurrent: Bool
    var isPrimary: Bool
    var sortOrder: Int
    var lastUpdated: Date

    init(
        name: String,
        state: String = "",
        country: String = "",
        latitude: Double,
        longitude: Double,
        isCurrent: Bool = false,
        isPrimary: Bool = false,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.state = state
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrent = isCurrent
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.lastUpdated = Date()
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        if !state.isEmpty {
            return "\(name), \(state)"
        }
        if !country.isEmpty {
            return "\(name), \(country)"
        }
        return name
    }
}
