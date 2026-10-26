
import AppKit
import Foundation

@MainActor
final class BlurOverlayManager {

    // Keep strong references to all overlay windows.
    private var windows: [NSWindow] = []

    private(set) var isVisible = false

    // MARK: - Show Privacy Overlay

    func show() {
        guard !isVisible else {
            return
        }

        // Remove any previous overlay windows.
        hide()

        for screen in NSScreen.screens {

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            // Position each window on its display.
            window.setFrame(
                screen.frame,
                display: true
            )

            // Keep the privacy overlay above normal windows.
            window.level = .screenSaver

            window.backgroundColor =
                NSColor.black.withAlphaComponent(0.92)

            window.isOpaque = false
            window.hasShadow = false

            // Allow mouse events to pass through.
            window.ignoresMouseEvents = true

            // Support Spaces and full-screen applications.
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

            // Show without making Shroud the active app.
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

        // Take ownership of the existing windows before
        // removing them from the active window collection.
        let oldWindows = windows

        windows = []
        isVisible = false

        // Hide the windows without explicitly closing them.
        for window in oldWindows {
            window.orderOut(nil)
        }

        // Keep references alive until a later main-actor turn.
        // This is a defensive lifetime measure while
        // investigating the AppKit crash.
        Task { @MainActor in
            withExtendedLifetime(oldWindows) {}
        }
    }
}
