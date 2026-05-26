import SwiftUI
import WebKit

private enum AppTab: Hashable {
    case matchAndClassify
    case manageCategories
    case connect
}

struct ContentView: View {
    @Bindable var viewModel: ClassificationViewModel
    @Bindable var connectViewModel: ConnectViewModel
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
        // #R001: Render transaction triage UI as an HSplitView with 3 panes (Transactions /
        // #R001: Candidates / Classification + Email) inside the unified Match & Classify tab.
        TabView(selection: $selectedTab) {
            MatchAndClassifyView(viewModel: viewModel, scrollTargetId: $scrollTargetId)
                .padding(12)
                .tabItem { Label("Match & Classify", systemImage: "envelope.badge.shield.half.filled") }
                .tag(AppTab.matchAndClassify)

            CategoryManagerView(viewModel: viewModel)
                .padding(12)
                .tabItem { Label("Manage Categories", systemImage: "square.and.pencil") }
                .tag(AppTab.manageCategories)

            ConnectView(viewModel: connectViewModel)
                .padding(12)
                .tabItem { Label("Connect", systemImage: "link.badge.plus") }
                .tag(AppTab.connect)
        }
        .navigationTitle("Transaction Classifier")
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // #R010: Expose keyboard-first shortcuts for next-unclassified and undo.
                if selectedTab == .matchAndClassify {
                    Button("Next Unclassified") { viewModel.nextUnclassified() }.keyboardShortcut("]", modifiers: .command)
                        .accessibilityIdentifier("next-unclassified-button")
                }
                if selectedTab == .matchAndClassify {
                    Button("Undo") { Task { await viewModel.undoLast() } }.keyboardShortcut("z", modifiers: .command)
                        .accessibilityIdentifier("undo-button")
                }
            }
        }
        .task {
            guard autoLoadOnAppear else { return }
            await viewModel.loadAll()
        }
        .onChange(of: viewModel.selection) { _, _ in viewModel.selectionDidChange() }
        .transaction { transaction in
            if detectAppLaunchMode() == .uiTesting {
                transaction.animation = nil
            }
        }
    }

}

private func initialTab(startTab: String?, processInfo: ProcessInfo = .processInfo) -> AppTab {
    let normalized = startTab?.lowercased() ?? processInfo.environment["TELLER_MACOS_START_TAB"]?.lowercased()
    switch normalized {
    case "connect", "setup", "teller-setup":
        return .connect
    case "manage", "manage-categories":
        return .manageCategories
    case "classify", "match", "match-review", "match-and-classify":
        return .matchAndClassify
    default:
        return .matchAndClassify
    }
}

