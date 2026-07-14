//
//  PPHeroApex.swift
//  PurePetsAdmin
//
//  Flagship-grade, background-only hero material. The Objective-C PPHero
//  contract is preserved by PPHeroApexBridge while this view owns all visual,
//  accessibility, interaction, and motion behavior.
//

import UIKit

@MainActor
private final class PPHeroPassiveTouchRecognizer: UIGestureRecognizer {
    var onUpdate: ((CGPoint, UIGestureRecognizer.State) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view, let touch = touches.first else {
            state = .failed
            return
        }
        state = .began
        onUpdate?(touch.location(in: view), state)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view, let touch = touches.first else { return }
        state = .changed
        onUpdate?(touch.location(in: view), state)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let location = touches.first.map { touch in
            view.map { touch.location(in: $0) } ?? .zero
        } ?? .zero
        state = .ended
        onUpdate?(location, state)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        let location = touches.first.map { touch in
            view.map { touch.location(in: $0) } ?? .zero
        } ?? .zero
        state = .cancelled
        onUpdate?(location, state)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

/// The living visual engine behind every shared Admin hero.
///
/// This component deliberately remains background-only. It never owns copy,
/// actions, navigation, or business state, so existing controllers keep their
/// hierarchy, localization, permissions, and truthful action haptics.
@objcMembers
public final class PPHeroApexView: UIView, UIGestureRecognizerDelegate {
    private enum AccentMode: Int {
        case bar = 0
        case cornerGlow = 1
    }

    private struct AuroraSpec {
        let center: CGPoint
        let size: CGSize
        let travel: CGSize
        let duration: CFTimeInterval
        let phase: CFTimeInterval
    }

    private struct Palette {
        let accent: UIColor
        let surfaceHighlight: UIColor
        let surfaceMiddle: UIColor
        let surfaceTail: UIColor
        let depth: UIColor
        let aurora: [UIColor]
        let particle: [UIColor]
        let reactiveLight: UIColor
        let stroke: UIColor
        let shadowOpacity: Float
    }

    // MARK: - Objective-C compatibility surface

    public var accentColorOverride: UIColor? {
        didSet {
            guard oldValue !== accentColorOverride else { return }
            reapplyPalette()
        }
    }

    public var accentStyle: Int {
        get { storedAccentMode.rawValue }
        set {
            let resolvedMode = AccentMode(rawValue: newValue) ?? .bar
            guard resolvedMode != storedAccentMode else { return }
            storedAccentMode = resolvedMode
            setNeedsLayout()
            reapplyPalette()
        }
    }

    public var cornerGlowOpacityMultiplier: CGFloat {
        get { storedCornerGlowOpacityMultiplier }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard abs(clamped - storedCornerGlowOpacityMultiplier) > 0.001 else { return }
            storedCornerGlowOpacityMultiplier = clamped
            reapplyPalette()
        }
    }

    // MARK: - Material hierarchy

    private let materialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let baseView = UIView()
    private let ambientView = UIView()
    private let overlayView = UIView()

    private let baseGradientLayer = CAGradientLayer()
    private let depthGradientLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()
    private let auroraLayers = (0..<3).map { _ in CAGradientLayer() }
    private let particleLayers = (0..<3).map { _ in CAShapeLayer() }
    private let reactiveLightLayer = CAGradientLayer()
    private let glassSheenLayer = CAGradientLayer()
    private let accentBarLayer = CAGradientLayer()
    private let accentGlowLayer = CAGradientLayer()
    private let innerStrokeLayer = CAShapeLayer()

    // MARK: - Lifecycle state

    private var storedAccentMode: AccentMode = .bar
    private var storedCornerGlowOpacityMultiplier: CGFloat = 1
    private var motionRunning = false
    private var lastLayoutSize: CGSize = .zero
    private var parallaxMotionEffect: UIMotionEffectGroup?
    private weak var touchHost: UIView?
    private var touchRecognizer: PPHeroPassiveTouchRecognizer?
    private var touchResponseActive = false

    private let cornerRadius: CGFloat = 30
    private let auroraAnimationKey = "pp.hero.apex.aurora"
    private let particleAnimationKey = "pp.hero.apex.particle"
    private let reactiveLightAnimationKey = "pp.hero.apex.reactive-light"
    private let sheenAnimationKey = "pp.hero.apex.sheen"

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        detachTouchTracker()
    }

    private func commonInit() {
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 12)
        layer.shadowRadius = 24

