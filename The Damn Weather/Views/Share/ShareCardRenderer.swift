import SwiftUI
import UIKit
import WeatherKit

/// @MainActor wrapper around ImageRenderer for ShareCardView.
/// Output: 1080x1920 px UIImage at scale 3.0.
@MainActor
enum ShareCardRenderer {
    static let pointSize = CGSize(width: 360, height: 640)

    static func render(_ card: ShareCardView) -> UIImage? {
        let sized = card
            .frame(width: pointSize.width, height: pointSize.height)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(.large)

        let renderer = ImageRenderer(content: sized)
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// "Jul 5 12:10 PM" label for the card, in the location's timezone.
    /// Shared by every surface that renders the card so they can't drift.
    static func dateTimeLabel(timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMd h:mm a")
        return f.string(from: Date())
    }

    /// Pre-resolves the Apple Weather attribution mark to a UIImage.
    /// AsyncImage does not render inside ImageRenderer, so the URL must be
    /// fetched upstream and passed in as a static image.
    static func resolveAttributionMark(from attribution: WeatherAttribution?) async -> UIImage? {
        guard let attribution else { return nil }
        let url = attribution.combinedMarkDarkURL
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
