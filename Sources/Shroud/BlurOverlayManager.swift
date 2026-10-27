
import AppKit
import Foundation

@MainActor
final class BlurOverlayManager {

    // MARK: - Properties

    // Keep strong references to overlay windows.
    private var windows: [NSWindow] = []

    private(set) var isVisible = false

    // MARK: - Adjustable Opacity

    var opacity: Double = 0.92 {
        didSet {
            let clamped = min(max(opacity, 0.6), 1.0)

            if opacity != clamped {
                opacity = clamped
                return
            }

            // Update all currently visible overlays.
            for window in windows {
                window.backgroundColor =
                    NSColor.black.withAlphaComponent(opacity)
            }
        }
    }

    // MARK: - Show Privacy Overlay

    func show() {
        guard !isVisible else {
            return
        }

        // Remove any previous overlay windows.
        hide()

        // Create one privacy window per connected display.
        for screen in NSScreen.screens {

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            // Position window on the corresponding monitor.
            window.setFrame(
                screen.frame,
                display: true
            )

            // Keep overlay above normal application windows.
            window.level = .screenSaver

            // Apply the configured opacity.
            window.backgroundColor =
                NSColor.black.withAlphaComponent(opacity)

            window.isOpaque = false
            window.hasShadow = false

            // Allow mouse input to pass through.
            window.ignoresMouseEvents = true

            // Support multiple Spaces and full-screen apps.
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary
            ]

            // MARK: - Overlay Content

            let content = NSView(
                frame: NSRect(
                    origin: .zero,
                    size: screen.frame.size
                )
            )

            let title = NSTextField(
                labelWithString: "SHROUD"
            )

            title.font = .boldSystemFont(ofSize: 32)
            title.textColor = .white
            title.alignment = .center
            title.translatesAutoresizingMaskIntoConstraints = false

            let subtitle = NSTextField(
                labelWithString: "Privacy protection active"
            )

            subtitle.font = .systemFont(ofSize: 14)
            subtitle.textColor = .lightGray
            subtitle.alignment = .center
            subtitle.translatesAutoresizingMaskIntoConstraints = false

            content.addSubview(title)
            content.addSubview(subtitle)

            NSLayoutConstraint.activate([
                title.centerXAnchor.constraint(
                    equalTo: content.centerXAnchor
                ),

                title.centerYAnchor.constraint(
                    equalTo: content.centerYAnchor,
                    constant: -16
                ),

                subtitle.centerXAnchor.constraint(
                    equalTo: content.centerXAnchor
                ),

                subtitle.topAnchor.constraint(
                    equalTo: title.bottomAnchor,
                    constant: 12
                )
            ])

            window.contentView = content

            // Show without activating Shroud.
            window.orderFrontRegardless()

            windows.append(window)
        }

        isVisible = !windows.isEmpty
    }

    // MARK: - Hide Privacy Overlay

    func hide() {
        guard !windows.isEmpty else {
            isVisible = false
            return
        }

        // Take ownership of the existing windows.
        let oldWindows = windows

        windows = []
        isVisible = false

        // Hide without explicitly closing the windows.
        for window in oldWindows {
            window.orderOut(nil)
        }

        // Keep the references alive until a later
        // main-actor turn to reduce lifecycle issues.
        Task { @MainActor in
            withExtendedLifetime(oldWindows) {}
        }
    }
}
