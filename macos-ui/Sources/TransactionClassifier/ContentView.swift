import SwiftUI

private enum AppTab: Hashable {
    case classify
    case manageCategories
    case connect
}

struct ContentView: View {
    @Bindable var viewModel: ClassificationViewModel
    @Bindable var connectViewModel: ConnectViewModel
    @FocusState private var searchFocused: Bool
    @State private var scrollTargetId: String?
    @State private var selectedTab: AppTab
    let autoLoadOnAppear: Bool

    init(
        viewModel: ClassificationViewModel,
        connectViewModel: ConnectViewModel,
        autoLoadOnAppear: Bool = true,
        startTab: String? = nil
    ) {
        self.viewModel = viewModel
        self.connectViewModel = connectViewModel
        self.autoLoadOnAppear = autoLoadOnAppear
        _selectedTab = State(initialValue: initialTab(startTab: startTab))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // #R001: Render split-view transaction browsing with list and detail panes.
            NavigationSplitView {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        // #R005: Provide search/filter controls and manual refresh in the list header.
                        TextField("Search description / transaction id", text: $viewModel.searchText)
                            .textFieldStyle(.roundedBorder)
                            .focused($searchFocused)
                            .onSubmit { Task { await viewModel.loadAll() } }
                            .accessibilityIdentifier("search-field")
                        Toggle("Unclassified", isOn: $viewModel.onlyUnclassified).toggleStyle(.switch)
                            .accessibilityIdentifier("only-unclassified-toggle")
                        Button("Refresh") { Task { await viewModel.loadAll() } }
                            .accessibilityIdentifier("refresh-button")
                    }
                    // SwiftUI's ScrollViewReader does not reliably scroll `List` on macOS 14
                    // (Apple Developer Forum #758880), so the transaction list is a
                    // ScrollView + LazyVStack bound to `.scrollPosition(id:anchor:)` which gives
                    // us a reliable programmatic scroll-to-target handle for #R025.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(viewModel.transactions.enumerated()), id: \.element.transaction_id) { idx, row in
                                transactionRowView(row: row, alternating: idx % 2 == 1)
                                    .id(row.transaction_id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrollTargetId, anchor: .center)
                    .accessibilityIdentifier("transaction-list")
                    .overlay(alignment: .topTrailing) {
                        if viewModel.busy {
                            ProgressView().controlSize(.small).padding(8)
                        }
                    }
                    // #R025: Scroll the newly-selected row into view when selection changes (e.g., Next Unclassified).
                    .onChange(of: viewModel.selection) { _, newValue in
                        guard let target = newValue.first else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scrollTargetId = target
                        }
                    }
                }
                // #R020: Toggling the Unclassified filter in either direction automatically reloads the list.
                .onChange(of: viewModel.onlyUnclassified) { _, _ in
                    Task { await viewModel.loadAll() }
                }
                .padding(12)
                .frame(minWidth: 360, idealWidth: 420)
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
            } detail: {
                DetailPane(viewModel: viewModel)
                    .padding(12)
                    .overlay(alignment: .top) {
                        if !viewModel.errorText.isEmpty {
                            Text(viewModel.errorText)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.top, 4)
                                .accessibilityIdentifier("error-banner")
                        }
                    }
            }
            .tabItem { Label("Classify", systemImage: "slider.horizontal.3") }
            .tag(AppTab.classify)
            .accessibilityIdentifier("classify-tab")

            CategoryManagerView(viewModel: viewModel)
                .padding(12)
                .tabItem { Label("Manage Categories", systemImage: "square.and.pencil") }
                .tag(AppTab.manageCategories)
                .accessibilityIdentifier("manage-categories-tab")

            ConnectView(viewModel: connectViewModel)
                .padding(12)
                .tabItem { Label("Connect", systemImage: "link.badge.plus") }
                .tag(AppTab.connect)
        }
        .navigationTitle("Transaction Classifier")
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // #R010: Expose keyboard-first shortcuts for search focus, next-unclassified, and undo.
                Button("Focus Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                    .accessibilityIdentifier("focus-search-button")
                if selectedTab != .connect {
                    Button("Next Unclassified") { viewModel.nextUnclassified() }.keyboardShortcut("]", modifiers: .command)
                        .accessibilityIdentifier("next-unclassified-button")
                }
                Button("Undo") { Task { await viewModel.undoLast() } }.keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("undo-button")
            }
        }
        .task {
            guard autoLoadOnAppear else { return }
            await viewModel.loadAll()
        }
        .onChange(of: viewModel.selection) { _, _ in viewModel.selectionDidChange() }
        .accessibilityIdentifier("content-root")
    }

    @ViewBuilder
    private func transactionRowView(row: TransactionRow, alternating: Bool) -> some View {
        let classificationLabel = row.classification?.display_label ?? "Unclassified"
        let classificationColor: Color = row.classification == nil ? .secondary : .blue
        let accountContext = [row.institution_id, row.account_last_four]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        let isSelected = viewModel.selection.contains(row.transaction_id)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.description).lineLimit(1).font(.body.weight(.medium))
                    .accessibilityIdentifier("transaction-description-\(row.transaction_id)")
                Spacer()
                Text(row.amount as NSNumber, formatter: amountFormatter).monospacedDigit().foregroundStyle(.primary)
                    .accessibilityIdentifier("transaction-amount-\(row.transaction_id)")
            }
            HStack {
                Text(row.date).foregroundStyle(.secondary).lineLimit(1)
                Text("• \(row.status)\(accountContext.isEmpty ? "" : " • \(accountContext)")")
                    .foregroundStyle(.secondary)
                Spacer()
                SaveStateDot(state: viewModel.rowState[row.transaction_id] ?? .idle)
            }.font(.caption)
            Text(classificationLabel).font(.caption).lineLimit(1).foregroundStyle(classificationColor)
                .accessibilityIdentifier("transaction-classification-\(row.transaction_id)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: isSelected, alternating: alternating))
        .contentShape(Rectangle())
        .accessibilityIdentifier("transaction-row-\(row.transaction_id)")
        .onTapGesture {
            // Preserve multi-select semantics via Cmd+click, otherwise replace selection.
            if NSEvent.modifierFlags.contains(.command) {
                if viewModel.selection.contains(row.transaction_id) {
                    viewModel.selection.remove(row.transaction_id)
                } else {
                    viewModel.selection.insert(row.transaction_id)
                }
            } else {
                viewModel.selection = [row.transaction_id]
            }
        }
    }

    private func rowBackground(isSelected: Bool, alternating: Bool) -> some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.25)
            } else if alternating {
                Color.primary.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }
}

