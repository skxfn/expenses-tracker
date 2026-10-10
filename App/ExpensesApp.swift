import SwiftUI

@main
struct ExpensesApp: App {
    private let launchState = AppLaunch.prepare()

    init() {
        UnboundedFont.register()
        CurrencySignFont.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchState {
                case .ready(let container):
                    ContentView()
                        .modelContainer(container)
                case .failed(let failure):
                    StoreErrorView(failure: failure)
                }
            }
            #if DEBUG
            .debugShowcase()
            #endif
        }
    }
}
