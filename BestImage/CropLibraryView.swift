import SwiftUI
import UniformTypeIdentifiers

/// Crop section: its own list of images. Nothing here is scored or renamed. Cropping opens
/// in a resizable window, and saved cutouts land back in this list.
struct CropLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dropZone
            if !model.cropFiles.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.cropFiles, id: \.self) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 22)
                                Text(url.lastPathComponent)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Crop…") { openWindow(id: "crop", value: url) }
                                    .buttonStyle(.borderedProminent)
                                Button { model.removeCropFile(url) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.borderless)
                                    .help("Remove from list")
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "crop")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.primary)
            Text(isDropTargeted ? "Release to add for cropping" : "Drop images to crop")
                .font(.title3.weight(.semibold))
            Text("Cropping does not score or rename files.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Images…") { model.addCropFiles(PanelCoordinator.chooseImages()) }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.map(\.standardizedFileURL).filter { url in
                guard !url.hasDirectoryPath, let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .image)
            }
            model.addCropFiles(images)
            return !images.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }
}

/// Hosts the crop editor in its own resizable window.
struct CropWindowView: View {
    let url: URL
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CropSheet(
            job: ImageJob(url: url),
            onSaved: { model.addCropFiles([$0]) },
            close: { NSApp.keyWindow?.close() }
        )
    }
}
