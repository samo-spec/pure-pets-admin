//
//  PuryAvatar.swift
//  PurePetsAdmin
//
//  Central shared circular UI view with living Ultra Apex background,
//  precision multi-layered aurora depth, and official PuryV1 mascot artwork.
//  Available natively in SwiftUI (PuryAvatar) and UIKit/Obj-C (PuryAvatarView).
//

import SwiftUI
import UIKit

// MARK: - PuryAvatar (SwiftUI)

/// Central shared circular UI view for Pury featuring a living Ultra Apex background
/// and the high-resolution `PuryV1` character asset.
public struct PuryAvatar: View {
    // MARK: - Properties

    public let size: CGFloat
    public let isLiving: Bool
    public let isThinking: Bool
    public let showStatusRing: Bool
    public let showAmbientAura: Bool
    public let action: (() -> Void)?

    // MARK: - Animation States

    @State private var ambientBreath: Bool = false
    @State private var thinkingRotation: Double = 0
    @State private var particleDrift: Bool = false

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Initialization

    public init(
        size: CGFloat = 44,
        isLiving: Bool = true,
        isThinking: Bool = false,
        showStatusRing: Bool = true,
        showAmbientAura: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.size = size
        self.isLiving = isLiving
        self.isThinking = isThinking
        self.showStatusRing = showStatusRing
        self.showAmbientAura = showAmbientAura
        self.action = action
    }

    // MARK: - Convenience Presets

    /// Mini avatar (24pt) — optimized for message bubbles and compact table cells.
    public static func mini(isThinking: Bool = false, action: (() -> Void)? = nil) -> PuryAvatar {
        PuryAvatar(size: 24, isLiving: true, isThinking: isThinking, showStatusRing: false, showAmbientAura: false, action: action)
    }

    /// Compact avatar (32pt) — optimized for navigation bars, chips, and toolbars.
    public static func compact(isThinking: Bool = false, action: (() -> Void)? = nil) -> PuryAvatar {
        PuryAvatar(size: 32, isLiving: true, isThinking: isThinking, showStatusRing: true, showAmbientAura: false, action: action)
    }

    /// Standard avatar (44pt) — standard size for headers, cards, and interactive buttons.
    public static func standard(isThinking: Bool = false, action: (() -> Void)? = nil) -> PuryAvatar {
        PuryAvatar(size: 44, isLiving: true, isThinking: isThinking, showStatusRing: true, showAmbientAura: true, action: action)
    }

    /// Large avatar (64pt) — optimized for assistant greeting cards and modal headers.
    public static func large(isThinking: Bool = false, action: (() -> Void)? = nil) -> PuryAvatar {
        PuryAvatar(size: 64, isLiving: true, isThinking: isThinking, showStatusRing: true, showAmbientAura: true, action: action)
    }

