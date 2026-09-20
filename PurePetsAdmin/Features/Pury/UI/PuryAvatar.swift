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
import AVFoundation

// MARK: - Pury Brand Identity

/// Pury-local identity tokens sampled from the official `PuryV1` artwork.
/// These colors identify Pury only; operational success/warning/error colors stay semantic.
public enum PuryBrand {
    public static let deepRose = Color(red: 160.0 / 255.0, green: 0.0 / 255.0, blue: 48.0 / 255.0)
    public static let primary = Color(red: 208.0 / 255.0, green: 0.0 / 255.0, blue: 80.0 / 255.0)
    public static let accent = Color(red: 224.0 / 255.0, green: 16.0 / 255.0, blue: 96.0 / 255.0)
    public static let hotPink = Color(red: 255.0 / 255.0, green: 64.0 / 255.0, blue: 128.0 / 255.0)
    public static let highlight = Color(red: 255.0 / 255.0, green: 96.0 / 255.0, blue: 160.0 / 255.0)
    public static let violet = Color(red: 139.0 / 255.0, green: 92.0 / 255.0, blue: 246.0 / 255.0)
    public static let glow = hotPink

    /// Dynamic app foreground color token (`AppForgroundColr` / `ppElevatedSurface`).
    public static var appForeground: Color {
        Color(uiColor: UIColor(named: "AppForgroundColr") ?? .ppElevatedSurface)
    }

