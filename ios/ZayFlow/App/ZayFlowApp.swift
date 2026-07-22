import SwiftUI

@main
struct ZayFlowApp: App {
    @State private var model: AppModel

    init() {
        do {
            let database = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? try AppDatabase.inMemory()
                : try AppDatabase.live()
            _model = State(initialValue: try AppModel(database: database))
        } catch {
            fatalError("Unable to start ZayFlow: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(ZayFlowTheme.brand)
        }
    }
}
