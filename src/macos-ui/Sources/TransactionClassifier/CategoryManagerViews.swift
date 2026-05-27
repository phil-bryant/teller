import SwiftUI

struct CategoryManagerView: View {
    @Bindable var viewModel: ClassificationViewModel

    private var categoryEditorTitle: String {
        switch viewModel.categoryEditorSelection.count {
        case 0:
            return "Create Category"
        case 1:
            return "Edit Category"
        default:
            return "\(viewModel.categoryEditorSelection.count) Categories Selected"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Categories").font(.headline)
                    Spacer()
                    Button("Refresh") { Task { await viewModel.reloadCategories() } }
                        .disabled(viewModel.categoryEditorBusy)
                        .accessibilityIdentifier("category-refresh-button")
                    Button("New") { viewModel.beginNewCategoryDraft() }
                        .disabled(viewModel.categoryEditorBusy)
                        .accessibilityIdentifier("category-new-button")
                    // #R040: Bulk delete is available whenever one or more categories are selected.
                    Button("Delete") { Task { await viewModel.deleteSelectedCategories() } }
                        .disabled(viewModel.categoryEditorBusy || viewModel.categoryEditorSelection.isEmpty)
                        .accessibilityIdentifier("category-bulk-delete-button")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.allCategories) { category in
                            CategoryListRowView(
                                category: category,
                                isSelected: viewModel.categoryEditorSelection.contains(category.nys_snw_category_id)
                            )
                            .accessibilityIdentifier("category-row-\(category.nys_snw_category_id)")
                            .onTapGesture {
                                let categoryId = category.nys_snw_category_id
                                if NSEvent.modifierFlags.contains(.command) {
                                    if viewModel.categoryEditorSelection.contains(categoryId) {
                                        viewModel.categoryEditorSelection.remove(categoryId)
                                    } else {
                                        viewModel.categoryEditorSelection.insert(categoryId)
                                    }
                                } else {
                                    viewModel.categoryEditorSelection = [categoryId]
                                }
                            }
                        }
                    }
                }
                .onChange(of: viewModel.categoryEditorSelection) { _, _ in
                    viewModel.syncCategoryEditorToSelection()
                }
                .accessibilityIdentifier("category-manager-list")
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                Text(categoryEditorTitle)
                    .font(.headline)
                CategoryDraftForm(draft: $viewModel.categoryEditorDraft)
                    .disabled(viewModel.categoryEditorBusy || viewModel.categoryEditorSelection.count != 1)
                HStack(spacing: 8) {
                    Button("Save") { Task { await viewModel.saveCategoryDraft() } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(viewModel.categoryEditorBusy || viewModel.categoryEditorPrimarySelectionId == nil)
                        .accessibilityIdentifier("category-save-button")
                }
                if !viewModel.categoryEditorErrorText.isEmpty {
                    Text(viewModel.categoryEditorErrorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("category-error-banner")
                } else {
                    Text(viewModel.categoryEditorStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("category-status-text")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            if viewModel.allCategories.isEmpty {
                await viewModel.reloadCategories()
            }
        }
    }
}

private struct CategoryListRowView: View {
    let category: CategoryOption
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category.display_label).lineLimit(1)
            Text("ID \(category.nys_snw_category_id)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct CategoryDraftForm: View {
    @Binding var draft: CategoryDraft

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            draftRow("Level 1", text: $draft.level_1, identifier: "category-field-level-1")
            draftRow("Level 1 Name", text: $draft.level_1_name, identifier: "category-field-level-1-name")
            draftRow("Level 2", text: $draft.level_2, identifier: "category-field-level-2")
            draftRow("Level 2 Name", text: $draft.level_2_name, identifier: "category-field-level-2-name")
            draftRow("Level 3", text: $draft.level_3, identifier: "category-field-level-3")
            draftRow("Level 4", text: $draft.level_4, identifier: "category-field-level-4")
            draftRow("Categorization", text: $draft.categorization, identifier: "category-field-categorization")
            draftRow("Applicability", text: $draft.applicability, identifier: "category-field-applicability")
        }
    }

    @ViewBuilder
    private func draftRow(_ label: String, text: Binding<String>, identifier: String) -> some View {
        GridRow {
            Text(label)
                .frame(width: 120, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct CategoryTypeaheadField: View {
    @Binding var selectedCategoryId: Int?
    let categories: [CategoryOption]
    let hasSelection: Bool
    let showsMixedSelection: Bool
    let onCommit: (Int?) async -> Void

    @State private var queryText = ""
    @State private var highlightedIndex = 0
    @FocusState private var isFocused: Bool

    private var options: [CategoryTypeaheadOption] { rankedCategoryOptions(query: queryText, categories: categories) }
    private var isExpanded: Bool { isFocused || !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Type to search categories...", text: $queryText)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commitHighlightedOption() }
                .onChange(of: isFocused) { _, focused in
                    if focused, detectAppLaunchMode() == .normal {
                        activateTransactionClassifierForInput()
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    if detectAppLaunchMode() == .normal {
                        activateTransactionClassifierForInput()
                    }
                    isFocused = true
                })
                .onChange(of: queryText) { _, _ in highlightedIndex = 0 }
                .onAppear { syncTextFromSelection() }
                .onChange(of: selectedCategoryId) { _, _ in syncTextFromSelection() }
                .onChange(of: hasSelection) { _, _ in syncTextFromSelection() }
                .onChange(of: showsMixedSelection) { _, _ in syncTextFromSelection() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
                .onKeyPress(.escape) { syncTextFromSelection(); isFocused = false; return .handled }
                .accessibilityIdentifier("category-typeahead-field")
            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            Button {
                                commit(option)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(option.label).lineLimit(1)
                                    Spacer()
                                    if selectedCategoryId == option.categoryId { Image(systemName: "checkmark").font(.caption) }
                                }.padding(.horizontal, 8).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index == highlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("category-option-\(option.id)")
                        }
                        if options.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
                                .accessibilityIdentifier("category-no-matches")
                        }
                    }.padding(4)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("category-options-list")
            }
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("category-typeahead-container")
    }

    private func moveHighlight(by delta: Int) {
        guard !options.isEmpty else { return }
        highlightedIndex = max(0, min(options.count - 1, highlightedIndex + delta))
    }

    private func commitHighlightedOption() {
        guard !options.isEmpty else { return }
        commit(options[max(0, min(options.count - 1, highlightedIndex))])
    }

    private func commit(_ option: CategoryTypeaheadOption) {
        selectedCategoryId = option.categoryId
        queryText = option.label
        highlightedIndex = 0
        Task { @MainActor in await onCommit(option.categoryId) }
    }

    private func syncTextFromSelection() {
        guard hasSelection else { queryText = ""; return }
        if showsMixedSelection { queryText = ""; return }
        queryText = selectedCategoryId.flatMap { id in categories.first { $0.nys_snw_category_id == id }?.display_label } ?? ""
    }
}
