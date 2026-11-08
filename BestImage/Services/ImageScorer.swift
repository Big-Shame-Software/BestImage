import Foundation
import Vision

struct ImageVisionScore: Sendable {
    let overall: Float
    let isUtility: Bool
}

enum ImageScorer {
    static func score(_ url: URL) async throws -> ImageVisionScore {
        try await Task.detached(priority: .userInitiated) {
            let request = VNCalculateImageAestheticsScoresRequest()
            request.revision = VNCalculateImageAestheticsScoresRequestRevision1
            let handler = VNImageRequestHandler(url: url, options: [:])
            try handler.perform([request])

            guard let observation = request.results?.first as? VNImageAestheticsScoresObservation else {
                throw BestImageError.noAestheticsScore
            }

            return ImageVisionScore(
                overall: observation.overallScore,
                isUtility: observation.isUtility
            )
        }.value
    }
}
