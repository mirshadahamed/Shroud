import AppKit
import Foundation
import QuartzCore

// MARK: - Overlay Styles

enum OverlayStyle: String, CaseIterable, Identifiable {
    case solidBlack
    case darkFrosted
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solidBlack:
            return "Solid Black"
        case .darkFrosted:
            return "Dark Frosted Glass"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }
}

// MARK: - Full-Screen Glass Overlay

@MainActor
final class BlurOverlayManager {

    private var windows: [NSWindow] = []

    private(set) var isVisible = false

    // Size of the floating Liquid Glass card.
    private let cardSize = CGSize(width: 380, height: 240)
    private let cardCornerRadius: CGFloat = 40

    var opacity: Double = 0.92 {
        didSet {
            let clamped = min(max(opacity, 0.60), 1.0)

            if opacity != clamped {
                opacity = clamped
                return
            }

            updateAppearance()
        }
    }

    var style: OverlayStyle = .solidBlack {
        didSet {
            guard oldValue != style else { return }

            if isVisible {
                hide()
                show()
            }
        }
    }

    // MARK: - Show Overlay

    func show() {
        guard !isVisible else { return }

        for screen in NSScreen.screens {
            let window = makeWindow(for: screen)
            window.orderFrontRegardless()
            windows.append(window)
        }

        isVisible = !windows.isEmpty
    }

    // MARK: - Window Creation

    private func makeWindow(for screen: NSScreen) -> NSWindow {

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.setFrame(screen.frame, display: true)
        window.level = .screenSaver

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        let root = NSView(
            frame: NSRect(
                origin: .zero,
                size: screen.frame.size
            )
        )

        root.wantsLayer = true

        switch style {
        case .solidBlack:
            makeSolidBackground(in: root)
            addBranding(to: root)

        case .darkFrosted:
            makeGlassBackground(in: root)
            addBranding(to: root)

        case .liquidGlass:
            makeGlassBackground(in: root)
            makeLiquidGlassCard(in: root)   // branding lives inside the card
        }

        window.contentView = root

        return window
    }

    // MARK: - Solid Black

    private func makeSolidBackground(in root: NSView) {

        let background = NSView(frame: root.bounds)

        background.identifier =
            NSUserInterfaceItemIdentifier("ShroudSolidBackground")

        background.autoresizingMask = [
            .width,
            .height
        ]

        background.wantsLayer = true

        background.layer?.backgroundColor =
            NSColor.black
                .withAlphaComponent(opacity)
                .cgColor

        root.addSubview(background)
    }

    // MARK: - Full-Screen Glass

    private func makeGlassBackground(in root: NSView) {

        // Native macOS background blur.
        let glass = NSVisualEffectView(frame: root.bounds)

        glass.identifier =
            NSUserInterfaceItemIdentifier("ShroudGlassBackground")

        glass.autoresizingMask = [
            .width,
            .height
        ]

        glass.blendingMode = .behindWindow
        glass.state = .active

        glass.material = style == .darkFrosted
            ? .hudWindow
            : .underWindowBackground

        root.addSubview(glass)

        // Tint layer.
        let tint = NSView(frame: root.bounds)

        tint.identifier =
            NSUserInterfaceItemIdentifier("ShroudGlassTint")

        tint.autoresizingMask = [
            .width,
            .height
        ]

        tint.wantsLayer = true

        tint.layer?.backgroundColor =
            glassTintColor().cgColor

        root.addSubview(tint)

        // Glossy light reflection.
        let reflection = NSView(frame: root.bounds)

        reflection.autoresizingMask = [
            .width,
            .height
        ]

        reflection.wantsLayer = true

        let reflectionGradient = CAGradientLayer()

        reflectionGradient.frame = reflection.bounds

        reflectionGradient.colors = reflectionColors()

        reflectionGradient.locations = [
            0.0,
            0.28,
            0.65,
            1.0
        ]

        reflectionGradient.startPoint = CGPoint(
            x: 0.0,
            y: 1.0
        )

        reflectionGradient.endPoint = CGPoint(
            x: 1.0,
            y: 0.0
        )

        reflection.layer?.addSublayer(reflectionGradient)

        root.addSubview(reflection)

        // Soft glass edge highlights.
        let edge = NSView(frame: root.bounds)

        edge.autoresizingMask = [
            .width,
            .height
        ]

        edge.wantsLayer = true

        edge.layer?.borderWidth = 1.0

        edge.layer?.borderColor =
            NSColor.white
                .withAlphaComponent(
                    style == .darkFrosted ? 0.15 : 0.35
                )
                .cgColor

        root.addSubview(edge)
    }

    // MARK: - Liquid Glass Card

