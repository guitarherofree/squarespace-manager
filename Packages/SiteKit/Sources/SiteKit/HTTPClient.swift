import Foundation

/// The result of one GET request.
public struct HTTPResponse: Sendable {
    /// The final URL after redirects.
    public let url: URL
    public let status: Int
    public let data: Data
    public let contentType: String?

    public init(url: URL, status: Int, data: Data, contentType: String? = nil) {
        self.url = url
        self.status = status
        self.data = data
        self.contentType = contentType
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
    public var text: String { String(decoding: data, as: UTF8.self) }
}

/// Fetches pages. The app uses `URLSessionHTTPClient`; tests use a stub.
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    public var userAgent: String
    public var timeout: TimeInterval

    public init(userAgent: String, timeout: TimeInterval = 30) {
        self.userAgent = userAgent
        self.timeout = timeout
    }

    public func get(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return HTTPResponse(
            url: http?.url ?? url,
            status: http?.statusCode ?? 0,
            data: data,
            contentType: http?.value(forHTTPHeaderField: "Content-Type")
        )
    }
}
