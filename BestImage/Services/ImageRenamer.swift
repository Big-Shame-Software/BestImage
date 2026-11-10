import Foundation

struct ImageRenameRequest: Sendable {
    let id: UUID
    let sourceURL: URL
    let originalName: String
    let score: Float
}

struct ImageRestoreRequest: Sendable {
    let id: UUID
    let currentURL: URL
    let originalName: String
}

struct ImageRenameResult: Sendable {
    let id: UUID
    let destinationURL: URL?
    let errorDescription: String?
}

enum ImageRenamer {
    private struct Item {
        let id: UUID
        let sourceURL: URL
        let preferredName: String
    }

    private struct Move {
        let item: Item
        let destinationURL: URL
        /// True when the destination is the current name of another file in this batch,
        /// so the file must be moved out of the way first.
        let needsTemporaryHop: Bool
        let temporaryURL: URL
    }

    static func rename(_ requests: [ImageRenameRequest]) -> [ImageRenameResult] {
        perform(requests.map {
            Item(
                id: $0.id,
                sourceURL: $0.sourceURL,
                preferredName: ScoreFilename.preferredName(originalName: $0.originalName, score: $0.score)
            )
        })
    }

    static func restore(_ requests: [ImageRestoreRequest]) -> [ImageRenameResult] {
        perform(requests.map {
            Item(id: $0.id, sourceURL: $0.currentURL, preferredName: $0.originalName)
        })
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func perform(_ items: [Item]) -> [ImageRenameResult] {
        guard !items.isEmpty else { return [] }

        let fileManager = FileManager.default
        let sourceKeys = Set(items.map { key($0.sourceURL) })
        var namesByDirectory: [URL: Set<String>] = [:]
        var results: [ImageRenameResult] = []
        var moves: [Move] = []

        for item in items {
            let directory = item.sourceURL.deletingLastPathComponent().standardizedFileURL
            if namesByDirectory[directory] == nil {
                let existingNames = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
                namesByDirectory[directory] = Set(existingNames.filter { name in
                    !sourceKeys.contains(key(directory.appendingPathComponent(name)))
                }.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
            }

            var usedNames = namesByDirectory[directory] ?? []
            let destinationName = ScoreFilename.uniqueName(preferred: item.preferredName, usedNames: &usedNames)
            namesByDirectory[directory] = usedNames

            let destinationURL = directory.appendingPathComponent(destinationName)

            // Already has exactly this name: nothing to do.
            if destinationURL.path == item.sourceURL.standardizedFileURL.path {
                results.append(ImageRenameResult(id: item.id, destinationURL: destinationURL, errorDescription: nil))
                continue
            }

            moves.append(Move(
                item: item,
                destinationURL: destinationURL,
                needsTemporaryHop: sourceKeys.contains(key(destinationURL)),
                temporaryURL: directory.appendingPathComponent(".bestimage-\(UUID().uuidString).tmp")
            ))
        }

        // Most files are renamed directly. Only files whose new name is another batch file's
        // current name take the temporary hop, which keeps the window for an interrupted
        // rename as small as possible.
        var staged: [Move] = []

        for move in moves {
            do {
                if move.needsTemporaryHop {
                    try fileManager.moveItem(at: move.item.sourceURL, to: move.temporaryURL)
                    staged.append(move)
                } else {
                    try fileManager.moveItem(at: move.item.sourceURL, to: move.destinationURL)
                    results.append(ImageRenameResult(id: move.item.id, destinationURL: move.destinationURL, errorDescription: nil))
                }
            } catch {
                results.append(ImageRenameResult(id: move.item.id, destinationURL: nil, errorDescription: error.localizedDescription))
            }
        }

        for move in staged {
            do {
                try fileManager.moveItem(at: move.temporaryURL, to: move.destinationURL)
                results.append(ImageRenameResult(id: move.item.id, destinationURL: move.destinationURL, errorDescription: nil))
            } catch {
                let restored = (try? fileManager.moveItem(at: move.temporaryURL, to: move.item.sourceURL)) != nil
                let detail = restored
                    ? error.localizedDescription
                    : "\(error.localizedDescription) The file remains at \(move.temporaryURL.path)."
                results.append(ImageRenameResult(id: move.item.id, destinationURL: nil, errorDescription: detail))
            }
        }

        return results
    }
}
