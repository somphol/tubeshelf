import SwiftUI
import WebKit
import TubeShelfCore

/// Inline YouTube playback. Uses the privacy-preserving nocookie embed; if the
/// video forbids embedding, the deck falls back to opening it in the browser.
struct InlinePlayer: NSViewRepresentable {
    let videoID: String
    var onFailure: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .black
        webView.load(URLRequest(url: YouTubeURL.embedURL(for: videoID, autoplay: true)))
        context.coordinator.loadedID = videoID
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        webView.load(URLRequest(url: YouTubeURL.embedURL(for: videoID, autoplay: true)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedID: String?
        private let onFailure: () -> Void

        init(onFailure: @escaping () -> Void) {
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
    }
}
