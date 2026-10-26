
import Foundation
import Combine

@MainActor
final class PrivacyController: ObservableObject {

    @Published private(set) var isProtected = false

    private let overlay = BlurOverlayManager()

    private var activationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    private var lastState: GazeState = .unknown

    // MARK: - Timing

    private let activationDelay: Duration = .milliseconds(900)
    private let recoveryDelay: Duration = .milliseconds(350)

    // MARK: - Gaze Updates

    func update(_ state: GazeState) {
        lastState = state

        switch state {
        case .facingScreen:
            activationTask?.cancel()
            activationTask = nil

            // Require stable facing detection before clearing.
            guard isProtected else { return }

            guard recoveryTask == nil else { return }

            recoveryTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: recoveryDelay)
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

            guard !isProtected else { return }
            guard activationTask == nil else { return }

            activationTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: activationDelay)
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      lastState == .lookingAway ||
                      lastState == .noFace else {
                    return
                }

                activationTask = nil
                overlay.show()
                isProtected = overlay.isVisible
            }

        case .unknown:
            // An unknown measurement should not immediately
            // activate or clear the overlay.
            activationTask?.cancel()
            activationTask = nil

            recoveryTask?.cancel()
            recoveryTask = nil
        }
    }

    // MARK: - Clear Overlay

    private func hideOverlay() {
        recoveryTask?.cancel()
        recoveryTask = nil

        overlay.hide()
        isProtected = false
    }

    // MARK: - Emergency Stop / Manual Clear

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
