import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var jobs: [ImageJob] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isProcessing = false
    @Published private(set) var isRestoring = false

    private var batchTask: Task<Void, Never>?

    deinit { batchTask?.cancel() }

    var hasQueuedJobs: Bool { jobs.contains { $0.state == .queued } }
    var completedCount: Int { jobs.count { $0.state == .completed } }
    var restoredCount: Int { jobs.count { $0.state == .restored } }
    var failedCount: Int { jobs.count { $0.state == .failed } }
    var canRestore: Bool { !isProcessing && !isRestoring && completedCount > 0 }

    var progress: Double {
        guard !jobs.isEmpty else { return 0 }
        return Double(jobs.count(where: \.isFinished)) / Double(jobs.count)
    }

    var summary: String {
        if jobs.isEmpty { return "No images yet" }
        if isProcessing { return "\(completedCount) of \(jobs.count) renamed" }
        if completedCount == 0, restoredCount > 0, failedCount == 0 { return "\(restoredCount) restored" }
        if failedCount > 0 { return "\(completedCount) renamed • \(failedCount) failed" }
        return "\(completedCount) image\(completedCount == 1 ? "" : "s") renamed"
    }

    func chooseImages() {
        enqueue(PanelCoordinator.chooseImages())
    }

    func enqueue(_ urls: [URL]) {
        var acceptedPaths = Set(jobs.map { $0.sourceURL.standardizedFileURL.path })
        var added = 0
        var rejected = 0

        for droppedURL in urls {
            let url = droppedURL.standardizedFileURL
            guard url.isFileURL, !url.hasDirectoryPath, isSupportedImage(url) else {
                rejected += 1
                continue
            }
            guard acceptedPaths.insert(url.path).inserted else { continue }
            jobs.append(ImageJob(url: url))
            added += 1
        }

        if added > 0 {
            errorMessage = rejected == 0 ? nil : "Skipped \(rejected) unsupported item\(rejected == 1 ? "" : "s")."
            startProcessingIfNeeded()
        } else if !urls.isEmpty {
            errorMessage = "No new supported image files were added."
        }
    }

    func cancelRemaining() {
        for index in jobs.indices where jobs[index].state == .queued {
            jobs[index].state = .cancelled
            jobs[index].statusMessage = "Cancelled"
        }
    }

    func clearFinished() {
        jobs.removeAll(where: \.isFinished)
        errorMessage = nil
    }

    func reveal(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID && $0.state == .completed }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([job.currentURL])
    }

    /// Puts every renamed file back to its original name.
    func restoreOriginalNames() {
        guard canRestore else { return }
        let requests = jobs.filter { $0.state == .completed }.map {
            ImageRestoreRequest(id: $0.id, currentURL: $0.currentURL, originalName: $0.originalName)
        }
        isRestoring = true
        errorMessage = nil

        Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                ImageRenamer.restore(requests)
            }.value
            guard let self else { return }
            for result in results {
                guard let index = jobs.firstIndex(where: { $0.id == result.id }) else { continue }
                if let destination = result.destinationURL {
                    jobs[index].currentURL = destination
                    jobs[index].state = .restored
                    jobs[index].statusMessage = "Original name restored"
                    jobs[index].errorMessage = nil
                } else {
                    jobs[index].errorMessage = result.errorDescription
                    jobs[index].statusMessage = "Restore failed"
                }
            }
            isRestoring = false
            startProcessingIfNeeded()
        }
    }

    private func startProcessingIfNeeded() {
        guard batchTask == nil, !isRestoring, hasQueuedJobs else { return }
        isProcessing = true
        batchTask = Task { [weak self] in await self?.processBatch() }
    }

    private func processBatch() async {
        while !Task.isCancelled {
            let batchIDs = jobs.filter { $0.state == .queued }.map(\.id)
            guard !batchIDs.isEmpty else { break }

            for id in batchIDs where !Task.isCancelled {
                await score(id)
            }

            let requests = batchIDs.compactMap { id -> ImageRenameRequest? in
                guard let job = jobs.first(where: { $0.id == id }),
                      job.state == .renaming,
                      let score = job.score else { return nil }
                return ImageRenameRequest(id: id, sourceURL: job.sourceURL, originalName: job.originalName, score: score)
            }

            let results = await Task.detached(priority: .userInitiated) {
                ImageRenamer.rename(requests)
            }.value
            applyRenameResults(results)
        }

        batchTask = nil
        isProcessing = false
        if hasQueuedJobs { startProcessingIfNeeded() }
    }

    private func score(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let url = jobs[index].sourceURL
        jobs[index].state = .scoring
        jobs[index].statusMessage = "Calculating Vision score"

        do {
            let result = try await ImageScorer.score(url)
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].score = result.overall
            jobs[currentIndex].isUtility = result.isUtility
            jobs[currentIndex].state = .renaming
            jobs[currentIndex].statusMessage = "Ready to rename"
        } catch is CancellationError {
            updateFailure(id, state: .cancelled, message: "Cancelled")
        } catch {
            updateFailure(id, state: .failed, message: error.localizedDescription)
        }
    }

    private func applyRenameResults(_ results: [ImageRenameResult]) {
        for result in results {
            guard let index = jobs.firstIndex(where: { $0.id == result.id }) else { continue }
            if let destination = result.destinationURL {
                jobs[index].currentURL = destination
                jobs[index].state = .completed
                jobs[index].statusMessage = "Renamed"
            } else {
                jobs[index].state = .failed
                jobs[index].statusMessage = "Rename failed"
                jobs[index].errorMessage = result.errorDescription
            }
        }
    }

    private func updateFailure(_ id: UUID, state: ImageJob.State, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
        jobs[index].statusMessage = state == .failed ? "Could not score image" : message
        jobs[index].errorMessage = state == .failed ? message : nil
    }

    private func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
