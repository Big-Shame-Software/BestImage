import Foundation

enum BestImageError: LocalizedError {
    case noAestheticsScore

    var errorDescription: String? {
        switch self {
        case .noAestheticsScore:
            "Apple Vision did not return an aesthetics score for this image."
        }
    }
}