private struct MatchAndClassifyView: View {
    @Bindable var viewModel: ClassificationViewModel
    @Binding var scrollTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MatchAndClassifyToolbar(viewModel: viewModel)
            HSplitView {
                MatchAndClassifyTransactionsPane(viewModel: viewModel, scrollTargetId: $scrollTargetId)
                    .frame(minWidth: 240, idealWidth: 320)
                CandidatesPane(viewModel: viewModel)
                    .frame(minWidth: 220, idealWidth: 320)
                ClassifyAndEmailPane(viewModel: viewModel)
                    .frame(minWidth: 320, idealWidth: 420)
            }
            .accessibilityIdentifier("match-and-classify-split")
            HStack(spacing: 8) {
                if !viewModel.errorText.isEmpty {
                    Text(viewModel.errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("error-banner")
                } else if !viewModel.matchReviewErrorText.isEmpty {
                    Text(viewModel.matchReviewErrorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("match-review-error")
                } else if !viewModel.matchReviewStatusText.isEmpty && viewModel.matchReviewStatusText != "Ready" {
                    Text(viewModel.matchReviewStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("match-review-status")
                } else {
                    Text(viewModel.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("status-text")
                }
                Spacer()
                Button("Load more") { Task { await viewModel.loadMore() } }
                    .disabled(!viewModel.canLoadMore || viewModel.busy)
                    .accessibilityIdentifier("load-more-button")
            }
        }
        .onChange(of: viewModel.matchReviewStateFilter) { _, _ in Task { await viewModel.loadAll() } }
        .onChange(of: viewModel.matchReviewOnlyUnmoved) { _, _ in Task { await viewModel.loadAll() } }
        // #R020: Toggling the Unclassified filter in either direction automatically reloads the list.
        .onChange(of: viewModel.onlyUnclassified) { _, _ in Task { await viewModel.loadAll() } }
        .onChange(of: viewModel.selectedCandidateId) { _, _ in Task { await viewModel.selectedCandidateDidChange() } }
        .onChange(of: viewModel.mailcartSearchQuery) { _, _ in Task { await viewModel.searchMailcartIfNeeded() } }
    }
}

private struct MatchAndClassifyToolbar: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        // #R005: Provide search/filter controls (text search, unclassified toggle, match-state picker,
        // #R005: only-unmoved match toggle) plus a manual Refresh action in the list header.
        HStack(spacing: 8) {
            TextField("Search description / transaction id", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.loadAll() } }
                .accessibilityIdentifier("search-field")
            Toggle("Unclassified", isOn: $viewModel.onlyUnclassified).toggleStyle(.switch)
                .accessibilityIdentifier("only-unclassified-toggle")
            Picker("Match", selection: $viewModel.matchReviewStateFilter) {
                Text("All matches").tag("")
                Text("Unmatched").tag("unmatched")
                Text("No email").tag("no_email")
                Text("Needs review").tag("ai_candidate_uncertain")
                Text("AI confident").tag("ai_match_confident")
                Text("Confirmed").tag("human_confirmed_ai_match")
                Text("Overridden").tag("human_overrode_ai_match")
            }
            .frame(width: 240)
            .accessibilityIdentifier("match-review-state-picker")
            Toggle("Only unmoved", isOn: $viewModel.matchReviewOnlyUnmoved)
                .accessibilityIdentifier("match-review-only-unmoved-toggle")
            Spacer()
            Button("Refresh") { Task { await viewModel.loadAll() } }
                .accessibilityIdentifier("refresh-button")
        }
    }
}

private struct MatchAndClassifyTransactionsPane: View {
    @Bindable var viewModel: ClassificationViewModel
    @Binding var scrollTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Transactions")
                    .font(.headline)
                Spacer()
                if viewModel.busy {
                    ProgressView().controlSize(.small)
                }
                Text("\(viewModel.transactions.count) / \(viewModel.totalTransactions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // SwiftUI's ScrollViewReader does not reliably scroll `List` on macOS 14
            // (Apple Developer Forum #758880), so the transaction list is a
            // ScrollView + LazyVStack bound to `.scrollPosition(id:anchor:)` which gives
            // us a reliable programmatic scroll-to-target handle for #R025.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.transactions.enumerated()), id: \.element.transaction_id) { idx, row in
                        UnifiedTransactionRowView(
                            row: row,
                            isSelected: viewModel.selection.contains(row.transaction_id),
                            saveState: viewModel.rowState[row.transaction_id] ?? .idle,
                            alternating: idx % 2 == 1,
                            onTap: {
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
                        )
                        .id(row.transaction_id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTargetId, anchor: .center)
            .accessibilityIdentifier("transaction-list")
            // #R025: Programmatic selection changes scroll the newly-selected row into view (e.g.,
            // #R025: when the user triggers Next Unclassified via Cmd+]).
            // #R050: Manual row selection in long lists must not force re-centering and yank scroll.
            .onChange(of: viewModel.selection) { _, newValue in
                guard let target = newValue.first else { return }
                guard viewModel.consumePendingScrollSelectionTransactionId() == target else { return }
                if detectAppLaunchMode() == .uiTesting {
                    scrollTargetId = target
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollTargetId = target
                    }
                }
            }
        }
        .padding(8)
    }
}

