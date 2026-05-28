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
    func fetchTransactions(_ options: TransactionFetchOptions) async throws -> TransactionListResponse
    // #R005: Persist one or more classification mutations in a single batch request.
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse]
    // #R040: Manage nys_snw_category definitions from the UI.
    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption
    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption
    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse
    func confirmMatch(matchId: Int) async throws -> MatchReviewActionResponse
    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse
    // #R050: Clear human-reviewed matches by match id or transaction id.
    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse
    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func overrideTransaction(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse
    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse
    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse
    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow]
    func fetchMessage(emailMessageId: String) async throws -> EmailMessage
    // #R062: Search Mailcart messages for Match & Classify candidate discovery.
    // #R064: Support both keyword and structured Mailcart search criteria.
    // #R065: Keep query serialization aligned with shared frontend-backend contract scenarios.
    func searchMessages(criteria: EmailSearchCriteria, limit: Int) async throws -> EmailSearchResponse
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

    func overrideTransaction(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = transactionId
        _ = emailMessageId
        _ = note
        throw APIError.unsupportedOperation("Transaction override")
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

    func searchMessages(criteria: EmailSearchCriteria, limit: Int) async throws -> EmailSearchResponse {
        _ = criteria
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
        self.baseURL = APIClient.validateHTTPSBaseURL(baseURL, source: "APIClient initializer")
        self.writeToken = writeToken
        self.session = session ?? APIClient.makeDefaultSession()
    }

    func fetchCategories() async throws -> [CategoryOption] {
        try await send(path: "/v1/categories")
    }

    // #R001: Paginated transaction fetch with optional include_total/count_only (API R072).
    func fetchTransactions(_ options: TransactionFetchOptions) async throws -> TransactionListResponse {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        comp.queryItems = APIClient.transactionQueryItems(for: options)
        guard let transactionsURL = comp.url else {
            throw APIError.invalidResponse
        }
        return try await send(url: transactionsURL)
    }

    private static func transactionQueryItems(for options: TransactionFetchOptions) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "search", value: options.search),
            URLQueryItem(name: "only_unclassified", value: options.onlyUnclassified ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(options.limit)),
            URLQueryItem(name: "offset", value: String(options.offset)),
            URLQueryItem(name: "include_total", value: options.includeTotal ? "true" : "false"),
            URLQueryItem(name: "count_only", value: options.countOnly ? "true" : "false"),
        ]
        if options.onlyUnmovedMatch {
            items.append(URLQueryItem(name: "only_unmoved_match", value: "true"))
        }
        // #R063: Optional advanced transaction filter query parameters.
        let optionalPairs: [(String, String)] = [
            ("match_state", options.matchState),
            ("start_date", options.startDate),
            ("end_date", options.endDate),
            ("institution_id", options.institutionId),
            ("min_amount", options.minAmount),
            ("max_amount", options.maxAmount),
        ]
        for (name, value) in optionalPairs where !value.isEmpty {
            items.append(URLQueryItem(name: name, value: value))
        }
        return items
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

    func overrideTransaction(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        let body = MatchOverrideRequest(email_message_id: emailMessageId, note: note)
        guard let data = try? JSONEncoder().encode(body) else { throw APIError.encodeFailed }
        let encoded = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? transactionId
        return try await send(path: "/v1/matchy/transactions/\(encoded)/override", method: "PUT", body: data)
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

    // #R062: GET /v1/matchy/messages/search for Match & Classify candidate discovery.
    // #R064: Include structured criteria and limit parameters in Mailcart search requests.
    func searchMessages(criteria: EmailSearchCriteria, limit: Int) async throws -> EmailSearchResponse {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent("/v1/matchy/messages/search"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        let normalized = criteria.normalized()
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if !normalized.subject.isEmpty {
            queryItems.append(URLQueryItem(name: "subject", value: normalized.subject))
        }
        if !normalized.sender.isEmpty {
            queryItems.append(URLQueryItem(name: "sender", value: normalized.sender))
        }
        if !normalized.body.isEmpty {
            queryItems.append(URLQueryItem(name: "body", value: normalized.body))
        }
        if !normalized.receivedStartDate.isEmpty {
            queryItems.append(URLQueryItem(name: "start_date", value: normalized.receivedStartDate))
        }
        if !normalized.receivedEndDate.isEmpty {
            queryItems.append(URLQueryItem(name: "end_date", value: normalized.receivedEndDate))
        }
        comp.queryItems = queryItems
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
            let fallbackMessage = String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)"
            throw APIError.requestFailed(APIClient.errorMessage(from: data) ?? fallbackMessage)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = payload["detail"]
        else {
            return nil
        }
        if let detailText = detail as? String {
            return detailText
        }
        guard let detailArray = detail as? [[String: Any]] else {
            return nil
        }
        if let dateMessage = dateValidationMessage(from: detailArray) {
            return dateMessage
        }
        return detailArray.first?["msg"] as? String
    }

    private static func dateValidationMessage(from detailArray: [[String: Any]]) -> String? {
        for detail in detailArray {
            guard let loc = detail["loc"] as? [Any], loc.count >= 2 else {
                continue
            }
            guard (loc[0] as? String) == "query" else {
                continue
            }
            guard let fieldName = loc[1] as? String else {
                continue
            }
            if fieldName == "start_date" || fieldName == "end_date" {
                return "Expected date format: YYYY-MM-DD for \(fieldName)"
            }
        }
        return nil
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
        let defaultURL = "https://127.0.0.1:8787"
        let baseURLString = env["TELLER_CLASSIFIER_API_URL"] ?? defaultURL
        guard let parsedURL = URL(string: baseURLString) else {
            fatalError("TELLER_CLASSIFIER_API_URL must be a valid absolute URL.")
        }
        return validateHTTPSBaseURL(parsedURL, source: "TELLER_CLASSIFIER_API_URL")
    }

    private static func validateHTTPSBaseURL(_ url: URL, source: String) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            fatalError("\(source) must use https:// (received: \(url.absoluteString)).")
        }
        return url
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
