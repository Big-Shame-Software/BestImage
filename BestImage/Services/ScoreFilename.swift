import Foundation

enum ScoreFilename {
    private static let prefixPattern = #"^\d\.\d{3}_score[+-]\d\.\d{3}__"#
    private static let maximumFilenameBytes = 255

    static func originalName(from filename: String) -> String {
        guard let range = filename.range(of: prefixPattern, options: .regularExpression) else {
            return filename
        }
        return String(filename[range.upperBound...])
    }

    static func preferredName(originalName: String, score: Float) -> String {
        let clampedScore = min(1, max(-1, score))
        let scoreText = String(
            format: "%+.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            clampedScore
        )
        let sortableScore = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            clampedScore + 1
        )
        let prefix = "\(sortableScore)_score\(scoreText)__"
        return filenameFittingLimit(prefix: prefix, originalName: originalName)
    }

    static func uniqueName(preferred: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(collisionKey(preferred)).inserted { return preferred }

        let url = URL(fileURLWithPath: preferred)
        let fileExtension = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var copyNumber = 2

        while true {
            let suffix = "__\(copyNumber)"
            let candidate = filenameFittingLimit(
                prefix: "",
                originalName: stem + (fileExtension.isEmpty ? "" : ".\(fileExtension)"),
                protectedStemSuffix: suffix
            )
            if usedNames.insert(collisionKey(candidate)).inserted { return candidate }
            copyNumber += 1
        }
    }

    private static func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func filenameFittingLimit(
        prefix: String,
        originalName: String,
        protectedStemSuffix: String = ""
    ) -> String {
        let url = URL(fileURLWithPath: originalName)
        let fileExtension = url.pathExtension
        var stem = url.deletingPathExtension().lastPathComponent
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"

        while (prefix + stem + protectedStemSuffix + suffix).utf8.count > maximumFilenameBytes, !stem.isEmpty {
            stem.removeLast()
        }

        return prefix + stem + protectedStemSuffix + suffix
    }
}
