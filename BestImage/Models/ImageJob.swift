import Foundation

struct ImageJob: Identifiable, Sendable {
    enum State: Sendable {
        case queued
        case scoring
        case renaming
        case completed
        case restored
        case failed
        case cancelled
    }

    let id: UUID
    let sourceURL: URL
    let originalName: String
    var currentURL: URL
    var score: Float?
    var isUtility = false
    var state: State = .queued
    var statusMessage = "Waiting"
    var errorMessage: String?

    init(url: URL) {
        id = UUID()
        sourceURL = url
        currentURL = url
        originalName = ScoreFilename.originalName(from: url.lastPathComponent)
    }

    var isFinished: Bool {
        state == .completed || state == .restored || state == .failed || state == .cancelled
    }
}
