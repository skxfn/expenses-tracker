import SwiftUI

@main
struct ExpensesApp: App {
    private let launchState = AppLaunch.prepare()

    var body: some Scene {
        WindowGroup {
            switch launchState {
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let failure):
                StoreErrorView(failure: failure)
            }
        }
    }
}
