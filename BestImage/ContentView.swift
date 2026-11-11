import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var section: Section = .score

    private enum Section: String, CaseIterable, Identifiable {
        case score = "Score"
        case crop = "Crop"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            if section == .score {
                dropZone
                if !model.jobs.isEmpty || model.errorMessage != nil { resultsPanel }
            } else {
                CropLibraryView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BestImage")
                .font(.largeTitle.weight(.semibold))
            Text("Score images with Apple Vision, then rename them for quick sorting.")
                .foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 11) {
            if model.jobs.isEmpty && !isDropTargeted {
                // Empty state: brand pixel art is allowed here (styleguide §9).
                PixelDisk(size: 56)
            } else {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.stack")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.primary)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(isDropTargeted ? "Release to score and rename" : "Drop images here")
                .font(.title2.weight(.semibold))
            Text("Files are renamed in place. Sort by Name descending to see the best scores first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Images…", action: model.chooseImages)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 5])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueue(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Images").font(.headline)
                Spacer()
                Text(model.summary).foregroundStyle(.secondary)
            }

            if model.isProcessing {
                ProgressView(value: model.progress).progressViewStyle(.linear)
            }

            if !model.jobs.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.jobs) { job in
                            ImageJobRow(job: job) { model.reveal(job.id) }
                            if job.id != model.jobs.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 270)
            }

            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel Waiting", action: model.cancelRemaining)
                    .disabled(!model.hasQueuedJobs)
                Spacer()
                Button("Restore Original Names", action: model.restoreOriginalNames)
                    .disabled(!model.canRestore)
                Button("Clear Finished", action: model.clearFinished)
                    .disabled(!model.jobs.contains(where: \.isFinished))
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ImageJobRow: View {
    let job: ImageJob
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(job.state == .failed ? Color.red : Color.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            if let score = job.score {
                Text(score, format: .number.sign(strategy: .always()).precision(.fractionLength(3)))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(score >= 0 ? Color.green : Color.orange)
            }
            if job.state == .completed {
                Button(action: reveal) { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            }
        }
        .padding(.vertical, 9)
    }

    private var displayName: String {
        job.state == .completed || job.state == .restored ? job.currentURL.lastPathComponent : job.originalName
    }

    private var detail: String {
        job.errorMessage ?? (job.isUtility ? "\(job.statusMessage) • Vision marked as utility" : job.statusMessage)
    }

    private var icon: String {
        switch job.state {
        case .queued: "clock"
        case .scoring: "viewfinder"
        case .renaming: "pencil.line"
        case .completed: "checkmark.circle.fill"
        case .restored: "arrow.uturn.backward.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var color: Color {
        switch job.state {
        case .queued, .cancelled, .restored: .secondary
        case .scoring, .renaming: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }
}
