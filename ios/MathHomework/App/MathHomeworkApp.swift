import SwiftUI

@main
struct MathHomeworkApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { model.sceneBecameActive() }
                    else if phase == .background { model.sceneEnteredBackground() }
                }
        }
    }
}
