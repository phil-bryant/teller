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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.description).lineLimit(1)
                            Spacer()
                            Text(row.amount as NSNumber, formatter: amountFormatter).monospacedDigit()
                        }
                        HStack {
                            Text(row.date).foregroundStyle(.secondary)
                            Text("• \(row.status)").foregroundStyle(.secondary)
                            if let klass = row.classification {
                                Text("• \(klass.display_label)").lineLimit(1).foregroundStyle(.blue)
                            }
                            Spacer()
                            SaveStateDot(state: viewModel.rowState[row.transaction_id] ?? .idle)
                        }.font(.caption)
                    }.tag(row.transaction_id)
                }.listStyle(.inset(alternatesRowBackgrounds: true))
            }.padding(12)
        } detail: {
            DetailPane(viewModel: viewModel)
                .padding(12)
                .overlay(alignment: .top) {
                    if !viewModel.errorText.isEmpty {
                        Text(viewModel.errorText).foregroundStyle(.red).font(.caption).padding(.top, 4)
                    }
                }
        }
        .navigationTitle("Teller Reclassifier")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Focus Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                Button("Next Unclassified") { viewModel.nextUnclassified() }.keyboardShortcut("]", modifiers: .command)
                Button("Undo") { Task { await viewModel.undoLast() } }.keyboardShortcut("z", modifiers: .command)
            }
        }
        .task { await viewModel.loadAll() }
        .onSubmit(of: .text) { Task { await viewModel.loadAll() } }
    }
}

private struct DetailPane: View {
    @Bindable var viewModel: ReclassificationViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection").font(.headline)
            Text("\(viewModel.selection.count) transaction(s)").foregroundStyle(.secondary)
            Picker("Category", selection: $viewModel.selectedCategoryId) {
                Text("No category").tag(Optional<Int>.none)
                ForEach(viewModel.categories) { category in
                    Text(category.display_label).tag(Optional(category.nys_snw_category_id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
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