    private func makeLiquidGlassCard(in root: NSView) {

        let content = NSView()
        let card: NSView

        if #available(macOS 26.0, *) {
            // Real system Liquid Glass.
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cardCornerRadius
            glass.tintColor = NSColor.white.withAlphaComponent(0.06)
            glass.contentView = content
            card = glass

        } else {
            // Fallback: layered frosted card with a specular rim.
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = cardCornerRadius
            blur.layer?.cornerCurve = .continuous
            blur.layer?.masksToBounds = true

            content.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                content.topAnchor.constraint(equalTo: blur.topAnchor),
                content.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
            ])

            let cardBounds = CGRect(origin: .zero, size: cardSize)

            // Inner light wash.
            let wash = CAGradientLayer()
            wash.frame = cardBounds
            wash.colors = [
                NSColor.white.withAlphaComponent(0.22).cgColor,
                NSColor.white.withAlphaComponent(0.04).cgColor,
                NSColor.white.withAlphaComponent(0.10).cgColor
            ]
            wash.startPoint = CGPoint(x: 0, y: 1)
            wash.endPoint = CGPoint(x: 1, y: 0)
            blur.layer?.addSublayer(wash)

            // Specular rim: bright at top-left, fades, glints at bottom-right.
            let rim = CAGradientLayer()
            rim.frame = cardBounds
            rim.colors = [
                NSColor.white.withAlphaComponent(0.90).cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor,
                NSColor.white.withAlphaComponent(0.55).cgColor
            ]
            rim.locations = [0.0, 0.35, 0.65, 1.0]
            rim.startPoint = CGPoint(x: 0, y: 1)
            rim.endPoint = CGPoint(x: 1, y: 0)

            let stroke = CAShapeLayer()
            stroke.path = CGPath(
                roundedRect: cardBounds.insetBy(dx: 0.75, dy: 0.75),
                cornerWidth: cardCornerRadius,
                cornerHeight: cardCornerRadius,
                transform: nil
            )
            stroke.fillColor = nil
            stroke.strokeColor = NSColor.white.cgColor
            stroke.lineWidth = 1.5
            rim.mask = stroke
            blur.layer?.addSublayer(rim)

            card = blur
        }

        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true

        // Floating shadow (applied to the container, not the clipped layer).
        let shadowHost = NSView()
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.35
        shadowHost.layer?.shadowRadius = 40
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -16)

        root.addSubview(shadowHost)
        shadowHost.addSubview(card)

        NSLayoutConstraint.activate([
            shadowHost.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            shadowHost.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            shadowHost.widthAnchor.constraint(equalToConstant: cardSize.width),
            shadowHost.heightAnchor.constraint(equalToConstant: cardSize.height),

            card.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            card.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            card.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor)
        ])

        addBranding(to: content)
    }

    // MARK: - Glass Tint

    private func glassTintColor() -> NSColor {

        switch style {

        case .solidBlack:
            return NSColor.black.withAlphaComponent(opacity)

        case .darkFrosted:
            return NSColor.black.withAlphaComponent(
                min(0.25 + opacity * 0.50, 0.90)
            )

        case .liquidGlass:
            return NSColor(
                calibratedWhite: 0.82,
                alpha: min(0.08 + opacity * 0.22, 0.40)
            )
        }
    }

    // MARK: - Reflection Colors

    private func reflectionColors() -> [CGColor] {

        switch style {

        case .solidBlack:
            return [
                NSColor.clear.cgColor,
                NSColor.clear.cgColor,
                NSColor.clear.cgColor,
                NSColor.clear.cgColor
            ]

        case .darkFrosted:
            return [
                NSColor.white.withAlphaComponent(0.10).cgColor,
                NSColor.white.withAlphaComponent(0.02).cgColor,
                NSColor.black.withAlphaComponent(0.08).cgColor,
                NSColor.black.withAlphaComponent(0.22).cgColor
            ]

        case .liquidGlass:
            // Kept soft so the floating card is the bright element.
            return [
                NSColor.white.withAlphaComponent(0.10).cgColor,
                NSColor.white.withAlphaComponent(0.03).cgColor,
                NSColor.systemBlue.withAlphaComponent(0.04).cgColor,
                NSColor.black.withAlphaComponent(0.08).cgColor
            ]
        }
    }

    // MARK: - Branding

    /// Works with any container: the full-screen root or the glass card's content view.
    private func addBranding(to container: NSView) {

        let icon = NSImageView()

        icon.image = NSImage(
            systemSymbolName: "shield.lefthalf.filled",
            accessibilityDescription: "Privacy"
        )

        icon.contentTintColor = .white

        icon.symbolConfiguration =
            NSImage.SymbolConfiguration(
                pointSize: 34,
                weight: .medium
            )

        let title = NSTextField(
            labelWithString: "SHROUD"
        )

        title.font = .boldSystemFont(ofSize: 32)
        title.textColor = .white
        title.alignment = .center

        let subtitle = NSTextField(
            labelWithString: "Your screen. Your privacy."
        )

        subtitle.font = .systemFont(ofSize: 14)

        subtitle.textColor =
            NSColor.white.withAlphaComponent(0.85)

        subtitle.alignment = .center

        let status = NSTextField(
            labelWithString: "PRIVACY PROTECTION ACTIVE"
        )

        status.font = .systemFont(
            ofSize: 10,
            weight: .semibold
        )

        status.textColor =
            NSColor.white.withAlphaComponent(0.65)

        status.alignment = .center

        let stack = NSStackView(views: [icon, title, subtitle, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(22, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(
                equalTo: container.centerXAnchor
            ),
            stack.centerYAnchor.constraint(
                equalTo: container.centerYAnchor
            )
        ])
    }

    // MARK: - Live Opacity Update

    private func updateAppearance() {

        for window in windows {

            guard let root = window.contentView else {
                continue
            }

            if style == .solidBlack {

                if let background = root.subviews.first(where: {
                    $0.identifier?.rawValue ==
                        "ShroudSolidBackground"
                }) {

                    background.layer?.backgroundColor =
                        NSColor.black
                            .withAlphaComponent(opacity)
                            .cgColor
                }

            } else {

                if let tint = root.subviews.first(where: {
                    $0.identifier?.rawValue ==
                        "ShroudGlassTint"
                }) {

                    tint.layer?.backgroundColor =
                        glassTintColor().cgColor
                }
            }
        }
    }

    // MARK: - Hide Overlay

    func hide() {

        guard !windows.isEmpty else {
            isVisible = false
            return
        }

        let oldWindows = windows

        windows = []
        isVisible = false

        for window in oldWindows {
            window.orderOut(nil)
        }

        // Avoid the previous overlay release crash.
        // Do not explicitly call window.close().
        Task { @MainActor in
            withExtendedLifetime(oldWindows) {}
        }
    }
}