
import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: ShroudSettings

    @StateObject private var loginItem = LoginItemManager()

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                loginItem.isEnabled
            },
            set: { newValue in
                loginItem.setEnabled(newValue)
            }
        )
    }

    var body: some View {

        Form {

            // MARK: - Detection

            Section("Detection") {

                VStack(alignment: .leading, spacing: 10) {

                    HStack {
                        Text("Head-turn sensitivity")

                        Spacer()

                        Text(
                            settings.yawThreshold,
                            format: .number.precision(
                                .fractionLength(2)
                            )
                        )
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.yawThreshold,
                        in: 0.10...0.60,
                        step: 0.05
                    )

                    Text(
                        "Lower values detect smaller head turns."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // MARK: - Privacy Appearance

            Section("Privacy Appearance") {

                Picker(
                    "Overlay style",
                    selection: $settings.overlayStyle
                ) {
                    ForEach(OverlayStyle.allCases) { style in
                        Text(style.title)
                            .tag(style)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 10) {

                    HStack {
                        Text("Overlay opacity")

                        Spacer()

                        Text(
                            "\(Int(settings.overlayOpacity * 100))%"
                        )
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.overlayOpacity,
                        in: 0.60...1.00,
                        step: 0.05
                    )
                }

                Text(overlayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Protection Timing

            Section("Protection Timing") {

                VStack(alignment: .leading, spacing: 10) {

                    HStack {
                        Text("Activation delay")

                        Spacer()

                        Text(
                            "\(Int(settings.activationDelay * 1000)) ms"
                        )
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.activationDelay,
                        in: 0.20...2.00,
                        step: 0.10
                    )
                }
            }

            // MARK: - Startup

            Section("Startup") {

                Toggle(
                    "Launch Shroud at Login",
                    isOn: launchAtLoginBinding
                )

                Text(
                    "Automatically open Shroud in the menu bar when you sign in. Camera protection remains off until you start it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let errorMessage = loginItem.errorMessage {

                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }

            // MARK: - Emergency Shortcut

            Section("Emergency Protection") {

                Label(
                    "Emergency shortcut: Control + Option + S",
                    systemImage: "keyboard"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(
            width: 500,
            height: 540
        )
        .onAppear {
            loginItem.refresh()
        }
    }

    // MARK: - Style Description

    private var overlayDescription: String {

        switch settings.overlayStyle {

        case .solidBlack:
            return "A dark overlay for stronger visual privacy."

        case .darkFrosted:
            return "Native macOS blur with a dark tint. More translucent than solid black."

        case .liquidGlass:
            return "A light, Apple-inspired glass appearance. Less suitable for sensitive content."
        }
    }
}
