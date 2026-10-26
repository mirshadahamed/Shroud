
import SwiftUI
import AppKit
import Combine

// MARK: - Application Controller

@MainActor
final class ShroudAppController: ObservableObject {

    let camera = CameraManager()
    let privacy = PrivacyController()

    private var hotkey: GlobalHotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()

        hotkey = GlobalHotkeyManager { [weak self] in
            self?.emergencyStop()
        }

        hotkey?.register()
    }

    // MARK: - Persistent Camera Observation

    private func setupObservers() {

        // Forward camera changes to the SwiftUI menu.
        camera.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward privacy changes to the SwiftUI menu.
        privacy.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Connect gaze detection directly to privacy.
        camera.$gazeState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                if self.camera.isRunning {
                    self.privacy.update(state)
                }
            }
            .store(in: &cancellables)

        // Remove overlay when camera stops.
        camera.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }

                if !running {
                    self.privacy.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start / Stop

    func toggleProtection() {
        if camera.isRunning {
            emergencyStop()
        } else {
            camera.start()
        }
    }

    // MARK: - Emergency Stop

    func emergencyStop() {
        privacy.hide()
        camera.stop()

        print("Shroud: Emergency protection stop")
    }

    // MARK: - Quit

    func quit() {
        emergencyStop()
        hotkey?.unregister()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Shroud Menu Bar App

@main
struct Shroud: App {

    @StateObject private var controller =
        ShroudAppController()

    var body: some Scene {
        MenuBarExtra(
            "Shroud",
            systemImage: controller.camera.isRunning
                ? "eye.fill"
                : "eye"
        ) {
            VStack(alignment: .leading, spacing: 14) {

                // MARK: - Header

                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shroud")
                            .font(.headline)

                        Text("Your screen. Your privacy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                // MARK: - Camera Status

                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            controller.camera.isRunning
                                ? Color.green
                                : Color.gray
                        )
                        .frame(width: 9, height: 9)

                    Text(controller.camera.status)
                        .font(.subheadline)
                }

                // MARK: - Head Detection

                if controller.camera.isRunning {

                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                controller.camera.gazeState == .facingScreen
                                ? "eye.fill"
                                : "eye.slash.fill"
                        )
                        .foregroundStyle(
                            controller.camera.gazeState == .facingScreen
                                ? Color.green
                                : Color.orange
                        )

                        Text(controller.camera.gazeState.rawValue)
                            .font(.subheadline)
                    }
                }

                Divider()

                // MARK: - Protection Controls

                Button {
                    controller.toggleProtection()
                } label: {
                    Label(
                        controller.camera.isRunning
                            ? "Stop Protection"
                            : "Start Protection",
                        systemImage: controller.camera.isRunning
                            ? "pause.circle"
                            : "play.circle"
                    )
                }
                .buttonStyle(.borderedProminent)

                if controller.privacy.isProtected {
                    Button("Clear Privacy Overlay") {
                        controller.privacy.hide()
                    }
                }

                // MARK: - Emergency Stop

                Button {
                    controller.emergencyStop()
                } label: {
                    Label(
                        "Emergency Stop (⌃⌥S)",
                        systemImage: "exclamationmark.shield"
                    )
                }

                Divider()

                // MARK: - Privacy Information

                Label(
                    "Camera processing stays on your Mac",
                    systemImage: "lock.shield"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                Divider()

                // MARK: - Quit

                Button {
                    controller.quit()
                } label: {
                    Label(
                        "Quit Shroud",
                        systemImage: "power"
                    )
                }
            }
            .padding(16)
            .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }
}
