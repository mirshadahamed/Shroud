
import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: ShroudSettings

    var body: some View {
        Form {

            Section("Detection") {
                VStack(alignment: .leading) {
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
                }
            }

            Section("Privacy") {
                VStack(alignment: .leading) {
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
                        in: 0.2...2.0,
                        step: 0.1
                    )
                }

                VStack(alignment: .leading) {
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
                        in: 0.6...1.0,
                        step: 0.05
                    )
                }
            }

            Section {
                Text(
                    "Emergency shortcut: Control + Option + S"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 360)
    }
}
