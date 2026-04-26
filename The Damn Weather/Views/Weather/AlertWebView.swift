import SwiftUI
import SafariServices

/// Embeds an `SFSafariViewController` for a given URL inside a SwiftUI view.
/// Used as a fallback in `AlertDetailsSheet` when the alert wasn't issued
/// by NWS (or NWS is unreachable) — the WeatherKit `detailsURL` then renders
/// the issuing authority's webpage directly inside our sheet, so the user
/// never has to leave the app to read the full alert.
struct AlertWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
