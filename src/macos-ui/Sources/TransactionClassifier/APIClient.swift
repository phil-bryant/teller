import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)
    case encodeFailed
    case missingWriteToken
    case unsupportedOperation(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .requestFailed(let msg): return msg
        case .encodeFailed: return "Failed to encode request payload."
        case .missingWriteToken: return "Missing classifier write token from 1psa item TELLER_CLASSIFIER_WRITE_TOKEN."
        case .unsupportedOperation(let operation): return "\(operation) is not supported by this API client."
        }
    }
}

protocol ClassificationAPI: Sendable {
    // #R001: Fetch categories and transaction listings from the local classifier API.
    func fetchCategories() async throws -> [CategoryOption]
    func fetchTransactions(search: String, onlyUnclassified: Bool, matchState: String, onlyUnmovedMatch: Bool, limit: Int, offset: Int, includeTotal: Bool, countOnly: Bool) async throws -> TransactionListResponse
    // #R005: Persist one or more classification mutations in a single batch request.
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse]
    // #R040: Manage nys_snw_category definitions from the UI.
    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption
    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption
    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse
    func fetchMatchReview(state: String, onlyUnmoved: Bool, limit: Int, offset: Int) async throws -> MatchReviewListResponse
    func confirmMatch(matchId: Int) async throws -> MatchReviewActionResponse
    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse
    // #R050: Clear human-reviewed matches by match id or transaction id.
    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse
    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse
    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse
    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow]
    func fetchMessage(emailMessageId: String) async throws -> EmailMessage
    // #R062: Search Mailcart messages for Match & Classify candidate discovery.
    func searchMessages(query: String, limit: Int) async throws -> EmailSearchResponse
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

    func fetchMatchReview(state: String, onlyUnmoved: Bool, limit: Int, offset: Int) async throws -> MatchReviewListResponse {
        _ = state
        _ = onlyUnmoved
        _ = limit
        _ = offset
        throw APIError.unsupportedOperation("Match review listing")
    }

    func confirmMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        _ = matchId
        throw APIError.unsupportedOperation("Match confirmation")
    }

    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = matchId
        _ = emailMessageId
        _ = note
        throw APIError.unsupportedOperation("Match override")
    }

    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse {
        _ = matchId
        throw APIError.unsupportedOperation("Match no-email action")
    }

    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        _ = matchId
        throw APIError.unsupportedOperation("Match clear action")
    }

    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = transactionId
        _ = emailMessageId
        _ = note
        throw APIError.unsupportedOperation("Transaction candidate confirmation")
    }

    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = transactionId
        _ = emailMessageId
        _ = note
        throw APIError.unsupportedOperation("Transaction candidate override")
    }

    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse {
        _ = transactionId
        throw APIError.unsupportedOperation("Transaction no-email action")
    }

    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse {
        _ = transactionId
        throw APIError.unsupportedOperation("Transaction match clear action")
    }

    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow] {
        _ = transactionId
        throw APIError.unsupportedOperation("Match candidate listing")
    }

    func fetchMessage(emailMessageId: String) async throws -> EmailMessage {
        _ = emailMessageId
        throw APIError.unsupportedOperation("Email message fetch")
    }

    func searchMessages(query: String, limit: Int) async throws -> EmailSearchResponse {
        _ = query
        _ = limit
        throw APIError.unsupportedOperation("Mailcart search")
    }
}

