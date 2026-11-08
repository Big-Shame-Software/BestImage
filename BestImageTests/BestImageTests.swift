import Foundation
import Testing
@testable import BestImage

struct BestImageTests {
    @Test func signedScoresProduceFinderSortableNames() {
        let high = ScoreFilename.preferredName(originalName: "photo.jpg", score: 0.742)
        let low = ScoreFilename.preferredName(originalName: "photo.jpg", score: -0.183)

        #expect(high == "1.742_score+0.742__photo.jpg")
        #expect(low == "0.817_score-0.183__photo.jpg")
        #expect(high.localizedStandardCompare(low) == .orderedDescending)
    }

    @Test func rescoringReplacesManagedPrefix() {
        let original = ScoreFilename.originalName(from: "1.742_score+0.742__IMG_0042.jpg")
        #expect(original == "IMG_0042.jpg")
        #expect(ScoreFilename.preferredName(originalName: original, score: -0.1) == "0.900_score-0.100__IMG_0042.jpg")
    }

    @Test func collisionsAddIdentifierAtEndOfStem() {
        var used: Set<String> = ["1.500_score+0.500__image.jpg"]
        let result = ScoreFilename.uniqueName(
            preferred: "1.500_score+0.500__image.jpg",
            usedNames: &used
        )
        #expect(result == "1.500_score+0.500__image__2.jpg")
    }

    @Test func collisionsAreCaseInsensitive() {
        var used: Set<String> = ["1.500_score+0.500__image.jpg"]
        let result = ScoreFilename.uniqueName(
            preferred: "1.500_score+0.500__IMAGE.JPG",
            usedNames: &used
        )
        #expect(result == "1.500_score+0.500__IMAGE__2.JPG")
    }

    @Test func longCollisionNamesKeepIdentifierAndExtension() {
        let preferred = ScoreFilename.preferredName(
            originalName: String(repeating: "photo", count: 70) + ".jpeg",
            score: 0.5
        )
        var used = Set([preferred.lowercased()])
        let result = ScoreFilename.uniqueName(preferred: preferred, usedNames: &used)

        #expect(result.utf8.count <= 255)
        #expect(result.hasSuffix("__2.jpeg"))
    }
}
