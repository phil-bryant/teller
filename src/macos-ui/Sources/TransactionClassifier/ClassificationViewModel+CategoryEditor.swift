import Foundation

extension ClassificationViewModel {
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