actor APIClient: ClassificationAPI {
    private let session: URLSession
    private let baseURL: URL
    private let writeToken: String
    init(baseURL: URL = APIClient.defaultBaseURL(),
         writeToken: String = APIClient.defaultWriteToken(),
         session: URLSession? = nil) {
        self.baseURL = baseURL
        self.writeToken = writeToken
        self.session = session ?? APIClient.makeDefaultSession()
    }

    func fetchCategories() async throws -> [CategoryOption] {
        try await send(path: "/v1/categories")
    }

    // #R001: Paginated transaction fetch with optional include_total/count_only (API R072).
    func fetchTransactions(search: String, onlyUnclassified: Bool, matchState: String, onlyUnmovedMatch: Bool, limit: Int, offset: Int, includeTotal: Bool = true, countOnly: Bool = false) async throws -> TransactionListResponse {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "only_unclassified", value: onlyUnclassified ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "include_total", value: includeTotal ? "true" : "false"),
            URLQueryItem(name: "count_only", value: countOnly ? "true" : "false"),
        ]
        if !matchState.isEmpty {
            queryItems.append(URLQueryItem(name: "match_state", value: matchState))
        }
        if onlyUnmovedMatch {
            queryItems.append(URLQueryItem(name: "only_unmoved_match", value: "true"))
        }
        comp.queryItems = queryItems
        guard let transactionsURL = comp.url else {
            throw APIError.invalidResponse
        }
        return try await send(url: transactionsURL)
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

    func fetchMatchReview(state: String, onlyUnmoved: Bool, limit: Int, offset: Int) async throws -> MatchReviewListResponse {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/matchy/review"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        comp.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "only_unmoved", value: onlyUnmoved ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = comp.url else { throw APIError.invalidResponse }
        return try await send(url: url)
    }

    func confirmMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        try await send(path: "/v1/matchy/matches/\(matchId)/confirm", method: "PUT")
    }

    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        let body = MatchOverrideRequest(email_message_id: emailMessageId, note: note)
        guard let data = try? JSONEncoder().encode(body) else { throw APIError.encodeFailed }
        return try await send(path: "/v1/matchy/matches/\(matchId)/override", method: "PUT", body: data)
    }

    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse {
        try await send(path: "/v1/matchy/matches/\(matchId)/no-email", method: "PUT")
    }

    // #R050: PUT /v1/matchy/matches/{match_id}/clear to deactivate a human-reviewed match.
    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        try await send(path: "/v1/matchy/matches/\(matchId)/clear", method: "PUT")
    }

    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        let body = MatchOverrideRequest(email_message_id: emailMessageId, note: note)
        guard let data = try? JSONEncoder().encode(body) else { throw APIError.encodeFailed }
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/confirm-candidate", method: "PUT", body: data)
    }

    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        let body = MatchOverrideRequest(email_message_id: emailMessageId, note: note)
        guard let data = try? JSONEncoder().encode(body) else { throw APIError.encodeFailed }
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/override-candidate", method: "PUT", body: data)
    }

    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse {
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/no-email", method: "PUT")
    }

    // #R050: PUT /v1/matchy/transactions/{transaction_id}/clear when no match row id is available.
    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse {
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/clear", method: "PUT")
    }

    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow] {
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/candidates")
    }

    func fetchMessage(emailMessageId: String) async throws -> EmailMessage {
        let encoded = emailMessageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emailMessageId
        return try await send(path: "/v1/matchy/messages/\(encoded)")
    }

    // #R062: GET /v1/matchy/messages/search with query and limit parameters.
    func searchMessages(query: String, limit: Int) async throws -> EmailSearchResponse {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/matchy/messages/search"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        comp.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comp.url else { throw APIError.invalidResponse }
        return try await send(url: url)
    }

    private func send<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try await send(url: baseURL.appendingPathComponent(path), method: method, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        // #R010: Apply shared JSON request/response handling and raise API-aware errors on non-2xx status codes.
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if writeToken.isEmpty {
            throw APIError.missingWriteToken
        }
        req.setValue(writeToken, forHTTPHeaderField: "X-Teller-Write-Token")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.requestFailed(String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // #R020: URLSession delegate pins loopback HTTPS to the local classifier cert.
    private static let tlsSessionDelegate = LocalClassifierTLSSessionDelegate()
    private static let tlsSessionDelegateQueue = OperationQueue()

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        if let proxyURLString = ProcessInfo.processInfo.environment["TELLER_CLASSIFIER_HTTP_PROXY"],
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
        return URLSession(
            configuration: config,
            delegate: tlsSessionDelegate,
            delegateQueue: tlsSessionDelegateQueue
        )
    }

    private static func defaultBaseURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        let allowInsecureHTTP = (env["TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP"] ?? "").lowercased() == "true"
        let defaultURL = allowInsecureHTTP ? "http://127.0.0.1:8787" : "https://127.0.0.1:8787"
        let baseURLString = env["TELLER_CLASSIFIER_API_URL"] ?? defaultURL
        if let parsedURL = URL(string: baseURLString) {
            return parsedURL
        }
        return URL(fileURLWithPath: "/")
    }

    private static func defaultWriteToken() -> String {
        // #R045: Resolve write token exclusively from 1psa item.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["1psa", "-p", "TELLER_CLASSIFIER_WRITE_TOKEN"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return ""
            }
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}
