import AppKit
import UniformTypeIdentifiers

@MainActor
enum PanelCoordinator {
    static func chooseImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Images"
        panel.prompt = "Score and Rename"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : []
    }
}
