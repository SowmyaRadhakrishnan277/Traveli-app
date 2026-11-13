import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device model can build itineraries right now. Safe to call on any iOS version.
enum AIAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }

    static var current: AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This device doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Turn on Apple Intelligence in Settings to get AI itineraries.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The on-device AI model is still downloading.")
            case .unavailable:
                return .unavailable(reason: "The on-device AI model isn't available right now.")
            }
        }
        #endif
        return .unavailable(reason: "AI itineraries need iOS 26 or later with Apple Intelligence.")
    }
}