/// Each transaction row in the unified Match & Classify left pane carries badges for both its
/// classification status AND its email-match status, plus the "N emails" hint when matchy linked
/// multiple emails to one charge.
private struct UnifiedTransactionRowView: View {
    let row: TransactionRow
    let isSelected: Bool
    let saveState: SaveState
    let alternating: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.description).lineLimit(1).font(.body.weight(.medium))
                    .accessibilityIdentifier("transaction-description-\(row.transaction_id)")
                Spacer()
                Text(row.amount as NSNumber, formatter: amountFormatter).monospacedDigit()
                    .accessibilityIdentifier("transaction-amount-\(row.transaction_id)")
            }
            HStack(spacing: 6) {
                Text(row.date).foregroundStyle(.secondary).lineLimit(1)
                if let match = row.match {
                    StateBadge(state: match.state, selectedBy: match.selected_by)
                    if let confidence = match.ai_confidence {
                        ConfidencePill(confidence: confidence)
                    }
                    if match.match_count > 1 {
                        EmailCountBadge(count: match.match_count)
                    }
                } else {
                    Text("unmatched")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                SaveStateDot(state: saveState)
            }.font(.caption)
            HStack(spacing: 6) {
                Text(row.classification?.display_label ?? "Unclassified")
                    .font(.caption)
                    .foregroundStyle(row.classification == nil ? Color.secondary : Color.blue)
                    .lineLimit(1)
                    .accessibilityIdentifier("transaction-classification-\(row.transaction_id)")
                Spacer()
            }
            Text("txn \(row.transaction_id)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityIdentifier("transaction-row-\(row.transaction_id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowAccessibilityLabel: String {
        let category = row.classification?.display_label ?? "Unclassified"
        return "\(row.description), \(category), transaction \(row.transaction_id)"
    }

    private var rowBackground: some View {
        Group {
            if isSelected { Color.accentColor.opacity(0.25) }
            else if alternating { Color.primary.opacity(0.04) }
            else { Color.clear }
        }
    }
}

private struct EmailCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) emails")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.18))
            .foregroundStyle(Color.purple)
            .clipShape(Capsule())
            .accessibilityIdentifier("match-email-count-badge")
    }
}

private struct StateBadge: View {
    let state: String
    let selectedBy: String

    var body: some View {
        Text(stateLabel(state, selectedBy: selectedBy))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor(state).opacity(0.18))
            .foregroundStyle(stateColor(state))
            .clipShape(Capsule())
            .accessibilityIdentifier("match-state-badge-\(state)")
    }

    private func stateLabel(_ state: String, selectedBy: String) -> String {
        switch state {
        case "ai_no_match_found":
            return selectedBy == "human" ? "no email" : "unmatched"
        case "ai_candidate_uncertain": return "uncertain"
        case "ai_match_confident": return "AI match"
        case "human_confirmed_ai_match": return "confirmed"
        case "human_overrode_ai_match": return "overridden"
        default: return state
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ai_match_confident": return .blue
        case "ai_candidate_uncertain": return .orange
        case "ai_no_match_found": return .gray
        case "human_confirmed_ai_match": return .green
        case "human_overrode_ai_match": return .purple
        default: return .secondary
        }
    }
}

private struct ConfidencePill: View {
    let confidence: Double

    var body: some View {
        Text(String(format: "AI %.0f%%", confidence * 100))
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.16))
            .foregroundStyle(.primary)
            .clipShape(Capsule())
    }
}

private struct CandidatesPane: View {
    @Bindable var viewModel: ClassificationViewModel

    // The full set of email_message_ids matchy has actively linked to the selected transaction.
    // When matchy ties multiple emails to one transaction, every one of them should render with
    // the "active" badge in the candidates list — not just the single representative match row.
    private var activeMatchEmailIds: Set<String> { viewModel.activeEmailIdsForSelectedTransaction }

    /// Compact badge label for an "active" candidate that reflects whether the human or the AI
    /// chose it (so the user can see at a glance whether their `Confirm` click stuck).
    private var activeBadgeLabel: String {
        switch viewModel.selectedTransactionMatch?.state {
        case "human_confirmed_ai_match": return "confirmed"
        case "human_overrode_ai_match":  return "overridden"
        case "ai_match_confident":       return "AI match"
        case "ai_candidate_uncertain":   return "uncertain"
        default:                         return "active"
        }
    }

