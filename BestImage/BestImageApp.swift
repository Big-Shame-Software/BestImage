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
        .commands { AboutCommand() }

        WindowGroup("Crop", id: "crop", for: URL.self) { urlBinding in
            if let url = urlBinding.wrappedValue {
                CropWindowView(url: url)
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 1100, height: 820)

        Window("About BestImage", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
    }
}

private struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About BestImage") { openWindow(id: "about") }
        }
    }
}