    /// Hero avatar (88pt) — optimized for full-screen hero empty states and splash intros.
    public static func hero(isThinking: Bool = false, action: (() -> Void)? = nil) -> PuryAvatar {
        PuryAvatar(size: 88, isLiving: true, isThinking: isThinking, showStatusRing: true, showAmbientAura: true, action: action)
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let action = action {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }) {
                    avatarContent
                }
                .buttonStyle(.plain)
            } else {
                avatarContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Language.isRTL() ? "مساعد بيوري الذكي" : "Pury AI Assistant"))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - Avatar View Composition

    private var avatarContent: some View {
        ZStack {
            // 1. Living Outer Ambient Aura
            if showAmbientAura {
                ambientAuraView
            }

            // 2. Outer Precision Status Ring
            if showStatusRing {
                statusRingView
            }

            // 3. Ultra Apex Core Disk (Background + Mascot Art + Inner Rim)
            apexCoreOrbView
        }
        .frame(width: totalCanvasSize, height: totalCanvasSize)
        .onAppear {
            startLivingAnimations()
        }
        .onChange(of: isThinking) { thinking in
            if thinking {
                startThinkingAnimation()
            }
        }
    }

    // MARK: - 1. Ambient Aura

    private var ambientAuraView: some View {
        let auraExpansion: CGFloat = isThinking ? (size * 0.34) : (size * 0.22)
        let baseAuraSize = size + auraExpansion
        let pulseScale: CGFloat = (!reduceMotion && isLiving) ? (ambientBreath ? 1.08 : 0.94) : 1.0
        let pulseOpacity: Double = (!reduceMotion && isLiving) ? (ambientBreath ? (isThinking ? 0.55 : 0.36) : (isThinking ? 0.25 : 0.12)) : 0.22

        return Circle()
            .fill(
                RadialGradient(
                    colors: auraColors,
                    center: .center,
                    startRadius: size * 0.32,
                    endRadius: baseAuraSize * 0.5
                )
            )
            .frame(width: baseAuraSize, height: baseAuraSize)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .blur(radius: max(size * 0.12, 3))
    }

    private var auraColors: [Color] {
        if isThinking {
            return [
                Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.85), // Violet
                Color(red: 6/255, green: 182/255, blue: 212/255).opacity(0.45),  // Electric Cyan
                Color.clear
            ]
        } else {
            return [
                Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.80), // Emerald
                Color(red: 52/255, green: 211/255, blue: 153/255).opacity(0.35), // Mint
                Color.clear
            ]
        }
    }

    // MARK: - 2. Status Filament Ring

    private var statusRingView: some View {
        let ringDiameter = size + max(size * 0.14, 5)
        let strokeWidth: CGFloat = max(size * 0.032, 1.2)

        return ZStack {
            if isThinking {
                // Spinning halo ring during thinking/inference
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(red: 139/255, green: 92/255, blue: 246/255), // Purple
                                Color(red: 6/255, green: 182/255, blue: 212/255),  // Cyan
                                Color(red: 16/255, green: 185/255, blue: 129/255), // Emerald
                                Color(red: 139/255, green: 92/255, blue: 246/255)  // Back to Purple
                            ],
                            center: .center
                        ),
                        lineWidth: strokeWidth
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .rotationEffect(.degrees(thinkingRotation))
            } else {
                // Calibrated calm emerald status ring with soft highlight
                Circle()
                    .strokeBorder(
                        Color(red: 16/255, green: 185/255, blue: 129/255).opacity(isLiving ? (ambientBreath ? 0.45 : 0.22) : 0.25),
                        lineWidth: strokeWidth
                    )
                    .frame(width: ringDiameter, height: ringDiameter)

                // Micro specular point on the ring
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: strokeWidth * 1.6, height: strokeWidth * 1.6)
                    .offset(x: ringDiameter * 0.5 - strokeWidth * 0.5)
                    .rotationEffect(.degrees(ambientBreath ? 45 : 225))
            }
        }
    }

    // MARK: - 3. Ultra Apex Core Disk

    private var apexCoreOrbView: some View {
        ZStack {
            // (a) Frosted Glass Base Disc
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)

            // (b) Ultra Apex Deep Atmospheric Aurora Gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: coreAuroraColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // (c) Spherical Radial Vignette (Optical Convexity)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.32)
                        ],
                        center: .center,
                        startRadius: size * 0.25,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)

            // (d) Living Stardust Particles (when enabled and size is sufficient)
            if isLiving && !reduceMotion && size >= 32 {
                microStardustLayer
            }

            // (e) Official Pury Artwork (`PuryV1`) with graceful vector fallback
            mascotArtLayer

            // (f) Directional Specular Inner Stroke Rim (Top-down lighting)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(size * 0.026, 0.9)
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .shadow(
            color: (isThinking ? Color(red: 139/255, green: 92/255, blue: 246/255) : Color(red: 16/255, green: 185/255, blue: 129/255)).opacity(0.35),
            radius: max(size * 0.16, 4),
            x: 0,
            y: max(size * 0.06, 2)
        )
    }

    private var coreAuroraColors: [Color] {
        if isThinking {
            return [
                Color(red: 139/255, green: 92/255, blue: 246/255), // Violet
                Color(red: 79/255, green: 70/255, blue: 229/255),  // Indigo
                Color(red: 6/255, green: 182/255, blue: 212/255)   // Cyan
            ]
        } else {
            return [
                Color(red: 16/255, green: 185/255, blue: 129/255), // Emerald
                Color(red: 5/255, green: 150/255, blue: 105/255),  // Mint Green
                Color(red: 4/255, green: 120/255, blue: 87/255)    // Deep Ocean Teal
            ]
        }
    }

    // MARK: - Micro Stardust Layer

    private var microStardustLayer: some View {
        ZStack {
            // Top Right Sparkle Point
            Circle()
                .fill(Color.white)
                .frame(width: max(size * 0.04, 1.8), height: max(size * 0.04, 1.8))
                .opacity(particleDrift ? 0.75 : 0.25)
                .offset(x: size * 0.28, y: -size * 0.24)

            // Bottom Left Stardust Point
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(size * 0.03, 1.4), height: max(size * 0.03, 1.4))
                .opacity(particleDrift ? 0.20 : 0.65)
                .offset(x: -size * 0.26, y: size * 0.22)
        }
    }

    // MARK: - Mascot Art Layer (PuryV1)

    private var mascotArtLayer: some View {
        let artworkInset: CGFloat = max(size * 0.06, 2.0)
        let artworkDiameter = max(size - (artworkInset * 2), 12)

        return Group {
            if hasPuryV1Asset {
                Image("PuryV1")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: artworkDiameter, height: artworkDiameter)
                    .clipShape(Circle())
                    .scaleEffect((isThinking && !reduceMotion) ? (ambientBreath ? 1.03 : 0.98) : 1.0)
            } else {
                // Fail-safe vector beacon fallback if image asset is absent
                fallbackVectorBeacon(diameter: artworkDiameter)
            }
        }
    }

    private var hasPuryV1Asset: Bool {
        UIImage(named: "PuryV1") != nil
    }

    private func fallbackVectorBeacon(diameter: CGFloat) -> some View {
        Image(systemName: isThinking ? "rays" : "sparkles")
            .font(.system(size: diameter * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(isThinking ? thinkingRotation : 0))
    }

    // MARK: - Layout Helpers

    private var totalCanvasSize: CGFloat {
        if showAmbientAura {
            let auraExpansion: CGFloat = isThinking ? (size * 0.34) : (size * 0.22)
            return size + auraExpansion + 4
        } else if showStatusRing {
            return size + max(size * 0.14, 5) + 2
        } else {
            return size
        }
    }

    // MARK: - Animation Controllers

    private func startLivingAnimations() {
        guard isLiving && !reduceMotion else { return }

        withAnimation(
            .easeInOut(duration: 2.8)
            .repeatForever(autoreverses: true)
        ) {
            ambientBreath = true
        }

        withAnimation(
            .easeInOut(duration: 4.2)
            .repeatForever(autoreverses: true)
        ) {
            particleDrift = true
        }

        if isThinking {
            startThinkingAnimation()
        }
    }

    private func startThinkingAnimation() {
        guard !reduceMotion else { return }

        withAnimation(
            .linear(duration: 2.4)
            .repeatForever(autoreverses: false)
        ) {
            thinkingRotation = 360
        }
    }
}

