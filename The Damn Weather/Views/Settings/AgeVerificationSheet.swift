import SwiftUI
import WeatherShared

/// Age verification modal for explicit phrase mode.
/// Port of the website's age modal from index.html lines 211-220.
struct AgeVerificationSheet: View {
    let viewModel: SettingsViewModel
    let onConfirmed: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignTokens.spaceLG) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Heads up!")
                .font(.title2.bold())

            Text("You're about to enable some **colorful language**. The phrases will contain explicit profanity.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.spaceXL)

            VStack(spacing: 12) {
                Button {
                    viewModel.confirmAge()
                    onConfirmed()
                    dismiss()
                } label: {
                    Text("Enable explicit mode")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                }

                Button {
                    viewModel.cancelAge()
                    dismiss()
                } label: {
                    Text("Keep it clean")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                }
            }
            .padding(.horizontal, DesignTokens.spaceXL)

            Spacer()
        }
        .interactiveDismissDisabled()
    }
}
