import SwiftUI

@main
struct BestImageApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("BestImage") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
