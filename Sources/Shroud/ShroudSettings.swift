
import Foundation
import Combine

@MainActor
final class ShroudSettings: ObservableObject {

    // Values are automatically saved using UserDefaults.

    @Published var yawThreshold: Double {
        didSet {
            UserDefaults.standard.set(
                yawThreshold,
                forKey: "yawThreshold"
            )
        }
    }

    @Published var activationDelay: Double {
        didSet {
            UserDefaults.standard.set(
                activationDelay,
                forKey: "activationDelay"
            )
        }
    }

    @Published var overlayOpacity: Double {
        didSet {
            UserDefaults.standard.set(
                overlayOpacity,
                forKey: "overlayOpacity"
            )
        }
    }

    init() {
        let defaults = UserDefaults.standard

        yawThreshold = defaults.object(
            forKey: "yawThreshold"
        ) as? Double ?? 0.30

        activationDelay = defaults.object(
            forKey: "activationDelay"
        ) as? Double ?? 0.9

        overlayOpacity = defaults.object(
            forKey: "overlayOpacity"
        ) as? Double ?? 0.92
    }
}
