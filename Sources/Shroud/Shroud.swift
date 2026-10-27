
import SwiftUI
import AppKit
import Combine

// MARK: - Application Controller

@MainActor
final class ShroudAppController: ObservableObject {

    let camera = CameraManager()
    let privacy = PrivacyController()
    let settings = ShroudSettings()

    private var hotkey: GlobalHotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()

        hotkey = GlobalHotkeyManager { [weak self] in
            self?.emergencyStop()
        }

        hotkey?.register()
    }

    // MARK: - Persistent Observation

    private func setupObservers() {

        camera.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        privacy.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // MARK: - Camera Gaze Detection

        camera.$gazeState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                if self.camera.isRunning {
                    self.privacy.update(state)
                }
            }
            .store(in: &cancellables)

        // MARK: - Camera Running State

        camera.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }

                if running {
                    // Apply the gaze state captured during startup.
                    self.privacy.update(
                        self.camera.gazeState
                    )
                } else {
                    self.privacy.hide()
                }
            }
            .store(in: &cancellables)

        // MARK: - Head-Turn Sensitivity

        settings.$yawThreshold
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.camera.setYawThreshold(value)
            }
            .store(in: &cancellables)

        // MARK: - Activation Delay

        settings.$activationDelay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.privacy.setActivationDelay(value)
            }
            .store(in: &cancellables)

        // MARK: - Overlay Opacity

        settings.$overlayOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.privacy.setOverlayOpacity(value)
            }
            .store(in: &cancellables)

        // MARK: - Overlay Style

        settings.$overlayStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                self?.privacy.setOverlayStyle(style)
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

// MARK: - Menu Bar Content

private struct ShroudMenuView: View {

    @ObservedObject var controller: ShroudAppController

    @Environment(\.openWindow)
    private var openWindow

    var body: some View {

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

                    Spacer()
                }
            }

            // MARK: - Overlay Status

            if controller.privacy.isProtected {

                Label(
                    "Privacy overlay active",
                    systemImage: "shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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

                Button {
                    controller.privacy.hide()
                } label: {

                    Label(
                        "Clear Privacy Overlay",
                        systemImage: "eye"
                    )
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

            // MARK: - Settings

            Button {

                NSApplication.shared.activate(
                    ignoringOtherApps: true
                )

                openWindow(id: "settings")

            } label: {

                Label(
                    "Settings...",
                    systemImage: "gearshape"
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
}

// MARK: - Shroud App

@main
struct Shroud: App {

    @StateObject private var controller =
        ShroudAppController()

    var body: some Scene {

        // MARK: - Menu Bar

        MenuBarExtra(
            "Shroud",
            systemImage: controller.camera.isRunning
                ? "eye.fill"
                : "eye"
        ) {
            ShroudMenuView(
                controller: controller
            )
        }
        .menuBarExtraStyle(.window)

        // MARK: - Settings Window

        Window(
            "Shroud Settings",
            id: "settings"
        ) {
            SettingsView(
                settings: controller.settings
            )
        }
        .defaultSize(
            width: 480,
            height: 480
        )
    }
}
