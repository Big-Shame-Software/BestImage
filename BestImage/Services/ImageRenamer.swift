import Foundation

struct ImageRenameRequest: Sendable {
    let id: UUID
    let sourceURL: URL
    let originalName: String
    let score: Float
}

struct ImageRenameResult: Sendable {
    let id: UUID
    let destinationURL: URL?
    let errorDescription: String?
}

enum ImageRenamer {
    private struct Move {
        let request: ImageRenameRequest
        let temporaryURL: URL
        let destinationURL: URL
    }

    static func rename(_ requests: [ImageRenameRequest]) -> [ImageRenameResult] {
        guard !requests.isEmpty else { return [] }

        let fileManager = FileManager.default
        let sourcePaths = Set(requests.map { $0.sourceURL.standardizedFileURL.path })
        var namesByDirectory: [URL: Set<String>] = [:]
        var moves: [Move] = []

        for request in requests {
            let directory = request.sourceURL.deletingLastPathComponent().standardizedFileURL
            if namesByDirectory[directory] == nil {
                let existingNames = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
                namesByDirectory[directory] = Set(existingNames.filter { name in
                    !sourcePaths.contains(directory.appendingPathComponent(name).standardizedFileURL.path)
                }.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
            }

            var usedNames = namesByDirectory[directory] ?? []
            let preferred = ScoreFilename.preferredName(
                originalName: request.originalName,
                score: request.score
            )
            let destinationName = ScoreFilename.uniqueName(preferred: preferred, usedNames: &usedNames)
            namesByDirectory[directory] = usedNames

            let temporaryURL = directory.appendingPathComponent(".bestimage-\(UUID().uuidString).tmp")
            let destinationURL = directory.appendingPathComponent(destinationName)
            moves.append(Move(request: request, temporaryURL: temporaryURL, destinationURL: destinationURL))
        }

        var staged: [Move] = []
        var results: [ImageRenameResult] = []

        for move in moves {
            do {
                try fileManager.moveItem(at: move.request.sourceURL, to: move.temporaryURL)
                staged.append(move)
            } catch {
                results.append(ImageRenameResult(
                    id: move.request.id,
                    destinationURL: nil,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        for move in staged {
            do {
                try fileManager.moveItem(at: move.temporaryURL, to: move.destinationURL)
                results.append(ImageRenameResult(
                    id: move.request.id,
                    destinationURL: move.destinationURL,
                    errorDescription: nil
                ))
            } catch {
                let restored = (try? fileManager.moveItem(at: move.temporaryURL, to: move.request.sourceURL)) != nil
                let detail = restored
                    ? error.localizedDescription
                    : "\(error.localizedDescription) The file remains at \(move.temporaryURL.path)."
                results.append(ImageRenameResult(
                    id: move.request.id,
                    destinationURL: nil,
                    errorDescription: detail
                ))
            }
        }

        return results
    }
}
