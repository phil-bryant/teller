import SwiftUI

private enum AppTab: Hashable {
    case connect
    case manageCategories
    case matchAndClassify
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
        // #R010: Keyboard shortcuts are owned by pane-local controls in MatchAndClassifyView.
        // #R055: Next Unclassified is scoped to Match & Classify by living in that tab's pane.
        // #R060: Undo is scoped to Match & Classify by living in that tab's pane.
        // #R070: Tab order is Connect, Manage Categories, Match & Classify.
        TabView(selection: $selectedTab) {
            ConnectView(viewModel: connectViewModel)
                .padding(12)
                .tabItem { Label("Connect", systemImage: "link.badge.plus") }
                .tag(AppTab.connect)

            CategoryManagerView(viewModel: viewModel)
                .padding(12)
                .tabItem { Label("Manage Categories", systemImage: "square.and.pencil") }
                .tag(AppTab.manageCategories)

            MatchAndClassifyView(viewModel: viewModel, scrollTargetId: $scrollTargetId)
                .padding(12)
                .tabItem { Label("Match & Classify", systemImage: "envelope.badge.shield.half.filled") }
                .tag(AppTab.matchAndClassify)
        }
        .navigationTitle("Transaction Classifier")
        .navigationSplitViewStyle(.balanced)
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
