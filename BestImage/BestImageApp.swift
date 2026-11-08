import SwiftUI

@main
struct BestImageApp: App {
    var body: some Scene {
        WindowGroup("BestImage") {
            ContentView()
                .environmentObject(AppModel())
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
