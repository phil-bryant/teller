import Foundation

extension ClassificationViewModel {
    // #R001: Category-editor extension participates in the shared ClassificationViewModel load/save flow.
    // #R005: Category-editor actions preserve classification mutation semantics owned by the view model.
    // #R010: Category-editor save path surfaces optimistic-save failures via shared error state.
    // #R015: Category-editor updates preserve keyboard-triage state and undo compatibility.
    // #R020: Category-editor operations keep transaction pagination state behavior unchanged.
    // #R025: Category-editor interactions preserve initial unclassified-filter behavior.
    // #R030: Category-editor owns bulk category delete behavior and partial failure reporting.
    // #R035: Category-editor composition preserves clear-match behavior exposed by the view model.
    // #R040: Category-editor composition preserves debounced Mailcart search behavior.
    // #R075: Category-editor composition preserves background accurate-total refresh behavior.
    // #R080: Category-editor composition preserves optional transaction-list profiling behavior.
    // #R085: Category-editor logic is split into this focused extension without behavior changes.
    // #R105: Category-editor composition preserves explicit confirm-vs-override semantics.
    // #R110: Category-editor composition preserves unmatched confirm candidate-scope behavior.
    // #R115: Category-editor composition preserves override retargeting guards.
    // #R116: Category-editor composition preserves Mailcart search persistence behavior.
    // #R090: Category-editor composition preserves advanced transaction filter forwarding behavior.
    // #R095: Category-editor composition preserves structured debounced Mailcart search behavior.
    // #R100: Category-editor composition preserves stale match snapshot recovery behavior.
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

    // #R030: Delete every selected category, reload the list, and surface partial failures.
    func deleteSelectedCategories() async {
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
}
