import SwiftUI
import WebKit

struct FlowView: View {
    let onClose: () -> Void

    var body: some View {
        FlowWebView(onClose: onClose)
            .background(Color.black)
            .ignoresSafeArea()
            .statusBarHidden(true)
    }
}

private struct FlowWebView: UIViewRepresentable {
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.bridgeName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.setURLSchemeHandler(
            context.coordinator.resourceSchemeHandler,
            forURLScheme: FlowResourceSchemeHandler.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.loadFlow(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.bridgeName)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let bridgeName = "flowBridge"

        private let onClose: () -> Void
        let resourceSchemeHandler = FlowResourceSchemeHandler()

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func loadFlow(in webView: WKWebView) {
            guard Bundle.main.url(forResource: "flow", withExtension: "html") != nil,
                  let pageURL = URL(string: "\(FlowResourceSchemeHandler.scheme)://app/flow.html") else {
                webView.loadHTMLString(Self.missingResourcePage, baseURL: nil)
                return
            }
            webView.load(URLRequest(url: pageURL))
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.bridgeName,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "close":
                onClose()
            case "haptic":
                let value = payload["value"] as? String
                value == "success" ? Haptics.success() : Haptics.selection()
            default:
                break
            }
        }

        private static let missingResourcePage = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <body style="margin:0;background:#050706;color:white;font:17px -apple-system;display:grid;place-items:center;min-height:100vh;text-align:center">
          <main><h1>Flow is unavailable</h1><p style="color:#9b9fa5">Please reinstall this version of Memory Lanes.</p></main>
        </body>
        """
    }
}

private final class FlowResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "memorylanes-flow"

    private static let resources = Set([
        "flow.html",
        "flow.css",
        "flow.js",
        "flow-engine.js",
        "flow-storage.js",
        "flow-audio.js",
        "flow-renderer.js",
        "flow-playcanvas-renderer.js",
        "playcanvas.min.mjs",
        "flow-assets.js",
        "flow-effects.js",
    ])

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.scheme == Self.scheme,
              requestURL.host == "app" else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        let resourceName = requestURL.lastPathComponent
        guard Self.resources.contains(resourceName) else {
            fail(urlSchemeTask, code: .fileDoesNotExist)
            return
        }

        let resource = resourceName as NSString
        let fileName = resource.deletingPathExtension
        let fileExtension = resource.pathExtension
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            fail(urlSchemeTask, code: .fileDoesNotExist)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(for: fileExtension),
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension {
        case "html": "text/html"
        case "css": "text/css"
        case "js", "mjs": "text/javascript"
        default: "application/octet-stream"
        }
    }

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}

#Preview {
    FlowView(onClose: {})
}
