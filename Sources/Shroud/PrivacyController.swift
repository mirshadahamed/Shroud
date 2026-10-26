
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

    // MARK: - Update Head Direction

    func update(_ state: GazeState) {

        // Cancel any pending activation.
        activationTask?.cancel()
        activationTask = nil

        // User is facing the screen.
        if state == .facingScreen {
            hide()
            return
        }

        // Only activate for confirmed head turns
        // or when the face is missing.
        guard state == .lookingAway ||
              state == .noFace else {
            return
        }

        // Don't create another overlay if already active.
        guard !isProtected else {
            return
        }

        // Wait briefly to avoid flashing the overlay
        // during normal head movements.
        activationTask = Task { @MainActor in

            do {
                try await Task.sleep(
                    for: .milliseconds(900)
                )
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            show()
        }
    }

    // MARK: - Show Privacy Overlay

    private func show() {

        guard !isProtected else {
            return
        }

        overlay.show()
        isProtected = overlay.isVisible

        guard isProtected else {
            return
        }

        // Cancel any previous recovery timer.
        recoveryTask?.cancel()

        // Safety fallback:
        // Automatically clear the overlay after 5 seconds.
        recoveryTask = Task { @MainActor in

            do {
                try await Task.sleep(
                    for: .seconds(5)
                )
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            hide()
        }
    }

    // MARK: - Hide Privacy Overlay

    func hide() {

        // Cancel pending activation.
        activationTask?.cancel()
        activationTask = nil

        // Cancel the automatic recovery timer.
        recoveryTask?.cancel()
        recoveryTask = nil

        // Only hide if protection is active.
        if isProtected || overlay.isVisible {
            overlay.hide()
        }

        isProtected = false
    }
}
