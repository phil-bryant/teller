import Foundation
import Observation

// #R001: Shared observable state supports loadAll-driven category/transaction hydration.
// #R005: Shared selection and category state supports redundant-save avoidance logic.
// #R010: Shared row/save-state storage supports optimistic apply with rollback.
// #R015: Shared selection/undo state supports keyboard triage progression and undo.
// #R020: Shared transaction list state supports paged append without duplicates.
// #R025: First-load filter defaults to unclassified transactions.
// #R030: Shared category editor selection supports bulk delete workflows.
// #R035: Shared selected-match state supports clear-to-unmatched actions.
// #R040: Shared Mailcart query/result state supports debounced search UX.
// #R095: Shared structured Mailcart query/result state supports debounced search UX.
// #R090: Shared advanced transaction filter state supports date/institution/amount filtering.
// #R075: Shared total/status state supports background count-only refresh.
// #R080: Shared loading/status state supports optional transaction-load profiling.
// #R085: Keep this file as the observable surface while behavior lives in focused extensions.
// #R100: Shared match action state supports stale snapshot reload-and-retry behavior.

struct UndoAction { let prior: [String: TransactionCategory?] }
struct CategoryDraft: Equatable {
    var level_1 = ""
    var level_1_name = ""
    var level_2 = ""
    var level_2_name = ""
    var level_3 = ""
    var level_4 = ""
    var categorization = ""
    var applicability = ""

    init() {}

    init(category: CategoryOption) {
        level_1 = category.level_1 ?? ""
        level_1_name = category.level_1_name ?? ""
        level_2 = category.level_2 ?? ""
        level_2_name = category.level_2_name ?? ""
        level_3 = category.level_3 ?? ""
        level_4 = category.level_4 ?? ""
        categorization = category.categorization ?? ""
        applicability = category.applicability ?? ""
    }

    var payload: CategoryMutationRequest {
        CategoryMutationRequest(
            level_1: normalize(level_1),
            level_1_name: normalize(level_1_name),
            level_2: normalize(level_2),
            level_2_name: normalize(level_2_name),
            level_3: normalize(level_3),
            level_4: normalize(level_4),
            categorization: normalize(categorization),
            applicability: normalize(applicability)
        )
    }

    private func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
@Observable
final class ClassificationViewModel {
    // MARK: - Shared data and list state

    // Internal for concern-specific extensions.
    let pageSize = 150
    var categories: [CategoryOption] = []
    var allCategories: [CategoryOption] = []
    var transactions: [TransactionRow] = []
    var totalTransactions = 0
    var selection: Set<String> = []
    var searchText = ""
    var transactionStartDate = ""
    var transactionEndDate = ""
    var transactionInstitutionId = ""
    var transactionMinAmount = ""
    var transactionMaxAmount = ""
    var onlyUnclassified = true // #R025: Default to filtering unclassified transactions.
    var focusedSearch = false
    var selectedCategoryId: Int?
    var rowState: [String: SaveState] = [:]
    var busy = false
    var errorText = ""
    var undoStack: [UndoAction] = []
    var statusText = "Ready"

    // MARK: - Category editor state

    var categoryEditorSelection: Set<Int> = []
    var categoryEditorDraft = CategoryDraft()
    var categoryEditorBusy = false
    var categoryEditorStatusText = "Select a category to edit, or create a new one."
    var categoryEditorErrorText = ""

    // MARK: - Match review and candidate/email pane state

    var matchReviewStateFilter = ""
    var matchReviewOnlyUnmoved = false
    var matchOverrideEmailMessageId = ""
    var matchReviewStatusText = "Ready"
    var matchReviewErrorText = ""
    var candidates: [MatchCandidateRow] = []
    var candidatesBusy = false
    var candidatesErrorText = ""
    var selectedCandidateId: String?
    var selectedEmail: EmailMessage?
    var emailBusy = false
    var emailErrorText = ""
    var mailcartSearchSubject = ""
    var mailcartSearchSender = ""
    var mailcartSearchBody = ""
    var mailcartSearchStartDate = ""
    var mailcartSearchEndDate = ""
    var mailcartSearchResults: [EmailSearchHit] = []
    var mailcartSearchBusy = false
    var mailcartSearchErrorText = ""
    var matchOverrideNote = ""

    // MARK: - Dependencies and internal coordination state

    // Internal for concern-specific extensions.
    let api: any ClassificationAPI
    var suppressAutoApply = false
    var pendingScrollSelectionTransactionId: String?
    var lastLoadedCandidatesTransactionId: String?
    var mailcartSearchTaskToken: UUID?
    /// Token issued for each in-flight candidate fetch. Late-arriving responses for a transaction
    /// the user has already moved away from are dropped so the candidates pane never shows stale
    /// data from a previously-selected row (the "HomeAgain showing DoorDash candidates" bug).
    var candidatesLoadToken: UUID?
    /// Token for the in-flight per-candidate email fetch (same rationale as `candidatesLoadToken`).
    var emailLoadToken: UUID?
    static let mailcartSearchDebounceNanoseconds: UInt64 = 250_000_000

    init(api: any ClassificationAPI = APIClient()) { self.api = api }

