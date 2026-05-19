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
    private let pageSize = 300
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
    var categoryEditorSelectionId: Int?
    var categoryEditorDraft = CategoryDraft()
    var categoryEditorBusy = false
    var categoryEditorStatusText = "Select a category to edit, or create a new one."
    var categoryEditorErrorText = ""
    var matchReviewRows: [MatchReviewRow] = []
    var matchReviewTotal = 0
    var matchReviewStateFilter = ""
    var matchReviewOnlyUnmoved = true
    var selectedMatchId: Int?
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
    private var lastLoadedCandidatesTransactionId: String?
    private var mailcartSearchTaskToken: UUID?
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

    func loadAll() async {
        // #R001: Load categories and the first transaction page together, then refresh derived UI state.
        busy = true; defer { busy = false }
        do {
            async let cats = api.fetchCategories()
            async let txs = api.fetchTransactions(search: searchText, onlyUnclassified: onlyUnclassified, limit: pageSize, offset: 0)
            let fetchedCategories = try await cats
            setCategories(fetchedCategories)
            let response = try await txs
            transactions = response.items
            totalTransactions = response.total
            syncPickerToSelection()
            statusText = loadStatusText(for: transactions)
            errorText = ""
        } catch { errorText = error.localizedDescription; statusText = "Load failed" }
    }

    func reloadCategories() async {
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        do {
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            if let selectedId = categoryEditorSelectionId, allCategories.first(where: { $0.nys_snw_category_id == selectedId }) == nil {
                beginNewCategoryDraft()
            }
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Loaded \(allCategories.count) categories."
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category load failed"
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
                limit: pageSize,
                offset: transactions.count
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

    var selectedMatchRow: MatchReviewRow? { matchReviewRows.first { $0.match_id == selectedMatchId } }

    /// Match-review rows deduped by `transaction_id`. Each transaction appears at most once;
    /// the chosen "representative" row is the highest-confidence active row for that transaction
    /// (ties broken by most-recent `selected_at`, then by `match_id`). Original row order is
    /// preserved otherwise.
    /// This stops a single transaction with N AI-linked emails (matchy can correctly tie multiple
    /// emails to one charge, per the AI prompt's "1 transaction may map to multiple emails" rule)
    /// from rendering as N apparent transactions in the left pane.
    var matchReviewGroupedRows: [MatchReviewRow] {
        var representatives: [String: MatchReviewRow] = [:]
        var orderedIds: [String] = []
        for row in matchReviewRows {
            if let existing = representatives[row.transaction_id] {
                if Self.isBetterRepresentative(row, than: existing) {
                    representatives[row.transaction_id] = row
                }
            } else {
                representatives[row.transaction_id] = row
                orderedIds.append(row.transaction_id)
            }
        }
        return orderedIds.compactMap { representatives[$0] }
    }

    private static func isBetterRepresentative(_ candidate: MatchReviewRow, than current: MatchReviewRow) -> Bool {
        let candidateConfidence = candidate.ai_confidence ?? -1
        let currentConfidence = current.ai_confidence ?? -1
        if candidateConfidence != currentConfidence { return candidateConfidence > currentConfidence }
        if candidate.selected_at != current.selected_at { return candidate.selected_at > current.selected_at }
        return candidate.match_id > current.match_id
    }

    /// How many active match rows exist for the given transaction. Used by the left pane to render
    /// "N emails" hints when matchy linked multiple emails to one transaction.
    func matchedEmailCount(for transactionId: String) -> Int {
        matchReviewRows.reduce(0) { $0 + ($1.transaction_id == transactionId ? 1 : 0) }
    }

    /// All `email_message_id`s currently active for the selected transaction. The candidates pane
    /// uses this set to mark every AI-picked candidate as "active" (not just the one representative
    /// match_id's email).
    var activeEmailIdsForSelectedTransaction: Set<String> {
        guard let row = selectedMatchRow else { return [] }
        var result = Set<String>()
        for matchRow in matchReviewRows where matchRow.transaction_id == row.transaction_id {
            if let emailId = matchRow.email_message_id, !emailId.isEmpty {
                result.insert(emailId)
            }
        }
        return result
    }

    var overrideTargetEmailMessageId: String? {
        let trimmedTyped = matchOverrideEmailMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTyped.isEmpty { return trimmedTyped }
        return selectedCandidateId
    }

    var canOverrideSelectedMatch: Bool {
        guard selectedMatchId != nil, let candidateId = overrideTargetEmailMessageId else { return false }
        return !activeEmailIdsForSelectedTransaction.contains(candidateId)
    }

    func loadMatchReview() async {
        busy = true
        defer { busy = false }
        do {
            let response = try await api.fetchMatchReview(
                state: matchReviewStateFilter,
                onlyUnmoved: matchReviewOnlyUnmoved,
                limit: pageSize,
                offset: 0
            )
            matchReviewRows = response.items
            matchReviewTotal = response.total
            matchReviewStatusText = "Loaded \(response.items.count) of \(response.total) matches"
            matchReviewErrorText = ""
            if let currentId = selectedMatchId, !response.items.contains(where: { $0.match_id == currentId }) {
                selectedMatchId = nil
            }
            if selectedMatchId == nil {
                selectedMatchId = response.items.first?.match_id
            }
            await selectedMatchDidChange()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match review load failed"
        }
    }

    func selectedMatchDidChange() async {
        guard let row = selectedMatchRow else {
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            lastLoadedCandidatesTransactionId = nil
            return
        }
        if lastLoadedCandidatesTransactionId == row.transaction_id { return }
        await loadCandidatesForSelectedMatch()
    }

    func loadCandidatesForSelectedMatch() async {
        guard let row = selectedMatchRow else { return }
        candidatesBusy = true
        candidatesErrorText = ""
        defer { candidatesBusy = false }
        do {
            let rows = try await api.fetchCandidates(transactionId: row.transaction_id)
            candidates = rows
            lastLoadedCandidatesTransactionId = row.transaction_id
            let preferred = rows.first(where: { $0.email_message_id == row.email_message_id })?.email_message_id
                ?? rows.first(where: { $0.is_selected_by_ai })?.email_message_id
                ?? rows.first?.email_message_id
            selectedCandidateId = preferred
            await selectedCandidateDidChange()
        } catch {
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            candidatesErrorText = error.localizedDescription
        }
    }

    func selectedCandidateDidChange() async {
        guard let candidateId = selectedCandidateId else {
            selectedEmail = nil
            return
        }
        emailBusy = true
        emailErrorText = ""
        defer { emailBusy = false }
        do {
            selectedEmail = try await api.fetchMessage(emailMessageId: candidateId)
        } catch {
            selectedEmail = nil
            emailErrorText = error.localizedDescription
        }
    }

    func selectCandidate(_ emailMessageId: String?) async {
        selectedCandidateId = emailMessageId
        await selectedCandidateDidChange()
    }

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
        guard let matchId = selectedMatchId else { return }
        do {
            _ = try await api.confirmMatch(matchId: matchId)
            matchReviewStatusText = "Confirmed match \(matchId)"
            await loadMatchReview()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match confirm failed"
        }
    }

    func overrideSelectedMatch() async {
        guard let matchId = selectedMatchId else { return }
        guard let emailId = overrideTargetEmailMessageId, !emailId.isEmpty else {
            matchReviewErrorText = "Select a candidate (or paste a message id) before overriding."
            return
        }
        let trimmedNote = matchOverrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? "Overridden in Teller UI" : trimmedNote
        do {
            _ = try await api.overrideMatch(matchId: matchId, emailMessageId: emailId, note: note)
            matchReviewStatusText = "Overrode match \(matchId)"
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadMatchReview()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match override failed"
        }
    }

    func markSelectedMatchNoEmail() async {
        guard let matchId = selectedMatchId else { return }
        do {
            _ = try await api.markMatchNoEmail(matchId: matchId)
            matchReviewStatusText = "Marked match \(matchId) as no-email"
            matchReviewErrorText = ""
            lastLoadedCandidatesTransactionId = nil
            await loadMatchReview()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "No-email action failed"
        }
    }

    func selectionDidChange() { syncPickerToSelection() }

    func selectedCategoryDidChange() async {
        // #R005: Only send updates for rows whose selected category actually changes.
        if suppressAutoApply || selection.isEmpty { return }
        let updates: [ClassificationMutation] = selectedRows.compactMap { row -> ClassificationMutation? in
            if row.classification?.nys_snw_category_id == selectedCategoryId { return nil }
            return ClassificationMutation(transaction_id: row.transaction_id, nys_snw_category_id: selectedCategoryId)
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
        categoryEditorSelectionId = nil
        categoryEditorDraft = CategoryDraft()
        categoryEditorErrorText = ""
        categoryEditorStatusText = "Creating a new category."
    }

    func selectCategoryForEditing(_ categoryId: Int?) {
        guard let categoryId, let category = allCategories.first(where: { $0.nys_snw_category_id == categoryId }) else {
            beginNewCategoryDraft()
            return
        }
        categoryEditorSelectionId = categoryId
        categoryEditorDraft = CategoryDraft(category: category)
        categoryEditorErrorText = ""
        categoryEditorStatusText = "Editing category \(categoryId)."
    }

    func saveCategoryDraft() async {
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        do {
            let saved: CategoryOption
            if let categoryId = categoryEditorSelectionId {
                saved = try await api.updateCategory(id: categoryId, category: categoryEditorDraft.payload)
            } else {
                saved = try await api.createCategory(categoryEditorDraft.payload)
            }
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            categoryEditorSelectionId = saved.nys_snw_category_id
            categoryEditorDraft = CategoryDraft(category: saved)
            categoryEditorErrorText = ""
            categoryEditorStatusText = "Saved category \(saved.nys_snw_category_id)."
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category save failed"
        }
    }

    func deleteSelectedCategory() async {
        guard let categoryId = categoryEditorSelectionId else { return }
        categoryEditorBusy = true
        defer { categoryEditorBusy = false }
        do {
            _ = try await api.deleteCategory(id: categoryId)
            let fetchedCategories = try await api.fetchCategories()
            setCategories(fetchedCategories)
            beginNewCategoryDraft()
            categoryEditorStatusText = "Deleted category \(categoryId)."
            syncPickerToSelection()
        } catch {
            categoryEditorErrorText = error.localizedDescription
            categoryEditorStatusText = "Category delete failed"
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
            if let first = transactions.first(where: { $0.classification == nil }) { selection = [first.transaction_id]; syncPickerToSelection() }
            return
        }
        selection = [target.transaction_id]
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
        allCategories = fetched
        categories = fetched.filter { (($0.applicability ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "N/A") }
    }
}