    public static var identityGradient: LinearGradient {
        LinearGradient(
            colors: [highlight, hotPink, primary, deepRose],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - PuryAvatar (SwiftUI)

/// Central shared circular UI view for Pury featuring a living Ultra Apex background
/// and the high-resolution `PuryV1` character asset.
public struct PuryAvatar: View {
    // MARK: - Properties

    public let size: CGFloat
    public let isLiving: Bool
    public let isThinking: Bool
    public let motionState: PuryMotionState?
    public let showStatusRing: Bool
    public let showAmbientAura: Bool
    public let useGlassBackground: Bool
    public let action: (() -> Void)?

    // MARK: - Animation States

    @State private var ambientBreath: Bool = false
    @State private var particleDrift: Bool = false

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    public init(
        size: CGFloat = 44,
        isLiving: Bool = true,
        isThinking: Bool = false,
        motionState: PuryMotionState? = nil,
        showStatusRing: Bool = true,
        showAmbientAura: Bool = true,
        useGlassBackground: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.size = size
        self.isLiving = isLiving
        self.isThinking = isThinking
        self.motionState = motionState
        self.showStatusRing = showStatusRing
        self.showAmbientAura = showAmbientAura
        self.useGlassBackground = useGlassBackground
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
        TimelineView(.animation(paused: !isThinking || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spinRotation: Double = (isThinking && !reduceMotion)
                ? (time.truncatingRemainder(dividingBy: 3.6) / 3.6) * 360.0
                : 0.0
            let microPulse: CGFloat = (isThinking && !reduceMotion)
                ? CGFloat(sin(time * 3.0) * 0.026 + 1.0)
                : 1.0

            ZStack {
                // 1. Living Outer Ambient Aura
                if showAmbientAura {
                    ambientAuraView
                }

                // 2. Outer Precision Status Ring
                if showStatusRing {
                    statusRingView(spinRotation: spinRotation)
                }

                // 3. Ultra Apex Core Disk (Background + Mascot Art + Inner Rim)
                apexCoreOrbView(spinRotation: spinRotation, microPulse: microPulse)
            }
            .frame(width: totalCanvasSize, height: totalCanvasSize)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: isThinking)
        }
        .onAppear {
            startLivingAnimations()
        }
    }

    // MARK: - 1. Ambient Aura

    private var ambientAuraView: some View {
        let auraExpansion: CGFloat = isThinking ? (size * 0.34) : (size * 0.22)
        let baseAuraSize = size + auraExpansion
        let pulseScale: CGFloat = (!reduceMotion && isLiving) ? (ambientBreath ? 1.08 : 0.94) : 1.0
        let pulseOpacity: Double = isThinking
            ? 0.45
            : ((!reduceMotion && isLiving) ? (ambientBreath ? 0.36 : 0.12) : 0.22)

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
                PuryBrand.violet.opacity(0.78),
                PuryBrand.highlight.opacity(0.58),
                PuryBrand.primary.opacity(0.30),
                Color.clear
            ]
        } else {
            return [
                PuryBrand.highlight.opacity(0.74),
                PuryBrand.primary.opacity(0.48),
                PuryBrand.deepRose.opacity(0.20),
                Color.clear
            ]
        }
    }

    // MARK: - 2. Status Filament Ring

    private func statusRingView(spinRotation: Double) -> some View {
        let ringDiameter = size + max(size * 0.14, 5)
        let strokeWidth: CGFloat = max(size * 0.032, 1.2)

        return ZStack {
            if isThinking {
                // Spinning halo ring during thinking/inference
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                PuryBrand.violet,
                                PuryBrand.highlight,
                                PuryBrand.hotPink,
                                PuryBrand.primary,
                                PuryBrand.violet
                            ],
                            center: .center
                        ),
                        lineWidth: strokeWidth
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .rotationEffect(.degrees(spinRotation * 1.15))
            } else {
                // Calm Pury rose filament with a soft optical highlight.
                Circle()
                    .strokeBorder(
                        PuryBrand.primary.opacity(isLiving ? (ambientBreath ? 0.46 : 0.24) : 0.28),
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

    private func apexCoreOrbView(spinRotation: Double, microPulse: CGFloat) -> some View {
        ZStack {
            // (a) Base Disc: Ultra Thin Material for glass mode, App Foreground otherwise
            if useGlassBackground {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(PuryBrand.appForeground)
                    .frame(width: size, height: size)
            }

            // (b) Subtle Specular Surface Sheen (Tactile Apple-grade depth)
            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40), location: 0.0),
                            .init(color: Color.white.opacity(0.0), location: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // (c) Living Stardust Particles (when enabled and size is sufficient)
            if isLiving && !reduceMotion && size >= 32 {
                microStardustLayer
            }

            // (d) Official Pury Artwork (`PuryV1`) with graceful vector fallback
            mascotArtLayer(spinRotation: spinRotation, microPulse: microPulse)

            // (e) Directional Precision Inner Stroke Rim
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: (colorScheme == .dark || useGlassBackground)
                            ? [
                                Color.white.opacity(0.36),
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.04)
                            ]
                            : [
                                Color(uiColor: .ppSurfaceBorder),
                                Color(uiColor: .ppSurfaceBorder).opacity(0.60),
                                Color(uiColor: .ppSurfaceBorder).opacity(0.30)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(size * 0.024, 0.8)
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .shadow(
            color: showAmbientAura
                ? (isThinking ? PuryBrand.violet : PuryBrand.glow).opacity(colorScheme == .dark ? 0.30 : 0.16)
                : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
            radius: max(size * 0.16, 4),
            x: 0,
            y: max(size * 0.06, 2)
        )
    }

    // MARK: - Micro Stardust Layer

    private var microStardustLayer: some View {
        let stardustColor = colorScheme == .dark ? Color.white : PuryBrand.primary
        return ZStack {
            // Top Right Sparkle Point
            Circle()
                .fill(stardustColor)
                .frame(width: max(size * 0.04, 1.8), height: max(size * 0.04, 1.8))
                .opacity(particleDrift ? 0.75 : 0.25)
                .offset(x: size * 0.28, y: -size * 0.24)

            // Bottom Left Stardust Point
            Circle()
                .fill(stardustColor.opacity(0.9))
                .frame(width: max(size * 0.03, 1.4), height: max(size * 0.03, 1.4))
                .opacity(particleDrift ? 0.20 : 0.65)
                .offset(x: -size * 0.26, y: size * 0.22)
        }
    }

    // MARK: - Mascot Art Layer (PuryV1)

    private func mascotArtLayer(spinRotation: Double, microPulse: CGFloat) -> some View {
        let artworkInset: CGFloat = max(size * 0.06, 2.0)
        let artworkDiameter = max(size - (artworkInset * 2), 12)

        return Group {
            if hasPuryV1Asset {
                ZStack {
                    if let videoURL = renderedMotionURL {
                        Image("PuryV1")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: artworkDiameter, height: artworkDiameter)
                            .clipShape(Circle())

                        PuryLoopingVideoView(url: videoURL)
                            .frame(width: artworkDiameter, height: artworkDiameter)
                            .clipShape(Circle())
                            .id(resolvedMotionState)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    } else {
                        Image("PuryV1")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: artworkDiameter, height: artworkDiameter)
                            .clipShape(Circle())
                            .rotationEffect(.degrees(spinRotation))
                            .scaleEffect(isThinking ? microPulse : 1.0)
                    }

                    // Apple-grade dynamic specular light sheen across the rotating mascot
                    if isThinking && !reduceMotion {
                        Circle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.15 : 0.32), location: 0.0),
                                        .init(color: Color.white.opacity(0.0), location: 0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: artworkDiameter, height: artworkDiameter)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                // Fail-safe vector beacon fallback if image asset is absent
                fallbackVectorBeacon(diameter: artworkDiameter, spinRotation: spinRotation)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: resolvedMotionState)
    }

    private var hasPuryV1Asset: Bool {
        UIImage(named: "PuryV1") != nil
    }

    private var resolvedMotionState: PuryMotionState {
        motionState ?? (isThinking ? .thinking : .idle)
    }

    private var renderedMotionURL: URL? {
        guard isLiving, !reduceMotion, size >= 36 else { return nil }
        return PuryMotionAssetStore.url(for: resolvedMotionState)
    }

    private func fallbackVectorBeacon(diameter: CGFloat, spinRotation: Double) -> some View {
        Image(systemName: isThinking ? "rays" : "sparkles")
            .font(.system(size: diameter * 0.48, weight: .bold))
            .foregroundStyle(isThinking ? PuryBrand.violet : PuryBrand.primary)
            .rotationEffect(.degrees(isThinking ? spinRotation : 0))
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

    @objc public var useGlassBackground: Bool = false {
        didSet {
            guard useGlassBackground != oldValue else { return }
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
        showAmbientAura: Bool = true,
        useGlassBackground: Bool = false
    ) {
        self.size = size
        self.isLiving = isLiving
        self.isThinking = isThinking
        self.showStatusRing = showStatusRing
        self.showAmbientAura = showAmbientAura
        self.useGlassBackground = useGlassBackground
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
            useGlassBackground: useGlassBackground,
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

// MARK: - Rendered Motion States

public enum PuryMotionState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case searching
    case responding
    case success
    case confused
    case warning
    case error

    fileprivate var assetName: String {
        "PuryV1" 
    }
}

private enum PuryMotionAssetStore {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSURL>()

    static func url(for state: PuryMotionState) -> URL? {
        let key = state.assetName as NSString
        if let cached = cache.object(forKey: key) {
            return cached as URL
        }
        guard let asset = NSDataAsset(name: state.assetName) else { return nil }

        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = caches.appendingPathComponent("PuryV1", isDirectory: true)
        let destination = directory.appendingPathComponent(state.assetName).appendingPathExtension("mp4")

        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let existingSize = ((try? fm.attributesOfItem(atPath: destination.path)[.size]) as? NSNumber)?.intValue
            if existingSize != asset.data.count {
                try asset.data.write(to: destination, options: .atomic)
            }
        } catch {
            return nil
        }

        cache.setObject(destination as NSURL, forKey: key)
        return destination
    }
}

private final class PuryPlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("PuryPlayerSurfaceView requires AVPlayerLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        playerLayer.videoGravity = .resizeAspectFill
    }
}

private struct PuryLoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PuryPlayerSurfaceView {
        let view = PuryPlayerSurfaceView()
        context.coordinator.play(url: url, on: view)
        return view
    }

    func updateUIView(_ view: PuryPlayerSurfaceView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.play(url: url, on: view)
    }

    static func dismantleUIView(_ view: PuryPlayerSurfaceView, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }

    final class Coordinator {
        fileprivate var currentURL: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func play(url: URL, on view: PuryPlayerSurfaceView) {
            stop()
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 0.12
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.actionAtItemEnd = .none
            queue.automaticallyWaitsToMinimizeStalling = false

            player = queue
            looper = AVPlayerLooper(player: queue, templateItem: item)
            currentURL = url
            view.playerLayer.player = queue
            queue.playImmediately(atRate: 1.0)
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player?.removeAllItems()
            player = nil
            currentURL = nil
        }
    }
}
