import Foundation

protocol ConnectAPI: Sendable {
    func fetchStatus() async throws -> ConnectStatusResponse
    func fetchContexts() async throws -> [ConnectContext]
    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse
    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse
}

actor ConnectAPIClient: ConnectAPI {
    private let session: URLSession
    private let baseURL: URL

    init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["TELLER_CONNECT_API_URL"] ?? "http://127.0.0.1:8080")!,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.session = session ?? ConnectAPIClient.makeDefaultSession()
    }

    func fetchStatus() async throws -> ConnectStatusResponse {
        try await send(path: "/api/status")
    }

    func fetchContexts() async throws -> [ConnectContext] {
        let response: ConnectContextsResponse = try await send(path: "/api/contexts")
        return response.contexts
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        guard let body = try? JSONEncoder().encode(request) else {
            throw APIError.encodeFailed
        }
        return try await send(path: "/api/store-token", method: "POST", body: body)
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        guard let body = try? JSONEncoder().encode(ConnectDeleteContextRequest(targetKey: targetKey)) else {
            throw APIError.encodeFailed
        }
        return try await send(path: "/api/delete-context", method: "POST", body: body)
    }

    private func send<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try await send(url: baseURL.appendingPathComponent(path), method: method, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.requestFailed(String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        if let proxyURLString = ProcessInfo.processInfo.environment["TELLER_CONNECT_HTTP_PROXY"],
           let proxyURL = URL(string: proxyURLString),
           let host = proxyURL.host,
           let port = proxyURL.port {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        }
        return URLSession(configuration: config)
    }
}
