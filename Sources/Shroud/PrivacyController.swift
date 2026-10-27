
import Foundation
import Combine

@MainActor
final class PrivacyController: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isProtected = false

    // MARK: - Overlay Manager

    private let overlay = BlurOverlayManager()

    // MARK: - Tasks

    private var activationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    // MARK: - Detection State

    private var lastState: GazeState = .unknown

    // MARK: - Configurable Settings

    private var activationDelay: Duration = .milliseconds(900)

    private let recoveryDelay: Duration = .milliseconds(350)

    // MARK: - Overlay Opacity

    func setOverlayOpacity(_ value: Double) {

        let clamped = min(max(value, 0.6), 1.0)

        overlay.opacity = clamped

        print(
            "Shroud: Overlay opacity set to \(Int(clamped * 100))%"
        )
    }

    // MARK: - Activation Delay

    func setActivationDelay(_ seconds: Double) {

        let clamped = min(max(seconds, 0.2), 2.0)

        activationDelay = .milliseconds(
            Int(clamped * 1000)
        )

        print(
            "Shroud: Activation delay set to \(Int(clamped * 1000)) ms"
        )
    }

    // MARK: - Gaze Updates

    func update(_ state: GazeState) {

        lastState = state

        switch state {

        // MARK: - Facing Screen

        case .facingScreen:

            // Cancel pending privacy activation.
            activationTask?.cancel()
            activationTask = nil

            // Nothing to recover if the overlay is hidden.
            guard isProtected else {
                return
            }

            // Avoid creating duplicate recovery tasks.
            guard recoveryTask == nil else {
                return
            }

            recoveryTask = Task { @MainActor in

                do {
                    try await Task.sleep(
                        for: recoveryDelay
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      lastState == .facingScreen else {
                    return
                }

                hideOverlay()
            }

        // MARK: - Looking Away / No Face

        case .lookingAway, .noFace:

            // Cancel recovery if the user looks away again.
            recoveryTask?.cancel()
            recoveryTask = nil

            // Overlay is already active.
            guard !isProtected else {
                return
            }

            // Avoid duplicate activation tasks.
            guard activationTask == nil else {
                return
            }

            activationTask = Task { @MainActor in

                do {
                    try await Task.sleep(
                        for: activationDelay
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      (
                        lastState == .lookingAway ||
                        lastState == .noFace
                      ) else {
                    return
                }

                activationTask = nil

                overlay.show()

                isProtected = overlay.isVisible
            }

        // MARK: - Unknown State

        case .unknown:

            // Cancel pending transitions until detection
            // produces a reliable state again.
            activationTask?.cancel()
            activationTask = nil

            recoveryTask?.cancel()
            recoveryTask = nil
        }
    }

    // MARK: - Hide Overlay Internally

    private func hideOverlay() {

        recoveryTask?.cancel()
        recoveryTask = nil

        overlay.hide()

        isProtected = false
    }

    // MARK: - Emergency / Manual Hide

    func hide() {

        // Cancel any pending activation.
        activationTask?.cancel()
        activationTask = nil

        // Cancel any pending recovery.
        recoveryTask?.cancel()
        recoveryTask = nil

        lastState = .unknown

        overlay.hide()

        isProtected = false

        print("Shroud: Privacy overlay hidden")
    }
}
