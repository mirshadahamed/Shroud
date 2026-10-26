
import SwiftUI
import AppKit

@main
struct Shroud: App {

    @StateObject private var camera = CameraManager()
    @StateObject private var privacy = PrivacyController()

    var body: some Scene {
        MenuBarExtra(
            "Shroud",
            systemImage: camera.isRunning ? "eye.fill" : "eye"
        ) {
            VStack(alignment: .leading, spacing: 14) {

                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text("Shroud")
                            .font(.headline)

                        Text("Your screen. Your privacy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Circle()
                        .fill(camera.isRunning ? .green : .gray)
                        .frame(width: 9, height: 9)

                    Text(camera.status)
                        .font(.subheadline)
                }

                if camera.isRunning {
                    Label(
                        camera.gazeState.rawValue,
                        systemImage: camera.gazeState == .facingScreen
                            ? "eye.fill"
                            : "eye.slash.fill"
                    )
                    .font(.subheadline)
                }

                Divider()

                Button {
                    if camera.isRunning {
                        privacy.hide()
                        camera.stop()
                    } else {
                        camera.start()
                    }
                } label: {
                    Label(
                        camera.isRunning
                            ? "Stop Protection"
                            : "Start Protection",
                        systemImage: camera.isRunning
                            ? "pause.circle"
                            : "play.circle"
                    )
                }
                .buttonStyle(.borderedProminent)

                if privacy.isProtected {
                    Button("Clear Privacy Overlay") {
                        privacy.hide()
                    }
                }

                Divider()

                Button("Quit Shroud") {
                    privacy.hide()
                    camera.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(16)
            .frame(width: 300)
            .onChange(of: camera.gazeState) { _, state in
                if camera.isRunning {
                    privacy.update(state)
                }
            }
            .onChange(of: camera.isRunning) { _, running in
                if !running {
                    privacy.hide()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
