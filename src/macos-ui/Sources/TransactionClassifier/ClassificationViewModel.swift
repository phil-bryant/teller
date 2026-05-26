import Foundation
import Observation

struct UndoAction { let prior: [String: TransactionCategory?]; let next: [String: TransactionCategory?] }
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

    var isEmpty: Bool {
        [level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    private let pageSize = 150
    var categories: [CategoryOption] = []
    var allCategories: [CategoryOption] = []
    var transactions: [TransactionRow] = []
    var totalTransactions = 0
    var selection: Set<String> = []
    var searchText = ""
    var onlyUnclassified = true // #R025: Default to filtering unclassified transactions.
    var focusedSearch = false
    var selectedCategoryId: Int?
    var rowState: [String: SaveState] = [:]
    var busy = false
    var errorText = ""
    var undoStack: [UndoAction] = []
    var statusText = "Ready"
    var categoryEditorSelection: Set<Int> = []
    var categoryEditorDraft = CategoryDraft()
    var categoryEditorBusy = false
    var categoryEditorStatusText = "Select a category to edit, or create a new one."
    var categoryEditorErrorText = ""
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
    var mailcartSearchQuery = ""
    var mailcartSearchResults: [EmailSearchHit] = []
    var mailcartSearchBusy = false
    var mailcartSearchErrorText = ""
    var matchOverrideNote = ""
    private let api: any ClassificationAPI
    private var suppressAutoApply = false
    private var pendingScrollSelectionTransactionId: String?
    private var lastLoadedCandidatesTransactionId: String?
    private var mailcartSearchTaskToken: UUID?
    /// Token issued for each in-flight candidate fetch. Late-arriving responses for a transaction
    /// the user has already moved away from are dropped so the candidates pane never shows stale
    /// data from a previously-selected row (the "HomeAgain showing DoorDash candidates" bug).
    private var candidatesLoadToken: UUID?
    /// Token for the in-flight per-candidate email fetch (same rationale as `candidatesLoadToken`).
    private var emailLoadToken: UUID?
    private static let mailcartSearchDebounceNanoseconds: UInt64 = 250_000_000

    init(api: any ClassificationAPI = APIClient()) { self.api = api }

    var selectedCategory: CategoryOption? { categories.first { $0.nys_snw_category_id == selectedCategoryId } }
    var selectedRows: [TransactionRow] { transactions.filter { selection.contains($0.transaction_id) } }
    var selectionHasMixedCategories: Bool {
        let rows = selectedRows
        guard let first = rows.first?.classification?.nys_snw_category_id else { return rows.contains { $0.classification != nil } }
        return rows.contains { $0.classification?.nys_snw_category_id != first }
    }
    var canLoadMore: Bool { transactions.count < totalTransactions }
    var categoryEditorPrimarySelectionId: Int? {
        guard categoryEditorSelection.count == 1 else { return nil }
        return categoryEditorSelection.first
    }

    func loadAll() async {
        // #R001: Load categories and first-page transactions; clear busy before side-pane fetches (R075/R080).
        // #R080: Optional stderr profiling when TELLER_UI_PROFILE_TRANSACTION_LIST=true.
        TransactionListProfiler.beginLoad()
        busy = true
        let fetchClock = ContinuousClock()
        do {
            async let cats = api.fetchCategories()
            async let txs = api.fetchTransactions(
                search: searchText,
                onlyUnclassified: onlyUnclassified,
                matchState: matchReviewStateFilter,
                onlyUnmovedMatch: matchReviewOnlyUnmoved,
                limit: pageSize,
                offset: 0,
                includeTotal: false,
                countOnly: false
            )
            let fetchedCategories = try await cats
            setCategories(fetchedCategories)
            TransactionListProfiler.markCategoriesLoaded()
            let txFetchStart = fetchClock.now
            let response = try await txs
            let fetchMs = TransactionListProfiler.milliseconds(from: txFetchStart, to: fetchClock.now)
            TransactionListProfiler.markTransactionsFetched(itemCount: response.items.count, milliseconds: fetchMs)
            transactions = response.items
            totalTransactions = response.total
            TransactionListProfiler.markTransactionsAssigned(rowCount: transactions.count)
            syncPickerToSelection()
            statusText = loadStatusText(for: transactions)
            errorText = ""
        } catch {
            errorText = error.localizedDescription
            statusText = "Load failed"
            TransactionListProfiler.markLoadFailed(error.localizedDescription)
            busy = false
            return
        }
        busy = false
        TransactionListProfiler.markBusyCleared()
        lastLoadedCandidatesTransactionId = nil
        Task { await selectedTransactionDidChange() }
        Task { await refreshTransactionTotal() }
    }

    func reloadCategories() async {
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        do {
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            if categoryEditorSelection.contains(where: { id in
                allCategories.first(where: { $0.nys_snw_category_id == id }) == nil
            }) {
                categoryEditorSelection = categoryEditorSelection.filter { id in
                    allCategories.contains { $0.nys_snw_category_id == id }
                }
                syncCategoryEditorToSelection()
            }
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Loaded \(allCategories.count) categories."
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category load failed"
        }
    }

    // #R075: Fetch accurate total in the background after the fast first list paint.
    func refreshTransactionTotal() async {
        do {
            let response = try await api.fetchTransactions(
                search: searchText,
                onlyUnclassified: onlyUnclassified,
                matchState: matchReviewStateFilter,
                onlyUnmovedMatch: matchReviewOnlyUnmoved,
                limit: 1,
                offset: 0,
                includeTotal: true,
                countOnly: true
            )
            totalTransactions = response.total
            statusText = loadStatusText(for: transactions)
        } catch {
            // Keep the estimated total from the fast first load when the background count fails.
        }
    }

    func loadMore() async {
        // #R020: Load additional pages and merge by transaction id without duplicates.
        guard !busy, canLoadMore else { return }
        busy = true; defer { busy = false }
        do {
            let response = try await api.fetchTransactions(
                search: searchText,
                onlyUnclassified: onlyUnclassified,
                matchState: matchReviewStateFilter,
                onlyUnmovedMatch: matchReviewOnlyUnmoved,
                limit: pageSize,
                offset: transactions.count,
                includeTotal: true,
                countOnly: false
            )
            totalTransactions = response.total
            mergeTransactions(response.items)
            statusText = loadStatusText(for: transactions)
            errorText = ""
        } catch {
            statusText = "Load failed"
            errorText = error.localizedDescription
        }
    }

    /// The single transaction the user is currently viewing (the "primary" of any multi-selection).
    /// Drives the candidates pane, email pane, classification picker, and match actions.
    var primaryTransaction: TransactionRow? {
        if let firstId = selection.first { return transactions.first { $0.transaction_id == firstId } }
        return nil
    }

    var selectedTransactionMatch: TransactionMatchInfo? { primaryTransaction?.match }

    /// Compatibility shim: the old viewmodel exposed `selectedMatchRow` as a `MatchReviewRow`.
    /// The unified pipeline keys off transactions, but the actions that update a match still need
    /// a match_id, so expose it here for backward compatibility with the existing call sites.
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

    var canOverrideSelectedMatch: Bool {
        guard let candidateId = overrideTargetEmailMessageId else { return false }
        if selectedMatchId != nil {
            return !activeEmailIdsForSelectedTransaction.contains(candidateId)
        }
        return primaryTransaction != nil
    }

    var canConfirmSelectedMatch: Bool {
        if selectedMatchId != nil { return true }
        return primaryTransaction != nil && overrideTargetEmailMessageId != nil
    }

    var canMarkSelectedMatchNoEmail: Bool {
        primaryTransaction != nil
    }

    var canClearSelectedMatch: Bool {
        selectedMatchId != nil
    }

    /// Triggered whenever the primary selected transaction changes. Loads the candidate set + email
    /// for the primary transaction so the right pane stays in sync with the left pane.
    func selectedTransactionDidChange() async {
        guard let row = primaryTransaction else {
            candidatesLoadToken = nil
            emailLoadToken = nil
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            lastLoadedCandidatesTransactionId = nil
            return
        }
        if lastLoadedCandidatesTransactionId == row.transaction_id, !candidates.isEmpty { return }
        // Clear the candidates pane + email pane immediately so the user never sees stale data
        // from the previously-selected transaction while the new fetch is in flight.
        candidates = []
        mailcartSearchResults = []
        selectedCandidateId = nil
        selectedEmail = nil
        candidatesErrorText = ""
        emailErrorText = ""
        await loadCandidatesForPrimaryTransaction()
    }

    func loadCandidatesForPrimaryTransaction() async {
        guard let row = primaryTransaction else { return }
        candidatesBusy = true
        candidatesErrorText = ""
        let token = UUID()
        candidatesLoadToken = token
        defer {
            if candidatesLoadToken == token { candidatesBusy = false }
        }
        do {
            let rows = try await api.fetchCandidates(transactionId: row.transaction_id)
            // Drop the response if the user has navigated to a different transaction (or cleared
            // selection) while this fetch was in flight.
            guard candidatesLoadToken == token,
                  let current = primaryTransaction,
                  current.transaction_id == row.transaction_id else { return }
            candidates = rows
            lastLoadedCandidatesTransactionId = row.transaction_id
            let activeEmailId = row.match?.email_message_id
            let preferred = rows.first(where: { $0.email_message_id == activeEmailId })?.email_message_id
                ?? rows.first(where: { $0.is_selected_by_ai })?.email_message_id
                ?? rows.first?.email_message_id
            selectedCandidateId = preferred
            await selectedCandidateDidChange()
        } catch {
            guard candidatesLoadToken == token,
                  let current = primaryTransaction,
                  current.transaction_id == row.transaction_id else { return }
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            candidatesErrorText = error.localizedDescription
        }
    }

    func selectedCandidateDidChange() async {
        guard let candidateId = selectedCandidateId else {
            emailLoadToken = nil
            selectedEmail = nil
            return
        }
        emailBusy = true
        emailErrorText = ""
        let token = UUID()
        emailLoadToken = token
        defer {
            if emailLoadToken == token { emailBusy = false }
        }
        do {
            let message = try await api.fetchMessage(emailMessageId: candidateId)
            // Drop the response if the user has switched candidates (or transactions) since this
            // fetch started.
            guard emailLoadToken == token, selectedCandidateId == candidateId else { return }
            selectedEmail = message
        } catch {
            guard emailLoadToken == token, selectedCandidateId == candidateId else { return }
            selectedEmail = nil
            emailErrorText = error.localizedDescription
        }
    }

    func selectCandidate(_ emailMessageId: String?) async {
        selectedCandidateId = emailMessageId
        await selectedCandidateDidChange()
    }

    // #R040: Debounce Mailcart search input and populate results or surface API errors.
    func searchMailcartIfNeeded() async {
        let query = mailcartSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            mailcartSearchResults = []
            mailcartSearchErrorText = ""
            mailcartSearchBusy = false
            return
        }
        let token = UUID()
        mailcartSearchTaskToken = token
        mailcartSearchBusy = true
        try? await Task.sleep(nanoseconds: Self.mailcartSearchDebounceNanoseconds)
        guard mailcartSearchTaskToken == token else { return }
        do {
            let response = try await api.searchMessages(query: query, limit: 25)
            guard mailcartSearchTaskToken == token else { return }
            mailcartSearchResults = response.items
            mailcartSearchErrorText = ""
        } catch {
            guard mailcartSearchTaskToken == token else { return }
            mailcartSearchResults = []
            mailcartSearchErrorText = error.localizedDescription
        }
        if mailcartSearchTaskToken == token { mailcartSearchBusy = false }
    }

    func confirmSelectedMatch() async {
        let trimmedNote = matchOverrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? nil : trimmedNote
        do {
            if let matchId = selectedMatchId {
                _ = try await api.confirmMatch(matchId: matchId)
                matchReviewStatusText = "Confirmed match \(matchId)"
            } else if let transactionId = primaryTransaction?.transaction_id,
                      let emailId = overrideTargetEmailMessageId {
                let response = try await api.confirmTransactionCandidate(
                    transactionId: transactionId,
                    emailMessageId: emailId,
                    note: note
                )
                matchReviewStatusText = "Confirmed candidate for \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a candidate before confirming."
                matchReviewStatusText = "Match confirm failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match confirm failed"
        }
    }

    func overrideSelectedMatch() async {
        guard let emailId = overrideTargetEmailMessageId, !emailId.isEmpty else {
            matchReviewErrorText = "Select a candidate (or paste a message id) before overriding."
            return
        }
        let trimmedNote = matchOverrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? "Overridden in Teller UI" : trimmedNote
        do {
            if let matchId = selectedMatchId {
                _ = try await api.overrideMatch(matchId: matchId, emailMessageId: emailId, note: note)
                matchReviewStatusText = "Overrode match \(matchId)"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.overrideTransactionCandidate(
                    transactionId: transactionId,
                    emailMessageId: emailId,
                    note: note
                )
                matchReviewStatusText = "Assigned email to \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a transaction before overriding."
                matchReviewStatusText = "Match override failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match override failed"
        }
    }

    func markSelectedMatchNoEmail() async {
        do {
            if let matchId = selectedMatchId {
                _ = try await api.markMatchNoEmail(matchId: matchId)
                matchReviewStatusText = "Marked match \(matchId) as no-email"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.markTransactionNoEmail(transactionId: transactionId)
                matchReviewStatusText = "Marked \(response.transaction_id) as no-email"
            } else {
                matchReviewErrorText = "Select a transaction before marking no-email."
                matchReviewStatusText = "No-email action failed"
                return
            }
            matchReviewErrorText = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "No-email action failed"
        }
    }

    func clearSelectedMatch() async {
        // #R035: Deactivate the active match so the transaction returns to unmatched.
        do {
            if let matchId = selectedMatchId {
                let response = try await api.clearMatch(matchId: matchId)
                matchReviewStatusText = "Cleared match \(matchId) for \(response.transaction_id)"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.clearTransactionMatch(transactionId: transactionId)
                matchReviewStatusText = "Cleared match for \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a transaction with an active match before clearing."
                matchReviewStatusText = "Match clear failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match clear failed"
        }
    }

    func selectionDidChange() {
        syncPickerToSelection()
        Task { await selectedTransactionDidChange() }
    }

    func consumePendingScrollSelectionTransactionId() -> String? {
        defer { pendingScrollSelectionTransactionId = nil }
        return pendingScrollSelectionTransactionId
    }

    func selectedCategoryDidChange(committedCategoryId: Int? = nil) async {
        // #R005: Only send updates for rows whose selected category actually changes.
        if suppressAutoApply || selection.isEmpty { return }
        let categoryId = committedCategoryId ?? selectedCategoryId
        let updates: [ClassificationMutation] = selectedRows.compactMap { row -> ClassificationMutation? in
            if row.classification?.nys_snw_category_id == categoryId { return nil }
            return ClassificationMutation(transaction_id: row.transaction_id, nys_snw_category_id: categoryId)
        }
        await apply(updates: updates)
    }

    func saveSelection() async {
        guard let categoryId = selectedCategoryId, !selection.isEmpty else { return }
        let updates = selection.map { ClassificationMutation(transaction_id: $0, nys_snw_category_id: categoryId) }
        await apply(updates: updates)
    }

    func clearSelectionClassification() async {
        guard !selection.isEmpty else { return }
        await apply(updates: selection.map { ClassificationMutation(transaction_id: $0, nys_snw_category_id: nil) })
    }

    func classifySingle(_ transactionId: String, _ categoryId: Int?) async {
        await apply(updates: [.init(transaction_id: transactionId, nys_snw_category_id: categoryId)])
    }

    func beginNewCategoryDraft() {
        categoryEditorSelection = []
        categoryEditorDraft = CategoryDraft()
        categoryEditorErrorText = ""
        categoryEditorStatusText = "Creating a new category."
    }

    func syncCategoryEditorToSelection() {
        switch categoryEditorSelection.count {
        case 0:
            categoryEditorDraft = CategoryDraft()
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Select a category to edit, or create a new one."
        case 1:
            guard let categoryId = categoryEditorSelection.first,
                  let category = allCategories.first(where: { $0.nys_snw_category_id == categoryId }) else {
                beginNewCategoryDraft()
                return
            }
            categoryEditorDraft = CategoryDraft(category: category)
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Editing category \(categoryId)."
        default:
            categoryEditorDraft = CategoryDraft()
            categoryEditorErrorText = ""
            categoryEditorStatusText = "\(categoryEditorSelection.count) categories selected."
        }
    }

    func selectCategoryForEditing(_ categoryId: Int?) {
        guard let categoryId else {
            beginNewCategoryDraft()
            return
        }
        categoryEditorSelection = [categoryId]
        syncCategoryEditorToSelection()
    }

    func saveCategoryDraft() async {
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        do {
            let saved: CategoryOption
            if let categoryId = categoryEditorPrimarySelectionId {
                saved = try await api.updateCategory(id: categoryId, category: categoryEditorDraft.payload)
            } else {
                saved = try await api.createCategory(categoryEditorDraft.payload)
            }
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            categoryEditorSelection = [saved.nys_snw_category_id]
            categoryEditorDraft = CategoryDraft(category: saved)
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Saved category \(saved.nys_snw_category_id)."
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category save failed"
        }
    }

    func deleteSelectedCategories() async {
        // #R030: Delete every selected category, reload the list, and surface partial failures.
        guard !categoryEditorSelection.isEmpty else { return }
        let idsToDelete = categoryEditorSelection.sorted()
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        var deletedCount = 0
        var failures: [String] = []
        for categoryId in idsToDelete {
            do {
                _ = try await api.deleteCategory(id: categoryId)
                deletedCount += 1
            } catch {
                failures.append("\(categoryId): \(error.localizedDescription)")
            }
        }
        do {
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category reload failed after delete"
            return
        }
        beginNewCategoryDraft()
        if failures.isEmpty {
            categoryEditorErrorText = ""
            categoryEditorStatusText = deletedCount == 1
                ? "Deleted category \(idsToDelete[0])."
                : "Deleted \(deletedCount) categories."
        } else {
            categoryEditorErrorText = failures.joined(separator: "; ")
            categoryEditorStatusText = "Deleted \(deletedCount) of \(idsToDelete.count) categories."
        }
    }

    func undoLast() async {
        // #R015: Replay prior category assignments for the most recent save action.
        guard let last = undoStack.popLast() else { return }
        let updates = last.prior.map { ClassificationMutation(transaction_id: $0.key, nys_snw_category_id: $0.value?.nys_snw_category_id) }
        await apply(updates: updates, shouldRecordUndo: false)
    }

    func nextUnclassified() {
        // #R015: Jump selection to the next unclassified transaction for keyboard-first triage.
        guard let idx = transactions.firstIndex(where: { selection.contains($0.transaction_id) }),
              let target = transactions[(idx + 1)...].first(where: { $0.classification == nil }) else {
            if let first = transactions.first(where: { $0.classification == nil }) {
                selection = [first.transaction_id]
                pendingScrollSelectionTransactionId = first.transaction_id
                syncPickerToSelection()
            }
            return
        }
        selection = [target.transaction_id]
        pendingScrollSelectionTransactionId = target.transaction_id
        syncPickerToSelection()
    }

    private func apply(updates: [ClassificationMutation], shouldRecordUndo: Bool = true) async {
        // #R010: Apply optimistic UI state, commit via API, then rollback on errors.
        guard !updates.isEmpty else { return }
        // #R010: Drop mutations that match the row's current classification so a redundant
        // apply (e.g. typeahead auto-apply followed by an explicit "Apply to Selected" click)
        // does not push an identity entry onto the undo stack and swallow a subsequent undo.
        let effectiveUpdates = updates.filter { mutation in
            guard let row = transactions.first(where: { $0.transaction_id == mutation.transaction_id }) else { return false }
            return row.classification?.nys_snw_category_id != mutation.nys_snw_category_id
        }
        guard !effectiveUpdates.isEmpty else { return }
        let previous = Dictionary(uniqueKeysWithValues: effectiveUpdates.compactMap { mutation in
            transactions.first(where: { $0.transaction_id == mutation.transaction_id }).map { (mutation.transaction_id, $0.classification) }
        })
        optimisticPatch(effectiveUpdates, state: .saving)
        do {
            _ = try await api.saveClassifications(effectiveUpdates)
            optimisticPatch(effectiveUpdates, state: .saved(Date()))
            if shouldRecordUndo {
                let next = Dictionary(uniqueKeysWithValues: effectiveUpdates.map { mutation in
                    let cat = mutation.nys_snw_category_id.flatMap { id in
                        allCategories.first(where: { $0.nys_snw_category_id == id }).map {
                            TransactionCategory(nys_snw_category_id: $0.nys_snw_category_id, display_label: $0.display_label)
                        }
                    }
                    return (mutation.transaction_id, cat)
                })
                undoStack.append(UndoAction(prior: previous, next: next))
            }
            statusText = "Saved \(effectiveUpdates.count) classification(s)"
            errorText = ""
            syncPickerToSelection()
        } catch {
            restore(previous)
            effectiveUpdates.forEach { rowState[$0.transaction_id] = .failed(error.localizedDescription) }
            statusText = "Save failed"
            errorText = error.localizedDescription
        }
    }

    private func optimisticPatch(_ updates: [ClassificationMutation], state: SaveState) {
        for mutation in updates {
            guard let idx = transactions.firstIndex(where: { $0.transaction_id == mutation.transaction_id }) else { continue }
            transactions[idx].classification = mutation.nys_snw_category_id.flatMap { id in
                allCategories.first(where: { $0.nys_snw_category_id == id }).map {
                    .init(nys_snw_category_id: $0.nys_snw_category_id, display_label: $0.display_label)
                }
            }
            rowState[mutation.transaction_id] = state
        }
    }

    private func restore(_ prior: [String: TransactionCategory?]) {
        for (transactionId, previousCategory) in prior {
            guard let idx = transactions.firstIndex(where: { $0.transaction_id == transactionId }) else { continue }
            transactions[idx].classification = previousCategory
            rowState[transactionId] = .idle
        }
        syncPickerToSelection()
    }

    private func syncPickerToSelection() {
        let rows = selectedRows
        let current = rows.first?.classification?.nys_snw_category_id
        let normalized = rows.allSatisfy { $0.classification?.nys_snw_category_id == current } ? current : nil
        suppressAutoApply = true
        selectedCategoryId = normalized
        suppressAutoApply = false
    }

    private func loadStatusText(for rows: [TransactionRow]) -> String {
        guard let firstDate = rows.first?.date else { return "Loaded 0 transactions" }
        let minDate = rows.map(\.date).min() ?? firstDate
        let maxDate = rows.map(\.date).max() ?? firstDate
        return "Loaded \(rows.count) transactions (\(minDate) to \(maxDate))"
    }

    private func mergeTransactions(_ newRows: [TransactionRow]) {
        guard !newRows.isEmpty else { return }
        var seen = Set(transactions.map(\.transaction_id))
        for row in newRows where !seen.contains(row.transaction_id) {
            transactions.append(row)
            seen.insert(row.transaction_id)
        }
    }

    private func setCategories(_ fetched: [CategoryOption]) {
        let sortedById = fetched.sorted { $0.nys_snw_category_id < $1.nys_snw_category_id }
        allCategories = sortedById
        categories = sortedById.filter { (($0.applicability ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "N/A") }
    }
}
