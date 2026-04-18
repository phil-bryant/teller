import SwiftUI

@main
struct TellerReclassifierApp: App {
    @State private var viewModel = ReclassificationViewModel()
    var body: some Scene {
        WindowGroup { ContentView(viewModel: viewModel).frame(minWidth: 1120, minHeight: 720) }
    }
}
