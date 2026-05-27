import Foundation

extension ClassificationViewModel {
    // #R001: Transaction-loading extension owns the concurrent first-load flow for categories + rows.
    // #R005: Transaction-loading composition preserves redundant-write filtering behavior downstream.
    // #R010: Transaction-loading composition preserves optimistic-save rollback behavior downstream.
    // #R015: Transaction-loading composition preserves keyboard progression and undo behavior downstream.
    // #R020: Transaction-loading extension owns append-page merge behavior without duplicate rows.
    // #R025: Transaction-loading extension preserves default unclassified-filter startup behavior.
    // #R030: Transaction-loading composition preserves category-editor delete behavior contracts.
    // #R035: Transaction-loading composition preserves clear-match behavior exposed by the view model.
    // #R040: Transaction-loading composition preserves debounced Mailcart search behavior.
    // #R075: Transaction-loading extension owns background accurate-total refresh behavior.
    // #R080: Transaction-loading extension owns optional transaction-list profiling behavior.
    // #R085: Transaction-loading logic is split into this focused extension without behavior changes.
    // #R090: Transaction-loading extension forwards advanced filters on every fetch call.
    // #R095: Transaction-loading composition preserves structured debounced Mailcart search behavior.
    // #R001: Load categories and first-page transactions; clear busy before side-pane fetches (R075/R080).
    // #R080: Optional stderr profiling when TELLER_UI_PROFILE_TRANSACTION_LIST=true.
    func loadAll() async {
        guard !busy else { return }
        TransactionListProfiler.beginLoad()
        busy = true
        let fetchClock = ContinuousClock()
        do {
            async let cats = api.fetchCategories()
            async let txs = api.fetchTransactions(
                transactionFetchOptions(limit: pageSize, offset: 0, includeTotal: false, countOnly: false)
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
        await selectedTransactionDidChange()
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
                transactionFetchOptions(limit: 1, offset: 0, includeTotal: true, countOnly: true)
            )
            totalTransactions = response.total
            statusText = loadStatusText(for: transactions)
        } catch {
            // Keep the estimated total from the fast first load when the background count fails.
        }
    }

    // #R020: Load additional pages and merge by transaction id without duplicates.
    func loadMore() async {
        guard !busy, canLoadMore else { return }
        busy = true
        defer { busy = false }
        do {
            let response = try await api.fetchTransactions(
                transactionFetchOptions(
                    limit: pageSize,
                    offset: transactions.count,
                    includeTotal: true,
                    countOnly: false
                )
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

    func selectionDidChange() {
        syncPickerToSelection()
        Task { await selectedTransactionDidChange() }
    }

    func consumePendingScrollSelectionTransactionId() -> String? {
        defer { pendingScrollSelectionTransactionId = nil }
        return pendingScrollSelectionTransactionId
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
}
