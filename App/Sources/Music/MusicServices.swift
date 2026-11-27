import AVFoundation
import Foundation
import SiteKit
import WebKit

/// Loads the music page in an off-screen browser and reads its blocks in the order visitors see
/// them. Squarespace 7.1 places blocks on a grid, so the page source order isn't reliable.
@MainActor
final class MusicPageReader: NSObject, WKNavigationDelegate {
    enum ReaderError: LocalizedError {
        case timedOut
        case unreadable

        var errorDescription: String? {
            switch self {
            case .timedOut: return "The music page took too long to load."
            case .unreadable: return "The music page couldn't be read."
            }
        }
    }

    static let script = """
    (() => {
      const items = [];
      const add = (el, item) => {
        const r = el.getBoundingClientRect();
        item.y = r.top + window.scrollY;
        item.x = r.left + window.scrollX;
        items.push(item);
      };
      document.querySelectorAll('[data-sqsp-text-block-content], .sqs-html-content').forEach(el =>
        add(el, { kind: 'text', text: el.innerText || '' }));
      document.querySelectorAll('.sqs-audio-embed').forEach(el => add(el, {
        kind: 'audio',
        text: el.getAttribute('data-title') || '',
        subtitle: el.getAttribute('data-author'),
        assetURL: el.getAttribute('data-asset-url'),
        durationMilliseconds: parseInt(el.getAttribute('data-length-in-milli-seconds') || '0', 10) || null,
        designStyle: el.getAttribute('data-design-style')
      }));
      return JSON.stringify(items);
    })()
    """

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    func read(_ url: URL) async throws -> [MusicPageItem] {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 1000), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        defer {
            webView?.navigationDelegate = nil
            webView = nil
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
                self?.finish(ReaderError.timedOut)
            }
        }
        // Give Squarespace's scripts a moment to lay out the blocks.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let result = try await view.evaluateJavaScript(Self.script)
        guard let json = result as? String, let data = json.data(using: .utf8) else { throw ReaderError.unreadable }
        return try JSONDecoder().decode([MusicPageItem].self, from: data)
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }
}

/// Gets audio files ready for Squarespace's audio block: MP3 or M4A, 160 MB or less.
enum AudioPreparer {
    enum PrepareError: LocalizedError {
        case cannotConvert(String)
        case conversionFailed(String, String)
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .cannotConvert(let title):
                return "\(title) couldn't be converted to M4A."
            case .conversionFailed(let title, let detail):
                return "Converting \(title) failed: \(detail)"
            case .tooLarge(let title):
                return "\(title) is still over 160 MB after converting, which is Squarespace's limit for audio."
            }
        }
    }

    static func duration(of url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? Int(seconds.rounded()) : nil
    }

    static func prepare(_ piece: LocalPiece, into folder: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(UploadPlan.fileName(for: piece))
        try? fileManager.removeItem(at: destination)

        switch UploadPlan.plan(for: piece) {
        case .copy:
            try fileManager.copyItem(at: piece.url, to: destination)
        case .convertToM4A:
            let asset = AVURLAsset(url: piece.url)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw PrepareError.cannotConvert(piece.title)
            }
            session.outputURL = destination
            session.outputFileType = .m4a
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
            guard session.status == .completed else {
                throw PrepareError.conversionFailed(piece.title, session.error?.localizedDescription ?? "unknown error")
            }
        }

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        if Int64(size) > UploadPlan.maximumBytes {
            throw PrepareError.tooLarge(piece.title)
        }
        return destination
    }
}

enum DurationText {
    static func format(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let minutes = seconds / 60
        let rest = seconds % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}
