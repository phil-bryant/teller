import Foundation

extension ClassificationViewModel {
    // #R005: Only send updates for rows whose selected category actually changes.
    func selectedCategoryDidChange(committedCategoryId: Int? = nil) async {
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

    // #R015: Replay prior category assignments for the most recent save action.
    func undoLast() async {
        guard let last = undoStack.popLast() else { return }
        let updates = last.prior.map {
            ClassificationMutation(transaction_id: $0.key, nys_snw_category_id: $0.value?.nys_snw_category_id)
        }
        await apply(updates: updates, shouldRecordUndo: false)
    }

    // #R015: Jump selection to the next unclassified transaction for keyboard-first triage.
    func nextUnclassified() {
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

    // #R010: Apply optimistic UI state, commit via API, then rollback on errors.
    private func apply(updates: [ClassificationMutation], shouldRecordUndo: Bool = true) async {
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
                undoStack.append(UndoAction(prior: previous))
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
}
