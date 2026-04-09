import SwiftUI
import WeatherKit

struct WeatherAttributionView: View {
    let attribution: WeatherAttribution?

    var body: some View {
        if let attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(url: attribution.combinedMarkDarkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 18)
                    default:
                        fallbackText
                    }
                }
            }
        } else {
            fallbackText
        }
    }

    private var fallbackText: some View {
        Text("\(Image(systemName: "apple.logo")) Weather")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
    }
}
