
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

    // MARK: - Timing

    private var activationDelay: Duration = .milliseconds(900)
    private let recoveryDelay: Duration = .milliseconds(350)

    // MARK: - Live Overlay Style

    func setOverlayStyle(_ value: OverlayStyle) {
        overlay.style = value

        // Changing styles rebuilds visible windows.
        isProtected = overlay.isVisible
    }

    // MARK: - Live Overlay Opacity

    func setOverlayOpacity(_ value: Double) {
        overlay.opacity = min(max(value, 0.60), 1.0)
    }

    // MARK: - Live Activation Delay

    func setActivationDelay(_ seconds: Double) {
        let clamped = min(max(seconds, 0.20), 2.0)

        activationDelay = .milliseconds(
            Int(clamped * 1000)
        )
    }

    // MARK: - Gaze Updates

    func update(_ state: GazeState) {

        lastState = state

        switch state {

        case .facingScreen:

            activationTask?.cancel()
            activationTask = nil

            guard isProtected,
                  recoveryTask == nil else {
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

        case .lookingAway, .noFace:

            recoveryTask?.cancel()
            recoveryTask = nil

            guard !isProtected,
                  activationTask == nil else {
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

        case .unknown:

            activationTask?.cancel()
            activationTask = nil

            recoveryTask?.cancel()
            recoveryTask = nil
        }
    }

    // MARK: - Internal Hide

    private func hideOverlay() {

        recoveryTask?.cancel()
        recoveryTask = nil

        overlay.hide()
        isProtected = false
    }

    // MARK: - Manual / Emergency Hide

    func hide() {

        activationTask?.cancel()
        activationTask = nil

        recoveryTask?.cancel()
        recoveryTask = nil

        lastState = .unknown

        overlay.hide()
        isProtected = false
    }
}
