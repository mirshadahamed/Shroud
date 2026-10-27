
import Foundation
import Combine

@MainActor
final class ShroudSettings: ObservableObject {

    // MARK: - Head-Turn Sensitivity

    @Published var yawThreshold: Double {
        didSet {
            UserDefaults.standard.set(
                yawThreshold,
                forKey: "yawThreshold"
            )
        }
    }

    // MARK: - Activation Delay

    @Published var activationDelay: Double {
        didSet {
            UserDefaults.standard.set(
                activationDelay,
                forKey: "activationDelay"
            )
        }
    }

    // MARK: - Overlay Opacity

    @Published var overlayOpacity: Double {
        didSet {
            UserDefaults.standard.set(
                overlayOpacity,
                forKey: "overlayOpacity"
            )
        }
    }

    // MARK: - Overlay Style

    @Published var overlayStyle: OverlayStyle {
        didSet {
            UserDefaults.standard.set(
                overlayStyle.rawValue,
                forKey: "overlayStyle"
            )
        }
    }

    // MARK: - Initialization

    init() {

        let defaults = UserDefaults.standard

        yawThreshold = min(
            max(
                defaults.object(forKey: "yawThreshold")
                    as? Double ?? 0.30,
                0.10
            ),
            0.60
        )

        activationDelay = min(
            max(
                defaults.object(forKey: "activationDelay")
                    as? Double ?? 0.90,
                0.20
            ),
            2.00
        )

        overlayOpacity = min(
            max(
                defaults.object(forKey: "overlayOpacity")
                    as? Double ?? 0.92,
                0.60
            ),
            1.00
        )

        let savedStyle = defaults.string(
            forKey: "overlayStyle"
        )

        overlayStyle = OverlayStyle(
            rawValue: savedStyle ?? ""
        ) ?? .solidBlack
    }
}