    // #R090: Bundle current list query state for transaction fetches.
    func transactionFetchOptions(
        limit: Int,
        offset: Int,
        includeTotal: Bool,
        countOnly: Bool
    ) -> TransactionFetchOptions {
        TransactionFetchOptions(
            search: searchText,
            onlyUnclassified: onlyUnclassified,
            matchState: matchReviewStateFilter,
            onlyUnmovedMatch: matchReviewOnlyUnmoved,
            startDate: transactionStartDate,
            endDate: transactionEndDate,
            institutionId: transactionInstitutionId,
            minAmount: transactionMinAmount,
            maxAmount: transactionMaxAmount,
            limit: limit,
            offset: offset,
            includeTotal: includeTotal,
            countOnly: countOnly
        )
    }

    // MARK: - Derived view state

    var selectedRows: [TransactionRow] { transactions.filter { selection.contains($0.transaction_id) } }
    var selectionHasMixedCategories: Bool {
        let rows = selectedRows
        guard let first = rows.first?.classification?.nys_snw_category_id else { return rows.contains { $0.classification != nil } }
        return rows.contains { $0.classification?.nys_snw_category_id != first }
    }
    var canLoadMore: Bool { transactions.count < totalTransactions }
    var transactionInstitutionOptions: [String] {
        Array(Set(transactions.compactMap(\.institution_id))).sorted()
    }
    var mailcartSearchCriteria: EmailSearchCriteria {
        EmailSearchCriteria(
            subject: mailcartSearchSubject,
            sender: mailcartSearchSender,
            body: mailcartSearchBody,
            receivedStartDate: mailcartSearchStartDate,
            receivedEndDate: mailcartSearchEndDate
        )
    }
    var categoryEditorPrimarySelectionId: Int? {
        guard categoryEditorSelection.count == 1 else { return nil }
        return categoryEditorSelection.first
    }

    /// The single transaction the user is currently viewing (the "primary" of any multi-selection).
    /// Drives the candidates pane, email pane, classification picker, and match actions.
    var primaryTransaction: TransactionRow? {
        if let firstId = selection.first { return transactions.first { $0.transaction_id == firstId } }
        return nil
    }

    var selectedTransactionMatch: TransactionMatchInfo? { primaryTransaction?.match }

    /// The unified pipeline keys off transactions, but the actions that update a match still
    /// need a match_id, so expose it here for the existing call sites.
    var selectedMatchId: Int? { selectedTransactionMatch?.match_id }
    var selectedMatchEmailMessageId: String? { selectedTransactionMatch?.email_message_id }

    /// How many active match rows exist for this transaction (1 normally; >1 when matchy linked
    /// multiple emails to one charge per the AI prompt's "1 transaction may map to multiple emails").
    func matchedEmailCount(for transactionId: String) -> Int {
        transactions.first { $0.transaction_id == transactionId }?.match?.match_count ?? 0
    }

    /// All `email_message_id`s currently active for the primary transaction. Currently we only
    /// know the representative email + count; full set is the candidate-set "AI pick" rows from
    /// `candidates` (server marks them via `is_selected_by_ai`).
    var activeEmailIdsForSelectedTransaction: Set<String> {
        var result = Set<String>()
        if let emailId = selectedMatchEmailMessageId, !emailId.isEmpty {
            result.insert(emailId)
        }
        for candidate in candidates where candidate.is_selected_by_ai {
            result.insert(candidate.email_message_id)
        }
        return result
    }

    var overrideTargetEmailMessageId: String? {
        let trimmedTyped = matchOverrideEmailMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTyped.isEmpty { return trimmedTyped }
        return selectedCandidateId
    }

    var isOverrideTargetInLatestCandidateSet: Bool {
        guard let target = overrideTargetEmailMessageId else { return false }
        return candidates.contains(where: { $0.email_message_id == target })
    }

    var isOverrideTargetSearchHitOnly: Bool {
        guard let target = overrideTargetEmailMessageId else { return false }
        let inCandidates = candidates.contains(where: { $0.email_message_id == target })
        let inSearchHits = mailcartSearchResults.contains(where: { $0.email_message_id == target })
        return inSearchHits && !inCandidates
    }

    var canOverrideSelectedMatch: Bool {
        guard let candidateId = overrideTargetEmailMessageId else { return false }
        if selectedMatchId != nil {
            return !activeEmailIdsForSelectedTransaction.contains(candidateId)
        }
        return primaryTransaction != nil
    }

    var canConfirmSelectedMatch: Bool {
        if selectedMatchId != nil { return true }
        return primaryTransaction != nil && overrideTargetEmailMessageId != nil && !isOverrideTargetSearchHitOnly
    }

    var canMarkSelectedMatchNoEmail: Bool {
        primaryTransaction != nil
    }

    var canClearSelectedMatch: Bool {
        selectedMatchId != nil
    }

    // Shared helper used across concern extensions.
    func syncPickerToSelection() {
        let rows = selectedRows
        let current = rows.first?.classification?.nys_snw_category_id
        let normalized = rows.allSatisfy { $0.classification?.nys_snw_category_id == current } ? current : nil
        suppressAutoApply = true
        selectedCategoryId = normalized
        suppressAutoApply = false
    }

    // Shared helper used across concern extensions.
    func setCategories(_ fetched: [CategoryOption]) {
        let sortedById = fetched.sorted { $0.nys_snw_category_id < $1.nys_snw_category_id }
        allCategories = sortedById
        categories = sortedById.filter { (($0.applicability ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "N/A") }
    }
}