private func initialTab(startTab: String?, processInfo: ProcessInfo = .processInfo) -> AppTab {
    let normalized = startTab?.lowercased() ?? processInfo.environment["TELLER_MACOS_START_TAB"]?.lowercased()
    switch normalized {
    case "connect":
        return .connect
    case "manage", "manage-categories":
        return .manageCategories
    default:
        return .classify
    }
}

private struct DetailPane: View {
    @Bindable var viewModel: ClassificationViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection").font(.headline)
            Text("\(viewModel.selection.count) transaction(s)").foregroundStyle(.secondary)
                .accessibilityIdentifier("selection-count")
            CategoryTypeaheadField(
                selectedCategoryId: $viewModel.selectedCategoryId,
                categories: viewModel.categories,
                hasSelection: !viewModel.selection.isEmpty,
                showsMixedSelection: viewModel.selectionHasMixedCategories
            ) { _ in
                await viewModel.selectedCategoryDidChange()
            }
            HStack(spacing: 8) {
                // #R015: Allow apply/clear actions from detail pane for selected rows.
                Button("Apply to Selected") { Task { await viewModel.saveSelection() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.selection.isEmpty || viewModel.selectedCategoryId == nil)
                    .accessibilityIdentifier("apply-selected-button")
                Button("Clear Classification") { Task { await viewModel.clearSelectionClassification() } }
                    .disabled(viewModel.selection.isEmpty)
                    .accessibilityIdentifier("clear-selection-button")
            }
            Divider()
            if let selected = viewModel.selectedRows.first {
                // #R030: Detail pane header includes the selected transaction's identifier.
                Text("Transaction \(selected.transaction_id)").font(.headline)
                    .accessibilityIdentifier("selected-transaction-header")
                Text(selected.description)
                    .accessibilityIdentifier("selected-transaction-description")
                Text("Teller Category: \(selected.teller_category ?? "n/a")")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("selected-teller-category")
                if let klass = selected.classification {
                    Text("Assigned: \(klass.display_label)")
                        .foregroundStyle(.blue)
                        .accessibilityIdentifier("selected-assigned-category")
                } else {
                    Text("Assigned: none")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("selected-assigned-category")
                }
            } else {
                ContentUnavailableView("Select a transaction", systemImage: "square.grid.2x2")
                    .accessibilityIdentifier("selection-empty")
            }
            Spacer()
            HStack(spacing: 8) {
                Text(viewModel.statusText).foregroundStyle(.secondary).font(.caption)
                    .accessibilityIdentifier("status-text")
                Spacer()
                Button("Load more") { Task { await viewModel.loadMore() } }
                    .disabled(!viewModel.canLoadMore || viewModel.busy)
                    .accessibilityIdentifier("load-more-button")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-pane")
    }
}

private struct CategoryManagerView: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Categories").font(.headline)
                    Spacer()
                    Button("Refresh") { Task { await viewModel.reloadCategories() } }
                        .disabled(viewModel.categoryEditorBusy)
                    Button("New") { viewModel.beginNewCategoryDraft() }
                        .disabled(viewModel.categoryEditorBusy)
                }
                List(selection: $viewModel.categoryEditorSelectionId) {
                    ForEach(viewModel.allCategories) { category in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.display_label).lineLimit(1)
                            Text("ID \(category.nys_snw_category_id)").font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(Optional(category.nys_snw_category_id))
                    }
                }
                .onChange(of: viewModel.categoryEditorSelectionId) { _, newValue in
                    viewModel.selectCategoryForEditing(newValue)
                }
                .accessibilityIdentifier("category-manager-list")
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.categoryEditorSelectionId == nil ? "Create Category" : "Edit Category")
                    .font(.headline)
                CategoryDraftForm(draft: $viewModel.categoryEditorDraft)
                    .disabled(viewModel.categoryEditorBusy)
                HStack(spacing: 8) {
                    Button("Save") { Task { await viewModel.saveCategoryDraft() } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(viewModel.categoryEditorBusy)
                        .accessibilityIdentifier("category-save-button")
                    Button("Delete") { Task { await viewModel.deleteSelectedCategory() } }
                        .disabled(viewModel.categoryEditorBusy || viewModel.categoryEditorSelectionId == nil)
                        .accessibilityIdentifier("category-delete-button")
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

private struct CategoryTypeaheadField: View {
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
        Task { await onCommit(option.categoryId) }
    }
    private func syncTextFromSelection() {
        guard hasSelection else { queryText = ""; return }
        if showsMixedSelection { queryText = ""; return }
        queryText = selectedCategoryId.flatMap { id in categories.first { $0.nys_snw_category_id == id }?.display_label } ?? ""
    }
}

private struct SaveStateDot: View {
    let state: SaveState
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(label)
            .accessibilityIdentifier("save-state-dot-\(state.uiToken)")
    }
    private var color: Color {
        switch state {
        case .idle: return .gray.opacity(0.3)
        case .saving: return .orange
        case .saved: return .green
        case .failed: return .red
        }
    }
    private var label: String {
        switch state {
        case .idle: return "Idle"
        case .saving: return "Saving"
        case .saved(let date): return "Saved \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

private extension SaveState {
    var uiToken: String {
        switch self {
        case .idle:
            return "idle"
        case .saving:
            return "saving"
        case .saved:
            return "saved"
        case .failed:
            return "failed"
        }
    }
}

private let amountFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.maximumFractionDigits = 2
    return formatter
}()