// MARK: - PuryAvatarView (UIKit & Objective-C Bridge)

/// Objective-C and UIKit compatible wrapper for `PuryAvatar`.
/// Can be used directly in any UIView hierarchy, navigation item, table cell, or view controller.
@objcMembers
public final class PuryAvatarView: UIView {
    // MARK: - Public Properties

    public var size: CGFloat = 44 {
        didSet {
            guard size != oldValue else { return }
            rebuildHostedView()
            invalidateIntrinsicContentSize()
        }
    }

    public var isLiving: Bool = true {
        didSet {
            guard isLiving != oldValue else { return }
            rebuildHostedView()
        }
    }

    public var isThinking: Bool = false {
        didSet {
            guard isThinking != oldValue else { return }
            rebuildHostedView()
        }
    }

    public var showStatusRing: Bool = true {
        didSet {
            guard showStatusRing != oldValue else { return }
            rebuildHostedView()
        }
    }

    public var showAmbientAura: Bool = true {
        didSet {
            guard showAmbientAura != oldValue else { return }
            rebuildHostedView()
        }
    }

    public var onTapped: (() -> Void)? {
        didSet {
            rebuildHostedView()
        }
    }

    // MARK: - Internal

    private var hostingController: UIHostingController<PuryAvatar>?

    // MARK: - Initializers

    public init(
        size: CGFloat = 44,
        isLiving: Bool = true,
        isThinking: Bool = false,
        showStatusRing: Bool = true,
        showAmbientAura: Bool = true
    ) {
        self.size = size
        self.isLiving = isLiving
        self.isThinking = isThinking
        self.showStatusRing = showStatusRing
        self.showAmbientAura = showAmbientAura
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setupView()
    }

    public override init(frame: CGRect) {
        let derivedSize = max(min(frame.width, frame.height), 24)
        self.size = derivedSize > 24 ? derivedSize : 44
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder: NSCoder) {
        self.size = 44
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        rebuildHostedView()
    }

    private func rebuildHostedView() {
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let swiftUIView = PuryAvatar(
            size: size,
            isLiving: isLiving,
            isThinking: isThinking,
            showStatusRing: showStatusRing,
            showAmbientAura: showAmbientAura,
            action: onTapped
        )

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.view.centerYAnchor.constraint(equalTo: centerYAnchor),
            host.view.widthAnchor.constraint(equalTo: widthAnchor),
            host.view.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        self.hostingController = host
    }

    // MARK: - Layout & Sizing

    public override var intrinsicContentSize: CGSize {
        CGSize(width: size, height: size)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: self.size, height: self.size)
    }

    // MARK: - Public Control Methods

    public func setThinking(_ thinking: Bool, animated: Bool = true) {
        if animated {
            UIView.animate(withDuration: 0.35) {
                self.isThinking = thinking
            }
        } else {
            self.isThinking = thinking
        }
    }
}
