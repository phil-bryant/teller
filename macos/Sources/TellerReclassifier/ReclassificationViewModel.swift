import Foundation
import Observation

struct UndoAction { let prior: [String: TransactionCategory?]; let next: [String: TransactionCategory?] }

@MainActor
@Observable
final class ReclassificationViewModel {
    var categories: [CategoryOption] = []
    var transactions: [TransactionRow] = []
    var selection: Set<String> = []
    var searchText = ""
    var onlyUnclassified = false
    var focusedSearch = false
    var selectedCategoryId: Int?
    var rowState: [String: SaveState] = [:]
    var busy = false
    var errorText = ""
    var undoStack: [UndoAction] = []
    var statusText = "Ready"
    private let api: any ReclassificationAPI
    private var suppressAutoApply = false

    init(api: any ReclassificationAPI = APIClient()) { self.api = api }

    var selectedCategory: CategoryOption? { categories.first { $0.nys_snw_category_id == selectedCategoryId } }
    var selectedRows: [TransactionRow] { transactions.filter { selection.contains($0.transaction_id) } }

    func loadAll() async {
        busy = true; defer { busy = false }
        do {
            async let cats = api.fetchCategories()
            async let txs = api.fetchTransactions(search: searchText, onlyUnclassified: onlyUnclassified)
            categories = try await cats.filter { (($0.applicability ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "N/A") }
            transactions = try await txs.items
            syncPickerToSelection()
            statusText = "Loaded \(transactions.count) transactions"
            errorText = ""
        } catch { errorText = error.localizedDescription; statusText = "Load failed" }
    }

    func selectionDidChange() { syncPickerToSelection() }

    func selectedCategoryDidChange() async {
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

    func undoLast() async {
        guard let last = undoStack.popLast() else { return }
        let updates = last.prior.map { ClassificationMutation(transaction_id: $0.key, nys_snw_category_id: $0.value?.nys_snw_category_id) }
        await apply(updates: updates, shouldRecordUndo: false)
    }

    func nextUnclassified() {
        guard let idx = transactions.firstIndex(where: { selection.contains($0.transaction_id) }),
              let target = transactions[(idx + 1)...].first(where: { $0.classification == nil }) else {
            if let first = transactions.first(where: { $0.classification == nil }) { selection = [first.transaction_id]; syncPickerToSelection() }
            return
        }
        selection = [target.transaction_id]
        syncPickerToSelection()
    }

    private func apply(updates: [ClassificationMutation], shouldRecordUndo: Bool = true) async {
        guard !updates.isEmpty else { return }
        let previous = Dictionary(uniqueKeysWithValues: updates.compactMap { mutation in
            transactions.first(where: { $0.transaction_id == mutation.transaction_id }).map { (mutation.transaction_id, $0.classification) }
        })
        optimisticPatch(updates, state: .saving)
        do {
            _ = try await api.saveClassifications(updates)
            optimisticPatch(updates, state: .saved(Date()))
            if shouldRecordUndo {
                let next = Dictionary(uniqueKeysWithValues: updates.map { mutation in
                    let cat = mutation.nys_snw_category_id.flatMap { id in
                        categories.first(where: { $0.nys_snw_category_id == id }).map {
                            TransactionCategory(nys_snw_category_id: $0.nys_snw_category_id, display_label: $0.display_label)
                        }
                    }
                    return (mutation.transaction_id, cat)
                })
                undoStack.append(UndoAction(prior: previous, next: next))
            }
            statusText = "Saved \(updates.count) classification(s)"
            errorText = ""
            syncPickerToSelection()
        } catch {
            restore(previous)
            updates.forEach { rowState[$0.transaction_id] = .failed(error.localizedDescription) }
            statusText = "Save failed"
            errorText = error.localizedDescription
        }
    }

    private func optimisticPatch(_ updates: [ClassificationMutation], state: SaveState) {
        for mutation in updates {
            guard let idx = transactions.firstIndex(where: { $0.transaction_id == mutation.transaction_id }) else { continue }
            transactions[idx].classification = mutation.nys_snw_category_id.flatMap { id in
                categories.first(where: { $0.nys_snw_category_id == id }).map {
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
}