        configureViewHierarchy()
        configureLayers()
        registerForLifecycleChanges()
        reapplyPalette()
    }

    private func configureViewHierarchy() {
        [materialView, baseView, ambientView, overlayView].forEach { view in
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.backgroundColor = .clear
        }

        materialView.clipsToBounds = true
        materialView.layer.cornerRadius = cornerRadius
        materialView.layer.cornerCurve = .continuous
        addSubview(materialView)
        materialView.contentView.addSubview(baseView)
        materialView.contentView.addSubview(ambientView)
        materialView.contentView.addSubview(overlayView)
    }

    private func configureLayers() {
        [baseGradientLayer, depthGradientLayer, vignetteLayer].forEach { layer in
            layer.drawsAsynchronously = true
            baseView.layer.addSublayer(layer)
        }

        baseGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        baseGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        baseGradientLayer.locations = [0, 0.52, 1]

        depthGradientLayer.startPoint = CGPoint(x: 0.15, y: 0)
        depthGradientLayer.endPoint = CGPoint(x: 0.85, y: 1)
        depthGradientLayer.locations = [0, 0.58, 1]

        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.38)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.locations = [0, 0.7, 1]

        auroraLayers.forEach { layer in
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            layer.locations = [0, 0.42, 1]
            layer.drawsAsynchronously = true
            ambientView.layer.addSublayer(layer)
        }

        particleLayers.forEach { layer in
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 0
            layer.contentsScale = UIScreen.main.scale
            layer.allowsEdgeAntialiasing = true
            ambientView.layer.addSublayer(layer)
        }

        reactiveLightLayer.type = .radial
        reactiveLightLayer.locations = [0, 0.34, 1]
        reactiveLightLayer.drawsAsynchronously = true
        overlayView.layer.addSublayer(reactiveLightLayer)

        glassSheenLayer.startPoint = CGPoint(x: 0, y: 0)
        glassSheenLayer.endPoint = CGPoint(x: 1, y: 1)
        glassSheenLayer.locations = [0, 0.28, 0.72, 1]
        overlayView.layer.addSublayer(glassSheenLayer)

        accentGlowLayer.type = .radial
        accentGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        accentGlowLayer.endPoint = CGPoint(x: 1, y: 1)
        accentGlowLayer.locations = [0, 0.38, 1]
        overlayView.layer.addSublayer(accentGlowLayer)

        accentBarLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentBarLayer.endPoint = CGPoint(x: 1, y: 0.5)
        accentBarLayer.locations = [0, 0.52, 1]
        accentBarLayer.cornerRadius = 1.5
        overlayView.layer.addSublayer(accentBarLayer)

        innerStrokeLayer.fillColor = UIColor.clear.cgColor
        innerStrokeLayer.lineWidth = 1
        innerStrokeLayer.contentsScale = UIScreen.main.scale
        overlayView.layer.addSublayer(innerStrokeLayer)
    }

    private func registerForLifecycleChanges() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(transparencyOrContrastStatusDidChange),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(transparencyOrContrastStatusDidChange),
            name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let sizeChanged = lastLayoutSize != bounds.size
        let shouldRestartMotion = sizeChanged && motionRunning
        if shouldRestartMotion {
            removeAmbientAnimations()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        materialView.frame = bounds
        materialView.layer.cornerRadius = cornerRadius
        baseView.frame = materialView.contentView.bounds
        ambientView.frame = materialView.contentView.bounds
        overlayView.frame = materialView.contentView.bounds

        let materialBounds = baseView.bounds
        baseGradientLayer.frame = materialBounds
        depthGradientLayer.frame = materialBounds
        vignetteLayer.frame = materialBounds
        reactiveLightLayer.frame = overlayView.bounds
        glassSheenLayer.frame = overlayView.bounds

        layoutAuroraLayers(in: ambientView.bounds)
        layoutParticleLayers(in: ambientView.bounds)
        layoutAccentLayers(in: overlayView.bounds)

        innerStrokeLayer.frame = overlayView.bounds
        innerStrokeLayer.path = UIBezierPath(
            roundedRect: overlayView.bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: max(cornerRadius - 0.5, 0)
        ).cgPath

        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath

        CATransaction.commit()

        lastLayoutSize = bounds.size

        if window != nil {
            if shouldRestartMotion {
                motionRunning = false
            }
            startAnimations()
        }
    }

    private func layoutAuroraLayers(in bounds: CGRect) {
        guard !bounds.isEmpty else { return }

        let specs = auroraSpecs
        for (index, layer) in auroraLayers.enumerated() where index < specs.count {
            let spec = specs[index]
            let size = CGSize(
                width: max(bounds.width * spec.size.width, 180),
                height: max(bounds.height * spec.size.height, 150)
            )
            layer.bounds = CGRect(origin: .zero, size: size)
            layer.position = CGPoint(
                x: bounds.width * spec.center.x,
                y: bounds.height * spec.center.y
            )
            layer.cornerRadius = min(size.width, size.height) * 0.5
        }
    }

    private func layoutParticleLayers(in bounds: CGRect) {
        guard !bounds.isEmpty else { return }

        let pointGroups = normalizedParticlePointGroups
        let displayScale = max(UIScreen.main.scale, 1)

        for (groupIndex, layer) in particleLayers.enumerated() {
            layer.frame = bounds
            let path = UIBezierPath()
            guard groupIndex < pointGroups.count else {
                layer.path = path.cgPath
                continue
            }

            for (pointIndex, normalizedPoint) in pointGroups[groupIndex].enumerated() {
                let x = (bounds.width * normalizedPoint.x * displayScale).rounded() / displayScale
                let y = (bounds.height * normalizedPoint.y * displayScale).rounded() / displayScale
                let diameter: CGFloat = (pointIndex + groupIndex).isMultiple(of: 4) ? 2.4 : 1.45
                path.append(UIBezierPath(
                    ovalIn: CGRect(
                        x: x - diameter * 0.5,
                        y: y - diameter * 0.5,
                        width: diameter,
                        height: diameter
                    )
                ))
            }
            layer.path = path.cgPath
        }
    }

    private func layoutAccentLayers(in bounds: CGRect) {
        guard !bounds.isEmpty else { return }

        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let barWidth: CGFloat = 44
        let barLeading: CGFloat = 38
        let barX = isRTL ? bounds.width - barLeading - barWidth : barLeading
        accentBarLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: 3)

        let glowDiameter = max(min(bounds.width * 0.72, 220), 168)
        let glowX = isRTL
            ? bounds.width - glowDiameter + 62
            : -62
        accentGlowLayer.frame = CGRect(
            x: glowX,
            y: -glowDiameter * 0.42,
            width: glowDiameter,
            height: glowDiameter
        )

        accentBarLayer.isHidden = storedAccentMode != .bar
        accentGlowLayer.isHidden = storedAccentMode != .cornerGlow
    }

    // MARK: - Palette

    public func reapplyPalette() {
        let palette = makePalette()
        let isDark = traitCollection.userInterfaceStyle == .dark
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled

        materialView.effect = reduceTransparency
            ? nil
            : UIBlurEffect(style: .systemUltraThinMaterial)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        backgroundColor = .clear
        materialView.backgroundColor = .clear
        materialView.contentView.backgroundColor = .clear

        baseGradientLayer.colors = [
            palette.surfaceHighlight.cgColor,
            palette.surfaceMiddle.cgColor,
            palette.surfaceTail.cgColor
        ]
        baseGradientLayer.startPoint = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? CGPoint(x: 1, y: 0)
            : CGPoint(x: 0, y: 0)
        baseGradientLayer.endPoint = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? CGPoint(x: 0, y: 1)
            : CGPoint(x: 1, y: 1)

        depthGradientLayer.colors = [
            UIColor.clear.cgColor,
            palette.depth.withAlphaComponent(isDark ? 0.055 : 0.018).cgColor,
            palette.depth.withAlphaComponent(isDark ? 0.16 : 0.055).cgColor
        ]

        vignetteLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(isDark ? 0.13 : 0.032).cgColor
        ]

        for (index, layer) in auroraLayers.enumerated() {
            let color = palette.aurora[index % palette.aurora.count]
            let leadingAlpha: CGFloat = reduceTransparency
                ? (isDark ? 0.15 : 0.10)
                : (isDark ? 0.22 : 0.13)
            layer.colors = [
                color.withAlphaComponent(leadingAlpha).cgColor,
                color.withAlphaComponent(leadingAlpha * 0.32).cgColor,
                UIColor.clear.cgColor
            ]
            layer.opacity = 1
        }

        for (index, layer) in particleLayers.enumerated() {
            let color = palette.particle[index % palette.particle.count]
            layer.fillColor = color.cgColor
            layer.opacity = isDark ? 0.27 : 0.20
            layer.shadowColor = color.cgColor
            layer.shadowOpacity = isDark ? 0.14 : 0.07
            layer.shadowRadius = 1.5
            layer.shadowOffset = .zero
        }

        reactiveLightLayer.colors = [
            palette.reactiveLight.withAlphaComponent(isDark ? 0.16 : 0.21).cgColor,
            palette.reactiveLight.withAlphaComponent(isDark ? 0.045 : 0.055).cgColor,
            UIColor.clear.cgColor
        ]
        setReactiveLightCenter(defaultReactiveLightCenter, animated: false)

        glassSheenLayer.colors = [
            UIColor.white.withAlphaComponent(isDark ? 0.13 : 0.28).cgColor,
            UIColor.white.withAlphaComponent(isDark ? 0.035 : 0.075).cgColor,
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(isDark ? 0.02 : 0.035).cgColor
        ]
        glassSheenLayer.opacity = 0.72

        accentBarLayer.colors = [
            palette.accent.withAlphaComponent(0.38).cgColor,
            palette.accent.withAlphaComponent(0.82).cgColor,
            palette.accent.withAlphaComponent(0.22).cgColor
        ]

        let glowStrength = storedCornerGlowOpacityMultiplier
        accentGlowLayer.colors = [
            palette.accent.withAlphaComponent((isDark ? 0.17 : 0.115) * glowStrength).cgColor,
            palette.accent.withAlphaComponent((isDark ? 0.055 : 0.034) * glowStrength).cgColor,
            UIColor.clear.cgColor
        ]

        innerStrokeLayer.strokeColor = palette.stroke.cgColor
        layer.shadowOpacity = palette.shadowOpacity

        CATransaction.commit()
        setNeedsLayout()
    }

    private func makePalette() -> Palette {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let strongerContrast = UIAccessibility.isDarkerSystemColorsEnabled

        let fallbackAccent = UIColor(
            red: 0.50,
            green: 0.18,
            blue: 0.08,
            alpha: 1
        )
        let accent = resolvedColor(
            accentColorOverride ?? UIColor(named: "AppPrimaryClr") ?? fallbackAccent
        )

        let surfaceFallback = isDark
            ? UIColor(white: 0.105, alpha: 1)
            : UIColor(red: 0.992, green: 0.989, blue: 0.991, alpha: 1)
        let surfaceBase = resolvedColor(UIColor(named: "AppForgroundColr") ?? surfaceFallback)
        let highlight = blend(
            surfaceBase,
            with: .white,
            amount: isDark ? 0.075 : 0.18
        )
        let middle = blend(
            surfaceBase,
            with: accent,
            amount: isDark ? 0.068 : 0.026
        )
        let tail = blend(
            middle,
            with: accent,
            amount: isDark ? 0.043 : 0.016
        )

        let seaGlass = blend(accent, with: resolvedColor(.systemTeal), amount: 0.58)
        let twilight = blend(accent, with: resolvedColor(.systemIndigo), amount: 0.44)
        let warmLight = blend(accent, with: resolvedColor(.systemOrange), amount: 0.32)
        let particlePrimary = blend(accent, with: .white, amount: isDark ? 0.66 : 0.52)
        let particleSecondary = blend(seaGlass, with: .white, amount: isDark ? 0.62 : 0.68)

        return Palette(
            accent: accent,
            surfaceHighlight: highlight,
            surfaceMiddle: middle,
            surfaceTail: tail,
            depth: blend(surfaceBase, with: .black, amount: isDark ? 0.30 : 0.12),
            aurora: [warmLight, seaGlass, twilight],
            particle: [particlePrimary, particleSecondary, UIColor.white],
            reactiveLight: blend(accent, with: .white, amount: isDark ? 0.76 : 0.86),
            stroke: UIColor.white.withAlphaComponent(
                strongerContrast ? (isDark ? 0.24 : 0.92) : (isDark ? 0.13 : 0.76)
            ),
            shadowOpacity: isDark ? 0.22 : 0.085
        )
    }

    private func resolvedColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: traitCollection)
    }

    private func blend(_ baseColor: UIColor, with overlayColor: UIColor, amount: CGFloat) -> UIColor {
        let base = resolvedColor(baseColor)
        let overlay = resolvedColor(overlayColor)
        let t = min(max(amount, 0), 1)

        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var overlayRed: CGFloat = 0
        var overlayGreen: CGFloat = 0
        var overlayBlue: CGFloat = 0
        var overlayAlpha: CGFloat = 0

        guard base.getRed(
            &baseRed,
            green: &baseGreen,
            blue: &baseBlue,
            alpha: &baseAlpha
        ), overlay.getRed(
            &overlayRed,
            green: &overlayGreen,
            blue: &overlayBlue,
            alpha: &overlayAlpha
        ) else {
            return base
        }

        return UIColor(
            red: baseRed * (1 - t) + overlayRed * t,
            green: baseGreen * (1 - t) + overlayGreen * t,
            blue: baseBlue * (1 - t) + overlayBlue * t,
            alpha: baseAlpha * (1 - t) + overlayAlpha * t
        )
    }

    // MARK: - Ambient motion

    public func startAnimations() {
        guard window != nil,
              !bounds.isEmpty,
              !UIAccessibility.isReduceMotionEnabled,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              UIApplication.shared.applicationState == .active else {
            stopAnimations()
            return
        }

        let animationIsAlive = auroraLayers.first?.animation(forKey: auroraAnimationKey) != nil
        if motionRunning && animationIsAlive {
            installMotionEffectsIfNeeded()
            installTouchTrackerIfNeeded()
            return
        }

        removeAmbientAnimations()
        motionRunning = true
        installAuroraAnimations()
        installParticleAnimations()
        installLightAnimations()
        installMotionEffectsIfNeeded()
        installTouchTrackerIfNeeded()
    }

    public func stopAnimations() {
        motionRunning = false
        removeAmbientAnimations()
        removeMotionEffects()
        detachTouchTracker()
        resetReactiveDepth(animated: false)
    }

    private func removeAmbientAnimations() {
        auroraLayers.forEach { $0.removeAnimation(forKey: auroraAnimationKey) }
        particleLayers.forEach { $0.removeAnimation(forKey: particleAnimationKey) }
        reactiveLightLayer.removeAnimation(forKey: reactiveLightAnimationKey)
        glassSheenLayer.removeAnimation(forKey: sheenAnimationKey)
    }

    private func installAuroraAnimations() {
        let specs = auroraSpecs
        let hostTime = CACurrentMediaTime()

        for (index, layer) in auroraLayers.enumerated() where index < specs.count {
            let spec = specs[index]
            let origin = layer.position

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = [
                NSValue(cgPoint: origin),
                NSValue(cgPoint: CGPoint(
                    x: origin.x + spec.travel.width,
                    y: origin.y - spec.travel.height * 0.46
                )),
                NSValue(cgPoint: CGPoint(
                    x: origin.x - spec.travel.width * 0.54,
                    y: origin.y + spec.travel.height
                )),
                NSValue(cgPoint: origin)
            ]
            position.keyTimes = [0, 0.34, 0.72, 1]
            position.calculationMode = .cubic

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 1.045, 0.985, 1]
            scale.keyTimes = [0, 0.38, 0.74, 1]
            scale.calculationMode = .cubic

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.86, 1, 0.90, 0.86]
            opacity.keyTimes = [0, 0.32, 0.72, 1]
            opacity.calculationMode = .cubic

            let group = CAAnimationGroup()
            group.animations = [position, scale, opacity]
            group.duration = spec.duration
            group.beginTime = layer.convertTime(hostTime, from: nil) + spec.phase
            group.repeatCount = .greatestFiniteMagnitude
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = true
            layer.add(group, forKey: auroraAnimationKey)
        }
    }

    private func installParticleAnimations() {
        let hostTime = CACurrentMediaTime()

        for (index, layer) in particleLayers.enumerated() {
            let origin = layer.position
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let travelX = direction * (2.4 + CGFloat(index) * 0.8)
            let travelY = 2.1 + CGFloat(index) * 0.65

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = [
                NSValue(cgPoint: origin),
                NSValue(cgPoint: CGPoint(x: origin.x + travelX, y: origin.y - travelY)),
                NSValue(cgPoint: CGPoint(x: origin.x - travelX * 0.62, y: origin.y + travelY)),
                NSValue(cgPoint: origin)
            ]
            position.keyTimes = [0, 0.30, 0.70, 1]
            position.calculationMode = .cubic

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            let baseOpacity = layer.opacity
            opacity.values = [
                baseOpacity * 0.72,
                min(baseOpacity + 0.055, 0.36),
                baseOpacity * 0.82,
                baseOpacity * 0.72
            ]
            opacity.keyTimes = [0, 0.36, 0.74, 1]
            opacity.calculationMode = .cubic

            let group = CAAnimationGroup()
            group.animations = [position, opacity]
            group.duration = 18 + CFTimeInterval(index) * 4.2
            group.beginTime = layer.convertTime(hostTime, from: nil) + CFTimeInterval(index) * 0.65
            group.repeatCount = .greatestFiniteMagnitude
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = true
            layer.add(group, forKey: particleAnimationKey)
        }
    }

    private func installLightAnimations() {
        let reactiveBreath = CAKeyframeAnimation(keyPath: "opacity")
        reactiveBreath.values = [0.70, 0.92, 0.76, 0.70]
        reactiveBreath.keyTimes = [0, 0.38, 0.74, 1]
        reactiveBreath.duration = 9.6
        reactiveBreath.repeatCount = .greatestFiniteMagnitude
        reactiveBreath.calculationMode = .cubic
        reactiveBreath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        reactiveLightLayer.add(reactiveBreath, forKey: reactiveLightAnimationKey)

        let sheenBreath = CAKeyframeAnimation(keyPath: "opacity")
        sheenBreath.values = [0.60, 0.78, 0.66, 0.60]
        sheenBreath.keyTimes = [0, 0.30, 0.72, 1]
        sheenBreath.duration = 12.8
        sheenBreath.repeatCount = .greatestFiniteMagnitude
        sheenBreath.calculationMode = .cubic
        sheenBreath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glassSheenLayer.add(sheenBreath, forKey: sheenAnimationKey)
    }

    // MARK: - Responsive depth

    private func installMotionEffectsIfNeeded() {
        guard parallaxMotionEffect == nil,
              !UIAccessibility.isReduceMotionEnabled else { return }

        let horizontal = UIInterpolatingMotionEffect(
            keyPath: "center.x",
            type: .tiltAlongHorizontalAxis
        )
        horizontal.minimumRelativeValue = -2.8
        horizontal.maximumRelativeValue = 2.8

        let vertical = UIInterpolatingMotionEffect(
            keyPath: "center.y",
            type: .tiltAlongVerticalAxis
        )
        vertical.minimumRelativeValue = -2.1
        vertical.maximumRelativeValue = 2.1

        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        ambientView.addMotionEffect(group)
        parallaxMotionEffect = group
    }

    private func removeMotionEffects() {
        if let parallaxMotionEffect {
            ambientView.removeMotionEffect(parallaxMotionEffect)
        }
        parallaxMotionEffect = nil
    }

    private func installTouchTrackerIfNeeded() {
        guard touchRecognizer == nil,
              !UIAccessibility.isReduceMotionEnabled else { return }

        var candidate = superview
        while let current = candidate, !current.isUserInteractionEnabled {
            candidate = current.superview
        }

        guard let host = candidate, host.window != nil else { return }

        let recognizer = PPHeroPassiveTouchRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        recognizer.onUpdate = { [weak self, weak host] point, state in
            guard let self, let host else { return }
            self.handleTouch(at: point, in: host, state: state)
        }
        host.addGestureRecognizer(recognizer)
        touchHost = host
        touchRecognizer = recognizer
    }

    private func detachTouchTracker() {
        if let recognizer = touchRecognizer {
            touchHost?.removeGestureRecognizer(recognizer)
        }
        touchRecognizer = nil
        touchHost = nil
        touchResponseActive = false
    }

    private func handleTouch(
        at point: CGPoint,
        in host: UIView,
        state: UIGestureRecognizer.State
    ) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let localPoint = convert(point, from: host)
        let hitBounds = bounds.insetBy(dx: -4, dy: -4)

        switch state {
        case .began, .changed:
            if !hitBounds.contains(localPoint) && !touchResponseActive {
                return
            }
            touchResponseActive = true
            applyReactiveDepth(at: localPoint)
        case .ended, .cancelled, .failed:
            guard touchResponseActive else { return }
            touchResponseActive = false
            resetReactiveDepth(animated: true)
        default:
            break
        }
    }

    private func applyReactiveDepth(at localPoint: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let normalized = CGPoint(
            x: min(max(localPoint.x / bounds.width, 0), 1),
            y: min(max(localPoint.y / bounds.height, 0), 1)
        )
        setReactiveLightCenter(normalized, animated: true)

        let centeredX = normalized.x - 0.5
        let centeredY = normalized.y - 0.5
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 900
        transform = CATransform3DTranslate(
            transform,
            centeredX * 4.4,
            centeredY * 3.2,
            0
        )
        transform = CATransform3DRotate(transform, centeredY * 0.022, 1, 0, 0)
        transform = CATransform3DRotate(transform, -centeredX * 0.022, 0, 1, 0)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        ambientView.layer.transform = transform
        CATransaction.commit()
    }

    private func resetReactiveDepth(animated: Bool) {
        let duration: CFTimeInterval = animated && !UIAccessibility.isReduceMotionEnabled ? 0.46 : 0

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        ambientView.layer.transform = CATransform3DIdentity
        setReactiveLightCenter(defaultReactiveLightCenter, animated: animated)
        CATransaction.commit()
    }

    private func setReactiveLightCenter(_ center: CGPoint, animated: Bool) {
        let clampedCenter = CGPoint(
            x: min(max(center.x, 0.04), 0.96),
            y: min(max(center.y, 0.04), 0.96)
        )
        let endPoint = CGPoint(
            x: min(clampedCenter.x + 0.48, 1.42),
            y: min(clampedCenter.y + 0.58, 1.48)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        reactiveLightLayer.startPoint = clampedCenter
        reactiveLightLayer.endPoint = endPoint
        CATransaction.commit()
    }

    private var defaultReactiveLightCenter: CGPoint {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? CGPoint(x: 0.24, y: 0.10)
            : CGPoint(x: 0.76, y: 0.10)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === touchRecognizer else { return true }
        let localPoint = touch.location(in: self)
        return bounds.insetBy(dx: -4, dy: -4).contains(localPoint)
    }

    // MARK: - Lifecycle and accessibility changes

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopAnimations()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setNeedsLayout()
            layoutIfNeeded()
            startAnimations()
        }
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if motionRunning {
            detachTouchTracker()
            installTouchTrackerIfNeeded()
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection == nil ||
            traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            reapplyPalette()
        }
    }

    @objc private func reduceMotionStatusDidChange() {
        if UIAccessibility.isReduceMotionEnabled {
            stopAnimations()
        } else {
            startAnimations()
        }
    }

    @objc private func transparencyOrContrastStatusDidChange() {
        reapplyPalette()
    }

    @objc private func applicationDidBecomeActive() {
        startAnimations()
    }

    @objc private func applicationWillResignActive() {
        stopAnimations()
    }

    @objc private func powerStateDidChange() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopAnimations()
        } else {
            startAnimations()
        }
    }

    // MARK: - Deterministic art direction

    private var auroraSpecs: [AuroraSpec] {
        [
            AuroraSpec(
                center: CGPoint(x: 0.10, y: 0.02),
                size: CGSize(width: 0.92, height: 1.42),
                travel: CGSize(width: 8, height: 5),
                duration: 26,
                phase: 0
            ),
            AuroraSpec(
                center: CGPoint(x: 0.84, y: 0.88),
                size: CGSize(width: 0.86, height: 1.28),
                travel: CGSize(width: 7, height: 6),
                duration: 31,
                phase: 1.6
            ),
            AuroraSpec(
                center: CGPoint(x: 0.58, y: 0.20),
                size: CGSize(width: 0.68, height: 1.08),
                travel: CGSize(width: 5, height: 4),
                duration: 23,
                phase: 3.2
            )
        ]
    }

    private var normalizedParticlePointGroups: [[CGPoint]] {
        [
            [
                CGPoint(x: 0.08, y: 0.31),
                CGPoint(x: 0.23, y: 0.72),
                CGPoint(x: 0.47, y: 0.17),
                CGPoint(x: 0.71, y: 0.58),
                CGPoint(x: 0.91, y: 0.27)
            ],
            [
                CGPoint(x: 0.14, y: 0.84),
                CGPoint(x: 0.34, y: 0.43),
                CGPoint(x: 0.58, y: 0.81),
                CGPoint(x: 0.77, y: 0.22),
                CGPoint(x: 0.86, y: 0.68)
            ],
            [
                CGPoint(x: 0.05, y: 0.57),
                CGPoint(x: 0.29, y: 0.12),
                CGPoint(x: 0.53, y: 0.52),
                CGPoint(x: 0.67, y: 0.91),
                CGPoint(x: 0.96, y: 0.48)
            ]
        ]
    }
}
