import SwiftUI
import WeatherShared

/// Renders the app icon design for export.
/// Use Xcode Previews to screenshot at 1024x1024.
struct AppIconGenerator: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            // Background — dark navy matching app
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "1a1d2e"),
                            Color(hex: "0f1117")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Weather icon — SF Symbol cloud.sun.fill
            Image(systemName: "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: size * 0.42))
                .offset(y: -size * 0.08)

            // Red "DAMN" banner — rotated, bottom-right
            Text("DAMN")
                .font(.system(size: size * 0.1, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.06)
                .padding(.vertical, size * 0.025)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.025)
                        .fill(Color(hex: "e63946"))
                        .shadow(color: .black.opacity(0.4), radius: size * 0.02, y: size * 0.01)
                )
                .rotationEffect(.degrees(-15))
                .offset(x: size * 0.1, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

#Preview("App Icon 1024") {
    AppIconGenerator(size: 1024)
        .frame(width: 1024, height: 1024)
}

#Preview("App Icon Preview") {
    AppIconGenerator(size: 200)
        .frame(width: 200, height: 200)
}