    private var activeBadgeColor: Color {
        switch viewModel.selectedTransactionMatch?.state {
        case "human_confirmed_ai_match": return .green
        case "human_overrode_ai_match":  return .purple
        case "ai_match_confident":       return .blue
        case "ai_candidate_uncertain":   return .orange
        default:                         return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Candidates")
                    .font(.headline)
                Spacer()
                if viewModel.candidatesBusy {
                    ProgressView().controlSize(.small)
                }
                Text("\(viewModel.candidates.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !viewModel.candidatesErrorText.isEmpty {
                Text(viewModel.candidatesErrorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("candidates-error")
            }
            List(selection: $viewModel.selectedCandidateId) {
                Section {
                    if viewModel.candidates.isEmpty && !viewModel.candidatesBusy {
                        Text(viewModel.selectedMatchId == nil ? "Select a transaction on the left to see candidates."
                                                              : "No candidates recorded for this transaction.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.candidates) { candidate in
                            CandidateRowView(candidate: candidate,
                                             isActiveMatch: activeMatchEmailIds.contains(candidate.email_message_id),
                                             activeBadgeLabel: activeBadgeLabel,
                                             activeBadgeColor: activeBadgeColor)
                                .tag(Optional(candidate.email_message_id))
                                .accessibilityIdentifier("candidate-row-\(candidate.email_message_id)")
                        }
                    }
                }
                Section("Search Email") {
                    TextField("Subject, sender, or keyword", text: $viewModel.mailcartSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mailcart-search-field")
                    if !viewModel.mailcartSearchErrorText.isEmpty {
                        Text(viewModel.mailcartSearchErrorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if viewModel.mailcartSearchBusy {
                        HStack { ProgressView().controlSize(.small); Text("Searching…").font(.caption) }
                    }
                    ForEach(viewModel.mailcartSearchResults) { hit in
                        SearchHitRowView(hit: hit)
                            .tag(Optional(hit.email_message_id))
                            .accessibilityIdentifier("mailcart-hit-row-\(hit.email_message_id)")
                    }
                }
            }
            .accessibilityIdentifier("candidates-list")
        }
        .padding(8)
    }
}

private struct CandidateRowView: View {
    let candidate: MatchCandidateRow
    let isActiveMatch: Bool
    let activeBadgeLabel: String
    let activeBadgeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(candidate.subject ?? candidate.email_message_id)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if candidate.is_selected_by_ai {
                    Text("AI pick")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
                if isActiveMatch {
                    Text(activeBadgeLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(activeBadgeColor.opacity(0.22))
                        .foregroundStyle(activeBadgeColor)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("candidate-active-badge-\(activeBadgeLabel)")
                }
            }
            HStack(spacing: 6) {
                Text(candidate.from ?? "unknown sender")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let received = candidate.email_received_at {
                    Text("• \(formattedDateString(received))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(String(format: "rank %.2f", candidate.score))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if candidate.is_unmatched_email_priority {
                    Text("priority")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let error = candidate.mailcart_error {
                    Text("• \(error)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            if let snippet = candidate.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SearchHitRowView: View {
    let hit: EmailSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.subject ?? hit.email_message_id)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(hit.from ?? "unknown sender")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let received = hit.received_at {
                    Text("• \(formattedDateString(received))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let snippet = hit.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Right pane: classification typeahead at the top (the workflow's terminal goal), email body in
/// the middle (the evidence that informs the classification decision), match actions at the bottom.
/// The user's stated workflow: read the email to figure out the category, pick a category,
/// then optionally confirm/override/no-email the email match.
private struct ClassifyAndEmailPane: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClassifySection(viewModel: viewModel)
                .zIndex(1)
            Divider()
            EmailSection(viewModel: viewModel)
                .frame(maxHeight: .infinity)
                .layoutPriority(-1)
                .clipped()
            Divider()
            MatchActionsBar(viewModel: viewModel)
        }
        .padding(8)
    }
}

private struct ClassifySection: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        // #R015: The classification picker drives apply/clear actions for the currently selected
        // #R015: transaction(s) so the user can classify directly from the same pane that shows
        // #R015: the email evidence.
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Classify").font(.headline)
                Spacer()
                Text("\(viewModel.selection.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("selection-count")
            }
            CategoryTypeaheadField(
                selectedCategoryId: $viewModel.selectedCategoryId,
                categories: viewModel.categories,
                hasSelection: !viewModel.selection.isEmpty,
                showsMixedSelection: viewModel.selectionHasMixedCategories
            ) { committedCategoryId in
                await viewModel.selectedCategoryDidChange(committedCategoryId: committedCategoryId)
            }
            Group {
                HStack(spacing: 8) {
                    Button("Apply to Selected") { Task { await viewModel.saveSelection() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(viewModel.selection.isEmpty || viewModel.selectedCategoryId == nil)
                        .accessibilityIdentifier("apply-selected-button")
                    Button("Clear") { Task { await viewModel.clearSelectionClassification() } }
                        .disabled(viewModel.selection.isEmpty)
                        .accessibilityIdentifier("clear-selection-button")
                    Spacer()
                    if let selected = viewModel.primaryTransaction {
                        if let klass = selected.classification {
                            Text("Current: \(klass.display_label)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .accessibilityIdentifier("selected-assigned-category")
                        }
                        // #R030: Detail pane header includes the selected transaction identifier.
                        Text("Transaction \(selected.transaction_id)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("selected-transaction-header")
                    }
                }
            }
        }
    }
}

private struct EmailSection: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Email").font(.headline)
                Spacer()
                if viewModel.emailBusy { ProgressView().controlSize(.small) }
            }
            if !viewModel.emailErrorText.isEmpty {
                Text(viewModel.emailErrorText)
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("email-error")
            }
            if let email = viewModel.selectedEmail {
                EmailHeaderView(email: email)
                Divider()
                EmailBodyContent(email: email, scrollToAmount: viewModel.primaryTransaction?.amount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selection.count > 1 {
                ContentUnavailableView("Multi-select \(viewModel.selection.count) transactions",
                                       systemImage: "rectangle.stack.fill",
                                       description: Text("Pick a category above to apply it to all selected transactions; clear selection to view email evidence per transaction."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.primaryTransaction != nil {
                ContentUnavailableView("Select an email to view body",
                                       systemImage: "envelope",
                                       description: Text("Pick a candidate or search result from the middle pane."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a transaction",
                                       systemImage: "square.grid.2x2",
                                       description: Text("Pick a transaction from the left pane to see its email candidates and classify it."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct EmailHeaderView: View {
    let email: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(email.subject ?? email.email_message_id)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .accessibilityIdentifier("email-subject")
            HStack(spacing: 8) {
                if let from = email.from { Text("From: \(from)").font(.caption) }
                if let to = email.to { Text("To: \(to)").font(.caption) }
                if let received = email.received_at {
                    Text("• \(formattedDateString(received))").font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            Text("id: \(email.email_message_id)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// #R035: Scroll the email body pane so the selected transaction amount is visible after load.
private struct EmailBodyContent: View {
    let email: EmailMessage
    let scrollToAmount: Decimal?

    var body: some View {
        if let html = email.html_body, !html.isEmpty {
            EmailBodyWebView(htmlBody: html, scrollToAmount: scrollToAmount)
                .accessibilityIdentifier("email-body-html")
        } else if let text = email.text_body, !text.isEmpty {
            EmailBodyTextScrollView(text: text, scrollToAmount: scrollToAmount)
                .accessibilityIdentifier("email-body-text")
        } else {
            ContentUnavailableView("Empty body", systemImage: "doc.text",
                                   description: Text("Mailcart returned no html_body or text_body for this message."))
        }
    }
}

private struct EmailBodyTextScrollView: View {
    let text: String
    let scrollToAmount: Decimal?

    private static let amountLineScrollId = "teller-amount-line"

    var body: some View {
        let amountLineIndex = scrollToAmount.flatMap { bestTextLineIndexForAmount(in: text, amount: $0) }
        let lines = text.components(separatedBy: .newlines)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index == amountLineIndex ? Self.amountLineScrollId : "line-\(index)")
                    }
                }
                .padding(8)
            }
            .onAppear {
                scrollToAmountLine(proxy: proxy, amountLineIndex: amountLineIndex)
            }
            .onChange(of: scrollToAmount) { _, _ in
                let index = scrollToAmount.flatMap { bestTextLineIndexForAmount(in: text, amount: $0) }
                scrollToAmountLine(proxy: proxy, amountLineIndex: index)
            }
            .onChange(of: text) { _, _ in
                let index = scrollToAmount.flatMap { bestTextLineIndexForAmount(in: text, amount: $0) }
                scrollToAmountLine(proxy: proxy, amountLineIndex: index)
            }
        }
    }

    private func scrollToAmountLine(proxy: ScrollViewProxy, amountLineIndex: Int?) {
        guard amountLineIndex != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(Self.amountLineScrollId, anchor: .center)
        }
    }
}

private struct MatchActionsBar: View {
    @Bindable var viewModel: ClassificationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Override email message id (optional override)", text: $viewModel.matchOverrideEmailMessageId)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("override-email-message-id-field")
            }
            HStack(spacing: 8) {
                TextField("Note (optional)", text: $viewModel.matchOverrideNote)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("override-note-field")
            }
            HStack(spacing: 8) {
                Button("Confirm") { Task { await viewModel.confirmSelectedMatch() } }
                    .disabled(!viewModel.canConfirmSelectedMatch)
                    .accessibilityIdentifier("match-confirm-button")
                Button("Override with this email") { Task { await viewModel.overrideSelectedMatch() } }
                    .disabled(!viewModel.canOverrideSelectedMatch)
                    .accessibilityIdentifier("match-override-button")
                Button("Mark no-email") { Task { await viewModel.markSelectedMatchNoEmail() } }
                    .disabled(!viewModel.canMarkSelectedMatchNoEmail)
                    .accessibilityIdentifier("match-no-email-button")
                // #R045: Clear match control sits to the right of Mark no-email in the action bar.
                Button("Clear") { Task { await viewModel.clearSelectedMatch() } }
                    .disabled(!viewModel.canClearSelectedMatch)
                    .accessibilityIdentifier("match-clear-button")
                Spacer()
            }
        }
    }
}

private final class NonFocusStealingWebView: WKWebView {
    private var userActivated = false

    override var acceptsFirstResponder: Bool { userActivated }

    override func mouseDown(with event: NSEvent) {
        userActivated = true
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
}

private struct EmailBodyWebView: NSViewRepresentable {
    let htmlBody: String
    let scrollToAmount: Decimal?

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollToAmount: scrollToAmount)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = NonFocusStealingWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadedHTML = htmlBody
        webView.loadHTMLString(wrappedEmailHTML(htmlBody), baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.scrollToAmount = scrollToAmount
        if context.coordinator.loadedHTML != htmlBody {
            context.coordinator.loadedHTML = htmlBody
            nsView.loadHTMLString(wrappedEmailHTML(htmlBody), baseURL: nil)
        } else if scrollToAmount != nil {
            context.coordinator.scrollToAmount(in: nsView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var scrollToAmount: Decimal?

        init(scrollToAmount: Decimal?) {
            self.scrollToAmount = scrollToAmount
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            _ = navigation
            scrollToAmount(in: webView)
        }

        func scrollToAmount(in webView: WKWebView) {
            guard let amount = scrollToAmount else { return }
            let variants = amountSearchVariants(for: amount)
            guard let script = scrollToAmountJavaScript(variants: variants) else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

private func formattedDateString(_ raw: String) -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
    return raw
}

private struct CategoryManagerView: View {
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

private struct SaveStateDot: View {
    let state: SaveState
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
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
