import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ReclassificationViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Search description / transaction id", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                    Toggle("Unclassified", isOn: $viewModel.onlyUnclassified).toggleStyle(.switch)
                    Button("Refresh") { Task { await viewModel.loadAll() } }
                }
                List(viewModel.transactions, selection: $viewModel.selection) { row in
                    let classificationLabel = row.classification?.display_label ?? "Unclassified"
                    let classificationColor: Color = row.classification == nil ? .secondary : .blue
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.description).lineLimit(1).font(.body.weight(.medium))
                            Spacer()
                            Text(row.amount as NSNumber, formatter: amountFormatter).monospacedDigit().foregroundStyle(.primary)
                        }
                        HStack {
                            Text(row.date).foregroundStyle(.secondary).lineLimit(1)
                            Text("• \(row.status)").foregroundStyle(.secondary)
                            Spacer()
                            SaveStateDot(state: viewModel.rowState[row.transaction_id] ?? .idle)
                        }.font(.caption)
                        Text(classificationLabel).font(.caption).lineLimit(1).foregroundStyle(classificationColor)
                    }.tag(row.transaction_id)
                        .padding(.vertical, 3)
                }.listStyle(.inset(alternatesRowBackgrounds: true))
            }
            .padding(12)
            .frame(minWidth: 360, idealWidth: 420)
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
        } detail: {
            DetailPane(viewModel: viewModel)
                .padding(12)
                .overlay(alignment: .top) {
                    if !viewModel.errorText.isEmpty {
                        Text(viewModel.errorText).foregroundStyle(.red).font(.caption).padding(.top, 4)
                    }
                }
        }
        .navigationTitle("Transaction Classifier")
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Focus Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                Button("Next Unclassified") { viewModel.nextUnclassified() }.keyboardShortcut("]", modifiers: .command)
                Button("Undo") { Task { await viewModel.undoLast() } }.keyboardShortcut("z", modifiers: .command)
            }
        }
        .task { await viewModel.loadAll() }
        .onSubmit(of: .text) { Task { await viewModel.loadAll() } }
        .onChange(of: viewModel.selection) { _, _ in viewModel.selectionDidChange() }
    }
}

private struct DetailPane: View {
    @Bindable var viewModel: ReclassificationViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection").font(.headline)
            Text("\(viewModel.selection.count) transaction(s)").foregroundStyle(.secondary)
            CategoryTypeaheadField(
                selectedCategoryId: $viewModel.selectedCategoryId,
                categories: viewModel.categories,
                hasSelection: !viewModel.selection.isEmpty,
                showsMixedSelection: viewModel.selectionHasMixedCategories
            ) { _ in
                await viewModel.selectedCategoryDidChange()
            }
            HStack(spacing: 8) {
                Button("Apply to Selected") { Task { await viewModel.saveSelection() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.selection.isEmpty || viewModel.selectedCategoryId == nil)
                Button("Clear Classification") { Task { await viewModel.clearSelectionClassification() } }
                    .disabled(viewModel.selection.isEmpty)
            }
            Divider()
            if let selected = viewModel.selectedRows.first {
                Text("Transaction").font(.headline)
                Text(selected.description)
                Text("Teller Category: \(selected.teller_category ?? "n/a")").foregroundStyle(.secondary)
                if let klass = selected.classification {
                    Text("Assigned: \(klass.display_label)").foregroundStyle(.blue)
                } else {
                    Text("Assigned: none").foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Select a transaction", systemImage: "square.grid.2x2")
            }
            Spacer()
            Text(viewModel.statusText).foregroundStyle(.secondary).font(.caption)
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
                        }
                        if options.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }.padding(4)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
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
        queryText = selectedCategoryId.flatMap { id in categories.first { $0.nys_snw_category_id == id }?.display_label } ?? "No category"
    }
}

private struct SaveStateDot: View {
    let state: SaveState
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).help(label)
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

private let amountFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.maximumFractionDigits = 2
    return formatter
}()
