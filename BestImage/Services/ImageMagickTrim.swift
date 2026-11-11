import CoreGraphics
import Foundation
import ImageIO

// Ported from BorderTrim. Uses the ImageMagick `magick` CLI for fuzz-based border trimming.
// Optional: when ImageMagick is missing, the crop sheet still works with Auto-Detect.

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandError: Error, LocalizedError {
    case failed(command: String, stderr: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let stderr, let exitCode):
            "Command failed with exit code \(exitCode): \(command)\n\(stderr)"
        }
    }
}

func runCommand(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let result = CommandResult(
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus
    )

    guard result.exitCode == 0 else {
        let command = ([executable] + arguments).joined(separator: " ")
        throw CommandError.failed(command: command, stderr: result.stderr, exitCode: result.exitCode)
    }
    return result
}

enum ImageMagick {
    static let candidatePaths = [
        "/opt/homebrew/bin/magick",
        "/usr/local/bin/magick",
        "/usr/bin/magick",
    ]

    static func locate() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum TrimBackground: String, CaseIterable, Identifiable {
    /// Let ImageMagick infer the background from the corner pixels.
    case auto = "Auto"
    /// Force the background by framing with 1px of the chosen color before trimming.
    case white = "White"
    case black = "Black"

    var id: String { rawValue }
}

struct ImageMagickTrimmer {
    let magickPath: String

    /// `-trim` only removes pixels matching the corner color, so multi-layer borders need
    /// repeated passes. Returns the crop rect in the input image's pixel coordinates.
    @discardableResult
    func trim(inputURL: URL, outputURL: URL, fuzz: Int, background: TrimBackground = .auto, maxPasses: Int = 15) throws -> CGRect {
        let workingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("working-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: workingURL) }

        let trimArgs = ["-fuzz", "\(fuzz)%", "-format", "%@", "-write", "info:", "-trim", "+repage"]

        var firstPass: [String] = [inputURL.path]
        if background != .auto {
            firstPass += ["-bordercolor", background.rawValue.lowercased(), "-border", "1"]
        }
        firstPass += trimArgs + [workingURL.path]
        let firstOut = try runCommand(magickPath, firstPass)
        guard var rect = Self.parseGeometry(firstOut.stdout) else {
            throw NSError(domain: "BestImage", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse trim geometry: \(firstOut.stdout)",
            ])
        }
        if background != .auto {
            rect.origin.x = max(0, rect.origin.x - 1)
            rect.origin.y = max(0, rect.origin.y - 1)
        }
        if rect.width < 1 || rect.height < 1 {
            rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let passURL = workingURL.deletingPathExtension().appendingPathExtension("pass.png")
        defer { try? FileManager.default.removeItem(at: passURL) }
        for _ in 1..<maxPasses {
            guard let passOut = try? runCommand(magickPath, [workingURL.path] + trimArgs + [passURL.path]),
                  let passRect = Self.parseGeometry(passOut.stdout),
                  passRect.width >= 1, passRect.height >= 1
            else { break }
            if passRect.size == rect.size { break }
            rect.origin.x += passRect.origin.x
            rect.origin.y += passRect.origin.y
            rect.size = passRect.size
            _ = try FileManager.default.replaceItemAt(workingURL, withItemAt: passURL)
        }

        _ = try runCommand(magickPath, [workingURL.path, outputURL.path])
        return rect
    }

    /// Parse ImageMagick page geometry like "400x300+60+60".
    static func parseGeometry(_ string: String) -> CGRect? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.replacingOccurrences(of: "x", with: " ")
            .replacingOccurrences(of: "+", with: " ")
            .split(separator: " ")
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[2], y: parts[3], width: parts[0], height: parts[1])
    }
}

/// One fuzz level's trim result, shown as a suggestion card.
struct TrimSuggestion: Identifiable, Sendable {
    enum Danger: Sendable { case none, warning, severe }

    let id = UUID()
    let fuzz: Int
    let cropRect: CGRect
    let originalSize: CGSize

    var size: CGSize { cropRect.size }

    var removedPercent: Double {
        let removedW = max(0, originalSize.width - size.width) / originalSize.width * 100
        let removedH = max(0, originalSize.height - size.height) / originalSize.height * 100
        return Double(max(removedW, removedH))
    }

    var danger: Danger {
        if removedPercent > 40 { return .severe }
        if removedPercent > 25 { return .warning }
        return .none
    }
}

enum TrimSuggester {
    static let fuzzLevels = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30]

    /// Runs the fuzz scan and keeps one suggestion per distinct crop size.
    static func suggestions(
        for source: URL,
        background: TrimBackground,
        magickPath: String,
        workDirectory: URL
    ) throws -> [TrimSuggestion] {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            throw NSError(domain: "BestImage", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not read image dimensions.",
            ])
        }
        let original = CGSize(width: width, height: height)
        let trimmer = ImageMagickTrimmer(magickPath: magickPath)
        var kept: [TrimSuggestion] = []

        for fuzz in fuzzLevels {
            let outputURL = workDirectory.appendingPathComponent("fuzz-\(fuzz).png")
            guard let rect = try? trimmer.trim(inputURL: source, outputURL: outputURL, fuzz: fuzz, background: background) else {
                continue
            }
            try? FileManager.default.removeItem(at: outputURL)

            // Two results are the same crop when both sides are within 1% (min 2px).
            let tolerance = CGSize(width: max(2, original.width * 0.01), height: max(2, original.height * 0.01))
            let isDuplicate = kept.contains {
                abs($0.size.width - rect.width) <= tolerance.width && abs($0.size.height - rect.height) <= tolerance.height
            }
            guard !isDuplicate else { continue }
            kept.append(TrimSuggestion(fuzz: fuzz, cropRect: rect, originalSize: original))
        }
        return kept
    }
}
