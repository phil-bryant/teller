import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)
    case encodeFailed
    case unsupportedOperation(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .requestFailed(let msg): return msg
        case .encodeFailed: return "Failed to encode request payload."
        case .unsupportedOperation(let operation): return "\(operation) is not supported by this API client."
        }
    }
}

protocol ClassificationAPI: Sendable {
    // #R001: Fetch categories and transaction listings from the local classifier API.
    func fetchCategories() async throws -> [CategoryOption]
    func fetchTransactions(search: String, onlyUnclassified: Bool, limit: Int, offset: Int) async throws -> TransactionListResponse
    // #R005: Persist one or more classification mutations in a single batch request.
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse]
    // #R040: Manage nys_snw_category definitions from the UI.
    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption
    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption
    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse
}

extension ClassificationAPI {
    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption {
        _ = category
        throw APIError.unsupportedOperation("Category creation")
    }

    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption {
        _ = id
        _ = category
        throw APIError.unsupportedOperation("Category update")
    }

    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse {
        _ = id
        throw APIError.unsupportedOperation("Category deletion")
    }
}

actor APIClient: ClassificationAPI {
    private let session: URLSession
    private let baseURL: URL
    init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["TELLER_CLASSIFIER_API_URL"] ?? "http://127.0.0.1:8787")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchCategories() async throws -> [CategoryOption] {
        try await send(path: "/v1/categories")
    }

    func fetchTransactions(search: String, onlyUnclassified: Bool, limit: Int, offset: Int) async throws -> TransactionListResponse {
        var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "only_unclassified", value: onlyUnclassified ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        return try await send(url: comp.url!)
    }

    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        let body = ClassificationBatchRequest(updates: updates)
        guard let data = try? JSONEncoder().encode(body) else { throw APIError.encodeFailed }
        return try await send(path: "/v1/transactions/classifications", method: "POST", body: data)
    }

    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption {
        guard let data = try? JSONEncoder().encode(category) else { throw APIError.encodeFailed }
        return try await send(path: "/v1/categories", method: "POST", body: data)
    }

    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption {
        guard let data = try? JSONEncoder().encode(category) else { throw APIError.encodeFailed }
        return try await send(path: "/v1/categories/\(id)", method: "PUT", body: data)
    }

    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse {
        try await send(path: "/v1/categories/\(id)", method: "DELETE")
    }

    private func send<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try await send(url: baseURL.appendingPathComponent(path), method: method, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        // #R010: Apply shared JSON request/response handling and raise API-aware errors on non-2xx status codes.
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.requestFailed(String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
