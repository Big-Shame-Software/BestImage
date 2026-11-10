import Foundation
import Testing
@testable import BestImage

struct ImageRenamerTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestimage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ name: String, contents: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func renamesFilesDirectlyAndKeepsContents() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write("photo.jpg", contents: "A", in: folder)

        let results = ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: url, originalName: "photo.jpg", score: 0.5)
        ])

        #expect(results.count == 1)
        #expect(results[0].errorDescription == nil)
        #expect(try names(in: folder) == ["1.500_score+0.500__photo.jpg"])
        let renamed = try String(contentsOf: #require(results[0].destinationURL), encoding: .utf8)
        #expect(renamed == "A")
    }

    @Test func rescoringToSameNameIsANoOp() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write("1.500_score+0.500__photo.jpg", contents: "A", in: folder)

        let results = ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: url, originalName: "photo.jpg", score: 0.5)
        ])

        #expect(results[0].errorDescription == nil)
        #expect(try names(in: folder) == ["1.500_score+0.500__photo.jpg"])
    }

    @Test func neverOverwritesAnUnrelatedExistingFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try write("1.500_score+0.500__photo.jpg", contents: "existing", in: folder)
        let url = try write("photo.jpg", contents: "new", in: folder)

        let results = ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: url, originalName: "photo.jpg", score: 0.5)
        ])

        #expect(results[0].errorDescription == nil)
        #expect(try names(in: folder) == ["1.500_score+0.500__photo__2.jpg", "1.500_score+0.500__photo.jpg"].sorted())
        let existing = try String(contentsOf: folder.appendingPathComponent("1.500_score+0.500__photo.jpg"), encoding: .utf8)
        #expect(existing == "existing")
    }

    @Test func batchWhereOneNewNameIsAnotherFilesCurrentNameLosesNothing() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scored = try write("1.500_score+0.500__a.jpg", contents: "scored", in: folder)
        let plain = try write("a.jpg", contents: "plain", in: folder)

        let results = ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: scored, originalName: "a.jpg", score: 0.1),
            ImageRenameRequest(id: UUID(), sourceURL: plain, originalName: "a.jpg", score: 0.5),
        ])

        #expect(results.allSatisfy { $0.errorDescription == nil })
        #expect(try names(in: folder) == ["1.100_score+0.100__a.jpg", "1.500_score+0.500__a.jpg"])
        #expect(try String(contentsOf: folder.appendingPathComponent("1.100_score+0.100__a.jpg"), encoding: .utf8) == "scored")
        #expect(try String(contentsOf: folder.appendingPathComponent("1.500_score+0.500__a.jpg"), encoding: .utf8) == "plain")
    }

    @Test func missingSourceFailsWithoutAffectingOthers() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = try write("good.jpg", contents: "A", in: folder)
        let missing = folder.appendingPathComponent("missing.jpg")

        let results = ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: missing, originalName: "missing.jpg", score: 0.2),
            ImageRenameRequest(id: UUID(), sourceURL: good, originalName: "good.jpg", score: 0.3),
        ])

        #expect(results.filter { $0.destinationURL == nil }.count == 1)
        #expect(try names(in: folder) == ["1.300_score+0.300__good.jpg"])
    }

    @Test func restoreBringsBackOriginalNames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write("photo.jpg", contents: "A", in: folder)
        let renamed = try #require(ImageRenamer.rename([
            ImageRenameRequest(id: UUID(), sourceURL: url, originalName: "photo.jpg", score: 0.5)
        ]).first?.destinationURL)

        let results = ImageRenamer.restore([
            ImageRestoreRequest(id: UUID(), currentURL: renamed, originalName: "photo.jpg")
        ])

        #expect(results[0].errorDescription == nil)
        #expect(try names(in: folder) == ["photo.jpg"])
    }
}
