//
//  PPScannerView.swift
//  PurePetsAdmin
//
//  Created from absolute first principles for PurePets Sovereign POS.
//  Category-defining Cheque & Financial Document Optical Scanner.
//

import SwiftUI
import AVFoundation
import Vision
@preconcurrency import CoreMotion
import PhotosUI

// MARK: - Scanned Cheque Model

public struct PPScannedCheque: Identifiable, Sendable, Equatable {
    public static func == (lhs: PPScannedCheque, rhs: PPScannedCheque) -> Bool {
        lhs.id == rhs.id
    }

    public let id: UUID
    public let image: UIImage
    public var chequeNumber: String
    public var bankName: String
    public var amount: Double?
    public var dateString: String?
    public var rawText: String
    public let scannedAt: Date

    public init(
        id: UUID = UUID(),
        image: UIImage,
        chequeNumber: String = "",
        bankName: String = "",
        amount: Double? = nil,
        dateString: String? = nil,
        rawText: String = "",
        scannedAt: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.chequeNumber = chequeNumber
        self.bankName = bankName
        self.amount = amount
        self.dateString = dateString
        self.rawText = rawText
        self.scannedAt = scannedAt
    }
}

// MARK: - Scanner Button Style

private struct ScannerButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Scanner State Phase

public enum PPScannerPhase: Equatable {
    case starting
    case scanning
    case autoCapturing(progress: CGFloat)
    case processingImage
    case reviewing(PPScannedCheque)
    case permissionDenied
    case error(String)
}

// MARK: - Scanner Visual Language

private enum PPScannerVisual {
    static let accent = Color(uiColor: .ppWarning)
    static let ready = Color(uiColor: .ppSuccess)
    static let danger = Color(uiColor: .ppError)
    static let chrome = Color.black.opacity(0.72)
    static let chromeRaised = Color.black.opacity(0.82)
    static let hairline = Color.white.opacity(0.16)
    static let secondaryText = Color.white.opacity(0.68)
}

// MARK: - Visual Focus Indicator

private struct PPScannerFocusIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.35
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(red: 0.96, green: 0.62, blue: 0.04), lineWidth: 1.5)
                .frame(width: 54, height: 54)
            
            Circle()
                .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                .frame(width: 4, height: 4)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            guard !reduceMotion else {
                scale = 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    opacity = 0.0
                }
                return
            }
            withAnimation(.easeOut(duration: 0.25)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.6)) {
                opacity = 0.0
            }
        }
    }
}

// MARK: - Master PPScanner View

public struct PPScannerView: View {
    let cartTotal: Double
    let onAttach: (PPScannedCheque) -> Void
    let onDismiss: () -> Void

    @StateObject private var engine = PPScannerEngine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: PPScannerPhase = .starting
    @State private var isShowingPhotoPicker = false
    @State private var focusTapTrigger: UUID = UUID()

    public init(
        cartTotal: Double = 0.0,
        onAttach: @escaping (PPScannedCheque) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.cartTotal = cartTotal
        self.onAttach = onAttach
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .permissionDenied:
                permissionDeniedView
            case .error(let message):
                errorView(message)
            case .reviewing(let cheque):
                PPScannerReviewFlightDeck(
                    cheque: cheque,
                    cartTotal: cartTotal,
                    onRetake: {
                        withAnimation(phaseAnimation) {
                            phase = .starting
                            engine.resume()
                        }
                    },
                    onConfirm: { confirmedCheque in
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onAttach(confirmedCheque)
                    }
                )
            case .processingImage:
                processingImageView
            case .starting, .scanning, .autoCapturing:
                liveScannerDeck
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            engine.onCameraReady = {
                guard phase == .starting else { return }
                withAnimation(phaseAnimation) {
                    phase = .scanning
                }
            }
            engine.onPermissionDenied = {
                withAnimation(phaseAnimation) {
                    phase = .permissionDenied
                }
            }
            engine.onCameraUnavailable = {
                withAnimation(phaseAnimation) {
                    phase = .error(
                        Language.get(
                            "PPScanner_CameraUnavailable",
                            alter: "تعذر تشغيل الكاميرا. حاول مجدداً أو اختر صورة شيك."
                        )
                    )
                }
            }
            engine.onCaptureComplete = { capturedCheque in
                switch phase {
                case .starting, .scanning, .autoCapturing, .processingImage:
                    engine.stop()
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(phaseAnimation) {
                        self.phase = .reviewing(capturedCheque)
                    }
                case .reviewing, .permissionDenied, .error:
                    break
                }
            }
            engine.onAutoCaptureProgress = { progress in
                switch phase {
                case .reviewing, .processingImage, .permissionDenied, .error:
                    return
                case .starting, .scanning, .autoCapturing:
                    break
                }
                if progress >= 1.0 {
                    self.phase = .autoCapturing(progress: 1.0)
                } else if progress > 0.0 {
                    self.phase = .autoCapturing(progress: progress)
                } else {
                    self.phase = .scanning
                }
            }
            engine.checkPermissionsAndStart()
        }
        .onDisappear {
            engine.stop()
            engine.onCameraReady = nil
            engine.onPermissionDenied = nil
            engine.onCameraUnavailable = nil
            engine.onCaptureComplete = nil
            engine.onAutoCaptureProgress = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                switch phase {
                case .permissionDenied where AVCaptureDevice.authorizationStatus(for: .video) == .authorized:
                    phase = .starting
                    engine.checkPermissionsAndStart()
                case .starting, .scanning, .autoCapturing:
                    phase = .starting
                    engine.checkPermissionsAndStart()
                case .processingImage, .reviewing, .permissionDenied, .error:
                    break
                }
            case .inactive, .background:
                engine.stop()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $isShowingPhotoPicker, onDismiss: {
            switch phase {
            case .starting, .scanning, .autoCapturing:
                phase = .starting
                engine.resume()
            case .processingImage, .reviewing, .permissionDenied, .error:
                break
            }
        }) {
            PPPhotoPickerRepresentable { selectedImage in
                isShowingPhotoPicker = false
                if let selectedImage {
                    phase = .processingImage
                    engine.processImportedImage(selectedImage) { parsedCheque in
                        engine.stop()
                        withAnimation(phaseAnimation) {
                            self.phase = .reviewing(parsedCheque)
                        }
                    }
                }
            }
        }
    }

    private var phaseAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)
    }

    // MARK: - Live Scanner Deck

    private var liveScannerDeck: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            let safeArea = proxy.safeAreaInsets
            let rSize = reticleSize(for: screenSize)
            let isLandscape = screenSize.width > screenSize.height

            ZStack {
                PPScannerCameraPreview(session: engine.session)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { factor in
                                engine.applyPinchZoom(factor)
                            }
                            .onEnded { _ in
                                engine.finalizePinchZoom()
                            }
                    )
                    .onTapGesture { location in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        engine.focus(at: location, in: screenSize)
                        focusTapTrigger = UUID()
                    }

                scannerAtmosphere
                    .ignoresSafeArea()

                if let pt = engine.focusPoint {
                    PPScannerFocusIndicator()
                        .position(pt)
                        .id(focusTapTrigger)
                        .allowsHitTesting(false)
                }

                if isLandscape {
                    landscapeScannerLayout(
                        safeArea: safeArea,
                        screenSize: screenSize,
                        reticleSize: rSize
                    )
                } else {
                    portraitScannerLayout(
                        safeArea: safeArea,
                        reticleSize: rSize
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    private var scannerAtmosphere: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.76),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func portraitScannerLayout(
        safeArea: EdgeInsets,
        reticleSize: CGSize
    ) -> some View {
        VStack(spacing: 0) {
            scannerTopBar
                .padding(.top, max(safeArea.top, 8) + 8)
                .padding(.horizontal, 16)

            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 16)

            scannerStageCluster(size: reticleSize)

            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 16)

            captureDock
                .padding(.horizontal, 14)
                .padding(.bottom, max(safeArea.bottom, 10) + 8)
        }
    }

    private func landscapeScannerLayout(
        safeArea: EdgeInsets,
        screenSize: CGSize,
        reticleSize: CGSize
    ) -> some View {
        VStack(spacing: 8) {
            scannerTopBar
                .padding(.top, max(safeArea.top, 6) + 4)
                .padding(.horizontal, 16)

            HStack(spacing: 16) {
                scannerStageCluster(size: reticleSize)
                    .frame(maxWidth: .infinity)

                captureDock
                    .frame(width: min(310, screenSize.width * 0.38))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, max(safeArea.bottom, 6) + 6)
        }
    }

    private func scannerStageCluster(size: CGSize) -> some View {
        VStack(spacing: 10) {
            PPScannerReticle(
                size: size,
                isLocked: isCaptureReady,
                isLowLight: engine.isLowLight,
                isSteady: engine.isDeviceSteady,
                autoCaptureProgress: autoCaptureProgress
            )
            .allowsHitTesting(false)

            scannerSignalRail

            ZStack {
                Color.clear
                if let detected = engine.detectedPreviewText, !detected.isEmpty {
                    liveFieldHUD(text: detected)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .frame(height: 38)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: engine.isChequeDetected
            )
        }
    }

    private var autoCaptureProgress: CGFloat {
        if case .autoCapturing(let p) = phase {
            return p
        }
        return 0.0
    }

    private var isCaptureReady: Bool {
        phase != .starting &&
        engine.isChequeDetected &&
        !engine.isLowLight &&
        engine.isDeviceSteady
    }

    private func reticleSize(for screenSize: CGSize) -> CGSize {
        let isLandscape = screenSize.width > screenSize.height
        let horizontalAllowance: CGFloat = dynamicTypeSize.isAccessibilitySize ? 48 : 28
        let widthLimit = isLandscape
            ? min(screenSize.width * 0.56, 620)
            : min(screenSize.width - horizontalAllowance, 520)
        let heightLimit = isLandscape
            ? max(108, screenSize.height - 220)
            : max(132, screenSize.height * 0.26)
        let height = min(widthLimit / 2.18, heightLimit)
        return CGSize(width: height * 2.18, height: height)
    }

    // MARK: - Scanner Identity Bar

    private var scannerTopBar: some View {
        ZStack {
            HStack {
                // Native close affordance remains isolated from camera telemetry.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(PPScannerVisual.chrome, in: Circle())
                        .overlay(Circle().strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75))
                }
                .buttonStyle(ScannerButtonPressStyle())
                .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
                .accessibilityHint(Language.get("PPScanner_CloseHint", alter: "إغلاق ماسح الشيك والعودة إلى نقطة البيع"))

                Spacer(minLength: 120)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    engine.toggleTorch()
                } label: {
                    Image(systemName: engine.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(engine.isTorchOn ? PPScannerVisual.accent : .white)
                        .frame(width: 48, height: 48)
                        .background(
                            engine.isTorchOn
                                ? PPScannerVisual.accent.opacity(0.18)
                                : PPScannerVisual.chrome,
                            in: Circle()
                        )
                        .overlay(
                            Circle().strokeBorder(
                                engine.isTorchOn ? PPScannerVisual.accent.opacity(0.72) : PPScannerVisual.hairline,
                                lineWidth: 0.75
                            )
                        )
                }
                .buttonStyle(ScannerButtonPressStyle())
                .disabled(!engine.isTorchAvailable || phase == .starting)
                .accessibilityLabel(Language.get("PPScanner_Torch", alter: "إضاءة الفلاش"))
                .accessibilityValue(
                    engine.isTorchOn
                        ? Language.get("On", alter: "مفعّلة")
                        : Language.get("Off", alter: "متوقفة")
                )
                .accessibilityHint(Language.get("PPScanner_TorchHint", alter: "تبديل إضاءة الكاميرا"))
            }

            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PPScannerVisual.accent.opacity(0.16))
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PPScannerVisual.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("PPScanner_Title", alter: "ماسح الشيكات"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(Language.get("PPScanner_OnDevice", alter: "معالجة خاصة على الجهاز"))
                            .font(AdminType.caption2)
                            .foregroundStyle(PPScannerVisual.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .background(PPScannerVisual.chrome, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75))
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 176 : 230)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    // MARK: - Readiness Rail

    private var scannerSignalRail: some View {
        HStack(spacing: 0) {
            scannerSignal(
                icon: engine.isLowLight ? "sun.haze.fill" : "sun.max.fill",
                title: Language.get("PPScanner_SignalLight", alter: "الإضاءة"),
                isReady: !engine.isLowLight
            )

            scannerSignalDivider

            scannerSignal(
                icon: engine.isChequeDetected ? "checkmark.square.fill" : "viewfinder",
                title: Language.get("PPScanner_SignalCheque", alter: "الشيك"),
                isReady: engine.isChequeDetected
            )

            scannerSignalDivider

            scannerSignal(
                icon: engine.isDeviceSteady ? "gyroscope" : "waveform.path",
                title: Language.get("PPScanner_SignalStability", alter: "الثبات"),
                isReady: engine.isDeviceSteady
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(PPScannerVisual.chrome, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75)
        )
    }

    private func scannerSignal(icon: String, title: String, isReady: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isReady ? PPScannerVisual.ready : PPScannerVisual.accent)
                .frame(width: 24, height: 24)
                .background(
                    (isReady ? PPScannerVisual.ready : PPScannerVisual.accent).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(
                    isReady
                        ? Language.get("PPScanner_Ready", alter: "جاهز")
                        : Language.get("PPScanner_Adjust", alter: "يحتاج ضبطاً")
                )
                .font(AdminType.caption2)
                .foregroundStyle(PPScannerVisual.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            isReady
                ? Language.get("PPScanner_Ready", alter: "جاهز")
                : Language.get("PPScanner_Adjust", alter: "يحتاج ضبطاً")
        )
    }

    private var scannerSignalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    // MARK: - Live Field Recognition HUD

    private func liveFieldHUD(text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PPScannerVisual.ready)

            Text(text)
                .font(AdminType.captionBold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 34)
        .background(PPScannerVisual.ready.opacity(0.15), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(PPScannerVisual.ready.opacity(0.44), lineWidth: 0.75)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("PPScanner_ChequeDetected", alter: "تم التعرف على الشيك"))
        .accessibilityValue(text)
    }

    // MARK: - Capture Dock

    private var captureDock: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: isCaptureReady ? "checkmark.circle.fill" : "scope")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isCaptureReady ? PPScannerVisual.ready : PPScannerVisual.accent)

                        Text(guidanceText)
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(.white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }

                    Text(guidanceDetail)
                        .font(AdminType.caption2)
                        .foregroundStyle(PPScannerVisual.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 4)

                if cartTotal > 0, !dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Language.get("PPScanner_SaleTotal", alter: "إجمالي البيع"))
                            .font(AdminType.caption2)
                            .foregroundStyle(PPScannerVisual.secondaryText)

                        Text("\(String(format: "%.2f", cartTotal)) \(Language.get("QAR", alter: "ر.ق"))")
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }

            HStack(spacing: 14) {
                Button {
                    openPhotoPicker()
                } label: {
                    scannerDockTool(
                        icon: "photo.on.rectangle",
                        label: Language.get("PPScanner_Gallery", alter: "الصور")
                    )
                }
                .buttonStyle(ScannerButtonPressStyle())
                .accessibilityLabel(Language.get("PPScanner_Gallery", alter: "من ألبوم الصور"))
                .accessibilityHint(Language.get("PPScanner_GalleryHint", alter: "اختيار صورة شيك موجودة على الجهاز"))

                Spacer(minLength: 0)

                Button {
                    guard phase != .starting else { return }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    withAnimation(phaseAnimation) {
                        phase = .processingImage
                    }
                    engine.capturePhotoManually()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.26), lineWidth: 3)
                            .frame(width: 82, height: 82)

                        Circle()
                            .trim(from: 0, to: max(autoCaptureProgress, 0.002))
                            .stroke(
                                engine.isChequeDetected ? PPScannerVisual.ready : PPScannerVisual.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 82, height: 82)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 66, height: 66)
                            .overlay(
                                Image(systemName: engine.isChequeDetected ? "doc.viewfinder.fill" : "camera.fill")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.82))
                            )
                            .shadow(color: Color.black.opacity(0.36), radius: 7, x: 0, y: 3)
                    }
                }
                .buttonStyle(ScannerButtonPressStyle())
                .disabled(phase == .starting)
                .accessibilityLabel(Language.get("PPScanner_ManualCapture", alter: "التقاط يدوي"))
                .accessibilityValue(
                    isCaptureReady
                        ? Language.get("PPScanner_Ready", alter: "جاهز")
                        : Language.get("PPScanner_Adjust", alter: "يحتاج ضبطاً")
                )
                .accessibilityHint(Language.get("PPScanner_ManualCaptureHint", alter: "التقاط صورة الشيك الآن ومراجعة البيانات"))

                Spacer(minLength: 0)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    engine.toggleZoomLevel()
                } label: {
                    scannerDockTool(
                        icon: "plus.magnifyingglass",
                        label: String(format: "%.0fx", engine.currentZoom),
                        forceLTR: true
                    )
                }
                .buttonStyle(ScannerButtonPressStyle())
                .disabled(phase == .starting)
                .accessibilityLabel(Language.get("PPScanner_Zoom", alter: "درجة التقريب"))
                .accessibilityValue(String(format: "%.0fx", engine.currentZoom))
                .accessibilityHint(Language.get("PPScanner_ZoomHint", alter: "التبديل بين التقريب العادي والمزدوج"))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(PPScannerVisual.chromeRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 24, x: 0, y: 12)
    }

    private func scannerDockTool(icon: String, label: String, forceLTR: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(AdminType.caption2Bold)
                .foregroundStyle(PPScannerVisual.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .environment(\.layoutDirection, forceLTR ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))
        }
        .frame(minWidth: 56, minHeight: 52)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }

    private func openPhotoPicker() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        engine.stop()
        isShowingPhotoPicker = true
    }

    private var guidanceText: String {
        if phase == .starting {
            return Language.get("PPScanner_PreparingCamera", alter: "جارٍ تجهيز الكاميرا")
        } else if engine.isLowLight {
            return Language.get("PPScanner_LowLight", alter: "الإضاءة منخفضة")
        } else if !engine.isDeviceSteady {
            return Language.get("PPScanner_HoldSteady", alter: "ثبّت الكاميرا فوق الشيك للتركيز")
        } else if isCaptureReady {
            return Language.get("PPScanner_ReadyToCapture", alter: "تم ضبط الشيك • جاري الالتقاط التلقائي...")
        } else {
            return Language.get("PPScanner_AlignCheque", alter: "وجّه الشيك داخل الإطار المخصص")
        }
    }

    private var guidanceDetail: String {
        if phase == .starting {
            return Language.get("PPScanner_PreparingCameraHint", alter: "سيبدأ المسح البصري بعد اتصال الكاميرا")
        } else if engine.isLowLight {
            return Language.get("PPScanner_LightHint", alter: "أضف إضاءة ناعمة وتجنب انعكاس الضوء على الشيك")
        } else if !engine.isDeviceSteady {
            return Language.get("PPScanner_StabilityHint", alter: "قرّب الهاتف قليلاً وثبّت الحواف داخل مجال الرؤية")
        } else if isCaptureReady {
            return Language.get("PPScanner_AutoCaptureHint", alter: "اثبت للحظة؛ سيتم الالتقاط تلقائياً عند اكتمال القراءة")
        } else {
            return Language.get("PPScanner_FrameHint", alter: "أظهر الحواف الأربع واجعل سطر MICR بمحاذاة المسار السفلي")
        }
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        scannerRecoveryView(
            icon: "camera.fill",
            tint: PPScannerVisual.accent,
            title: Language.get("PPScanner_CameraPermissionRequired", alter: "مطلوب إذن استخدام الكاميرا"),
            message: Language.get(
                "PPScanner_CameraPermissionDesc",
                alter: "اسمح باستخدام الكاميرا لمسح الشيك، أو اختر صورة موجودة من الجهاز."
            ),
            primaryTitle: Language.get("Settings", alter: "فتح الإعدادات"),
            primaryIcon: "gearshape.fill",
            primaryAction: {
                guard let url = URL(string: UIApplication.openSettingsURLString),
                      UIApplication.shared.canOpenURL(url) else { return }
                UIApplication.shared.open(url)
            },
            secondaryTitle: Language.get("PPScanner_Gallery", alter: "اختيار صورة"),
            secondaryIcon: "photo.on.rectangle",
            secondaryAction: openPhotoPicker
        )
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        scannerRecoveryView(
            icon: "exclamationmark.triangle.fill",
            tint: PPScannerVisual.danger,
            title: Language.get("PPScanner_CameraErrorTitle", alter: "تعذر بدء المسح"),
            message: message,
            primaryTitle: Language.get("PPScanner_Retry", alter: "إعادة المحاولة"),
            primaryIcon: "arrow.clockwise",
            primaryAction: {
                withAnimation(phaseAnimation) {
                    phase = .starting
                }
                engine.checkPermissionsAndStart()
            },
            secondaryTitle: Language.get("PPScanner_Gallery", alter: "اختيار صورة"),
            secondaryIcon: "photo.on.rectangle",
            secondaryAction: openPhotoPicker
        )
    }

    private var processingImageView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [PPScannerVisual.accent.opacity(0.18), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(PPScannerVisual.accent.opacity(0.12))
                        .frame(width: 86, height: 86)

                    ProgressView()
                        .controlSize(.large)
                        .tint(PPScannerVisual.accent)
                }

                Text(Language.get("PPScanner_Processing", alter: "جارٍ قراءة بيانات الشيك"))
                    .font(AdminType.title3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(Language.get("PPScanner_ProcessingHint", alter: "يتم تحليل الصورة على هذا الجهاز قبل عرضها للمراجعة"))
                    .font(AdminType.subheadline)
                    .foregroundStyle(PPScannerVisual.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(Language.get("Cancel", alter: "إلغاء")) {
                    onDismiss()
                }
                .font(AdminType.calloutBold)
                .foregroundStyle(.white)
                .frame(minWidth: 96, minHeight: 44)
                .background(Color.white.opacity(0.10), in: Capsule(style: .continuous))
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .background(PPScannerVisual.chromeRaised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75)
            )
            .padding(20)
        }
        .accessibilityElement(children: .contain)
    }

    private func scannerRecoveryView(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        primaryTitle: String,
        primaryIcon: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryIcon: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [tint.opacity(0.18), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 72, height: 72)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 7) {
                    Text(title)
                        .font(AdminType.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(AdminType.subheadline)
                        .foregroundStyle(PPScannerVisual.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primaryIcon)
                            .font(AdminType.calloutBold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.black)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(ScannerButtonPressStyle())

                    Button(action: secondaryAction) {
                        Label(secondaryTitle, systemImage: secondaryIcon)
                            .font(AdminType.calloutBold)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(ScannerButtonPressStyle())
                }

                Button(Language.get("Cancel", alter: "إلغاء")) {
                    onDismiss()
                }
                .font(AdminType.calloutBold)
                .foregroundStyle(PPScannerVisual.secondaryText)
                .frame(minWidth: 88, minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 390)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .background(PPScannerVisual.chromeRaised, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(PPScannerVisual.hairline, lineWidth: 0.75)
            )
            .padding(20)
        }
    }
}

// MARK: - Optical Reticle & Scanning Overlay

private struct PPScannerReticle: View {
    let size: CGSize
    let isLocked: Bool
    let isLowLight: Bool
    let isSteady: Bool
    let autoCaptureProgress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPhase: CGFloat = 0

    private var accentColor: Color {
        isLocked ? PPScannerVisual.ready : PPScannerVisual.accent
    }

    private var accessibilityState: String {
        if isLocked {
            return Language.get("PPScanner_ReadyToCapture", alter: "جاهز للالتقاط")
        } else if isLowLight {
            return Language.get("PPScanner_LowLight", alter: "الإضاءة منخفضة")
        } else if !isSteady {
            return Language.get("PPScanner_HoldStill", alter: "ثبّت الهاتف")
        } else {
            return Language.get("PPScanner_AlignCheque", alter: "وجّه الشيك داخل الإطار")
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(isLocked ? 0.08 : 0.15))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accentColor.opacity(0.92), accentColor.opacity(0.30), accentColor.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isLocked ? 1.8 : 1.0
                )

            PPScannerCornerBrackets(color: accentColor, cornerLength: 30, thickness: 3.2)

            if !reduceMotion && !isLocked {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, accentColor.opacity(0.92), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1.5)
                        .shadow(color: accentColor.opacity(0.55), radius: 5)
                        .offset(y: 14 + scanPhase * max(0, geo.size.height - 52))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(index == 2 ? 0.76 : 0.28))
                            .frame(width: index == 2 ? 18 : 6, height: 2)
                    }
                }
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 11, weight: .bold))
                    Text(Language.get("PPScanner_MICRTrack", alter: "شريط التشفير المغناطيسي MICR"))
                        .font(AdminType.caption2Bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(PPScannerVisual.chromeRaised)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(accentColor.opacity(0.48))
                        .frame(height: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if autoCaptureProgress > 0 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .trim(from: 0, to: min(max(autoCaptureProgress, 0), 1))
                    .stroke(
                        PPScannerVisual.ready,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: PPScannerVisual.ready.opacity(0.42), radius: 6)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: accentColor.opacity(isLocked ? 0.20 : 0.10), radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("PPScanner_CaptureFrame", alter: "إطار التقاط الشيك"))
        .accessibilityValue(accessibilityState)
        .onAppear {
            startScanningAnimationIfNeeded()
        }
        .onChange(of: reduceMotion) { _, _ in
            scanPhase = 0
            startScanningAnimationIfNeeded()
        }
    }

    private func startScanningAnimationIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            scanPhase = 1.0
        }
    }
}

// MARK: - Laser Corner Brackets

private struct PPScannerCornerBrackets: View {
    let color: Color
    let cornerLength: CGFloat
    let thickness: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                // Top-Left
                path.move(to: CGPoint(x: 0, y: cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))

                // Top-Right
                path.move(to: CGPoint(x: w - cornerLength, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: cornerLength))

                // Bottom-Left
                path.move(to: CGPoint(x: 0, y: h - cornerLength))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: cornerLength, y: h))

                // Bottom-Right
                path.move(to: CGPoint(x: w - cornerLength, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - cornerLength))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Post-Capture Review Flight Deck

private struct PPScannerReviewFlightDeck: View {
    @State var cheque: PPScannedCheque
    let cartTotal: Double
    let onRetake: () -> Void
    let onConfirm: (PPScannedCheque) -> Void

    @State private var editedChequeNumber: String = ""
    @State private var editedBankName: String = ""
    @State private var editedAmount: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("PPScanner_ReviewTitle", alter: "مراجعة بيانات الشيك"))
                            .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("PPScanner_ReviewSubtitle", alter: "تأكد من وضوح صورة الشيك وصحة البيانات"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Button {
                        onRetake()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("PPScanner_Retake", alter: "إعادة المسح"))
                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                        }
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AdminSurface.control, in: Capsule(style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                // High-Fidelity Cropped Cheque Image Preview
                Image(uiImage: cheque.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.40), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 18)

                // Financial Data Extraction Card
                VStack(spacing: 14) {
                    // Cheque Number
                    dataInputRow(
                        title: Language.get("PPScanner_ChequeNumber", alter: "رقم الشيك"),
                        icon: "number",
                        text: $editedChequeNumber,
                        placeholder: Language.get("PPScanner_ChequeNumberPlaceholder", alter: "مثال: 004821")
                    )

                    Divider().background(AdminSurface.hairline)

                    // Bank Name
                    dataInputRow(
                        title: Language.get("PPScanner_BankName", alter: "اسم البنك"),
                        icon: "building.columns.fill",
                        text: $editedBankName,
                        placeholder: Language.get("PPScanner_BankNamePlaceholder", alter: "مثال: بنك قطر الوطني")
                    )

                    Divider().background(AdminSurface.hairline)

                    // Cheque Amount
                    VStack(alignment: .leading, spacing: 6) {
                        dataInputRow(
                            title: Language.get("PPScanner_Amount", alter: "مبلغ الشيك (ر.ق)"),
                            icon: "banknote.fill",
                            text: $editedAmount,
                            placeholder: String(format: "%.2f", cartTotal)
                        )

                        // One-Tap Cart Total Match Shortcut
                        if cartTotal > 0 {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                editedAmount = String(format: "%.2f", cartTotal)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                                    Text("\(Language.get("PPScanner_MatchTotal", alter: "مطابقة إجمالي السلة")): \(String(format: "%.2f", cartTotal)) \(Language.get("QAR", alter: "ر.ق"))")
                                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption2))
                                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.12),
                                    in: Capsule(style: .continuous)
                                )
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(16)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
                .padding(.horizontal, 18)

                Spacer(minLength: 20)

                // Primary Confirmation Action
                Button {
                    var updated = cheque
                    updated.chequeNumber = editedChequeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.bankName = editedBankName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanAmt = PPScannerEngine.normalizeArabicNumerals(editedAmount.trimmingCharacters(in: .whitespacesAndNewlines))
                    if let parsed = Double(cleanAmt) {
                        updated.amount = parsed
                    }
                    onConfirm(updated)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(Language.get("PPScanner_Confirm", alter: "اعتماد وإرفاق الشيك بالسلة"))
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.85, green: 0.47, blue: 0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.35), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(ScannerButtonPressStyle())
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .onAppear {
            editedChequeNumber = cheque.chequeNumber
            editedBankName = cheque.bankName
            if let amt = cheque.amount {
                editedAmount = String(format: "%.2f", amt)
            } else if cartTotal > 0 {
                editedAmount = String(format: "%.2f", cartTotal)
            }
        }
    }

    private func dataInputRow(
        title: String,
        icon: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(placeholder, text: text)
                    .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                    .textFieldStyle(.plain)
            }
        }
    }
}

// MARK: - Camera Preview UIViewControllerRepresentable

private struct PPScannerCameraPreview: UIViewControllerRepresentable {
    let session: AVCaptureSession

    func makeUIViewController(context: Context) -> PPScannerPreviewViewController {
        let vc = PPScannerPreviewViewController()
        vc.previewLayer.session = session
        return vc
    }

    func updateUIViewController(_ uiViewController: PPScannerPreviewViewController, context: Context) {
        if uiViewController.previewLayer.session != session {
            uiViewController.previewLayer.session = session
        }
    }
}

final class PPScannerPreviewViewController: UIViewController {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

// MARK: - Native Photo Picker Wrapper

private struct PPPhotoPickerRepresentable: UIViewControllerRepresentable {
    let onImageSelected: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (UIImage?) -> Void

        init(onImageSelected: @escaping (UIImage?) -> Void) {
            self.onImageSelected = onImageSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onImageSelected(nil)
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                DispatchQueue.main.async {
                    self?.onImageSelected(object as? UIImage)
                }
            }
        }
    }
}

// MARK: - Qatar & GCC Bank Catalog Matcher

private struct PPBankDefinition {
    let canonicalName: String
    let patterns: [String]
}

private let kQatarBankCatalog: [PPBankDefinition] = [
    PPBankDefinition(
        canonicalName: "QNB • بنك قطر الوطني",
        patterns: ["QNB", "QATAR NATIONAL BANK", "الوطني", "قطر الوطني", "NATIONAL BANK OF QATAR"]
    ),
    PPBankDefinition(
        canonicalName: "QIB • مصرف قطر الإسلامي",
        patterns: ["QIB", "QATAR ISLAMIC BANK", "المصرف", "قطر الإسلامي", "المصرف الإسلامي", "ISLAMIC BANK"]
    ),
    PPBankDefinition(
        canonicalName: "CBQ • البنك التجاري",
        patterns: ["CBQ", "COMMERCIAL BANK", "التجاري", "البنك التجاري", "COMMERCIAL BANK OF QATAR"]
    ),
    PPBankDefinition(
        canonicalName: "Doha Bank • بنك الدوحة",
        patterns: ["DOHA BANK", "بنك الدوحة", "الدوحة"]
    ),
    PPBankDefinition(
        canonicalName: "Masraf Al Rayan • مصرف الريان",
        patterns: ["MASRAF AL RAYAN", "AL RAYAN", "الريان", "مصرف الريان", "RAYAN BANK"]
    ),
    PPBankDefinition(
        canonicalName: "Dukhan Bank • بنك دخان",
        patterns: ["DUKHAN", "دخان", "بنك دخان", "BARWA", "بروة", "بنك بروة"]
    ),
    PPBankDefinition(
        canonicalName: "Ahlibank • البنك الأهلي",
        patterns: ["AHLIBANK", "AHLI BANK", "الأهلي", "البنك الأهلي", "AHLI"]
    ),
    PPBankDefinition(
        canonicalName: "QDB • بنك قطر للتنمية",
        patterns: ["QDB", "QATAR DEVELOPMENT BANK", "تنمية", "بنك قطر للتنمية"]
    ),
    PPBankDefinition(
        canonicalName: "Arab Bank • البنك العربي",
        patterns: ["ARAB BANK", "البنك العربي", "العربي"]
    ),
    PPBankDefinition(
        canonicalName: "HSBC • إتش إس بي سي",
        patterns: ["HSBC", "إتش إس بي سي", "اتش اس بي سي"]
    ),
    PPBankDefinition(
        canonicalName: "Standard Chartered • ستاندرد تشارترد",
        patterns: ["STANDARD CHARTERED", "ستاندرد تشارترد"]
    )
]

// MARK: - Optical Scanner Vision & AVFoundation Engine

@MainActor
final class PPScannerEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.purepets.ppscanner.session", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "com.purepets.ppscanner.vision", qos: .userInitiated)
    private nonisolated(unsafe) let motionManager = CMMotionManager()

    private var videoDevice: AVCaptureDevice?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()

    @Published var isTorchOn: Bool = false
    @Published var isLowLight: Bool = false
    @Published var isDeviceSteady: Bool = true
    @Published var isChequeDetected: Bool = false
    @Published var detectedPreviewText: String? = nil
    @Published var focusPoint: CGPoint? = nil
    @Published var currentZoom: CGFloat = 1.0
    @Published var isTorchAvailable: Bool = false

    private var baseZoomFactor: CGFloat = 1.0

    var onCaptureComplete: ((PPScannedCheque) -> Void)?
    var onAutoCaptureProgress: ((CGFloat) -> Void)?
    var onCameraReady: (() -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onCameraUnavailable: (() -> Void)?

    private var isAnalyzing = false
    private nonisolated(unsafe) var lastFrameTime: TimeInterval = 0
    private var consecutiveValidFrames: Int = 0
    private var autoCaptureStartTime: Date? = nil

    private var latestCandidateCheque: PPScannedCheque? = nil

    override init() {
        super.init()
        startMotionTracking()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Numeral Normalization

    public nonisolated static func normalizeArabicNumerals(_ text: String) -> String {
        let arabicNumbers: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "،": ",", "٫": ".", "٬": ","
        ]
        return String(text.map { arabicNumbers[$0] ?? $0 })
    }

    // MARK: - Permissions & Setup

    func checkPermissionsAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.onPermissionDenied?()
                    }
                }
            }
        default:
            onPermissionDenied?()
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                DispatchQueue.main.async {
                    self.onCameraReady?()
                }
                return
            }

            if !self.session.inputs.isEmpty {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isTorchAvailable = self.videoDevice?.hasTorch == true
                    self.onCameraReady?()
                }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.onCameraUnavailable?()
                }
                return
            }

            guard self.session.canAddInput(input),
                  self.session.canAddOutput(self.videoOutput),
                  self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.onCameraUnavailable?()
                }
                return
            }

            self.videoDevice = device
            self.session.addInput(input)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            self.session.addOutput(self.videoOutput)
            self.session.addOutput(self.photoOutput)

            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isTorchAvailable = device.hasTorch
                self.onCameraReady?()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let device = self.videoDevice, device.hasTorch, device.torchMode == .on {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {
                    // Session shutdown must continue even when torch state cannot be changed.
                }
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isTorchOn = false
            }
        }
    }

    func resume() {
        consecutiveValidFrames = 0
        autoCaptureStartTime = nil
        latestCandidateCheque = nil
        detectedPreviewText = nil
        isChequeDetected = false
        focusPoint = nil
        checkPermissionsAndStart()
    }

    func toggleTorch() {
        guard let device = videoDevice, device.hasTorch else { return }
        try? device.lockForConfiguration()
        if device.torchMode == .on {
            device.torchMode = .off
            isTorchOn = false
        } else {
            try? device.setTorchModeOn(level: 1.0)
            isTorchOn = true
        }
        device.unlockForConfiguration()
    }

    // MARK: - Tap to Focus & Exposure

    func focus(at point: CGPoint, in viewSize: CGSize) {
        guard let device = videoDevice, viewSize.width > 0, viewSize.height > 0 else { return }
        // Convert screen coordinates to normalized camera coordinates (0.0 to 1.0)
        let x = point.y / viewSize.height
        let y = 1.0 - (point.x / viewSize.width)
        let devicePoint = CGPoint(x: max(0.01, min(0.99, x)), y: max(0.01, min(0.99, y)))

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            self.focusPoint = point
        } catch {
            print("[PPScannerEngine] Focus configuration error: \(error)")
        }
    }

    // MARK: - Zoom Controls

    func toggleZoomLevel() {
        guard let device = videoDevice else { return }
        let targetZoom: CGFloat = (currentZoom > 1.4) ? 1.0 : 2.0
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = targetZoom
            device.unlockForConfiguration()
            self.currentZoom = targetZoom
            self.baseZoomFactor = targetZoom
        } catch {
            print("[PPScannerEngine] Zoom error: \(error)")
        }
    }

    func applyPinchZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
        let newZoom = max(1.0, min(baseZoomFactor * factor, maxZoom))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newZoom
            device.unlockForConfiguration()
            self.currentZoom = newZoom
        } catch {
            print("[PPScannerEngine] Pinch zoom error: \(error)")
        }
    }

    func finalizePinchZoom() {
        baseZoomFactor = currentZoom
    }

    // MARK: - Motion Tracking

    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rotationRate = motion.rotationRate
            let magnitude = sqrt(rotationRate.x * rotationRate.x + rotationRate.y * rotationRate.y + rotationRate.z * rotationRate.z)
            self.isDeviceSteady = magnitude < 0.35
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let currentTime = CACurrentMediaTime()
        // Throttle OCR to ~3 frames/second for battery & thermal preservation
        guard currentTime - lastFrameTime > 0.30 else { return }
        lastFrameTime = currentTime

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Analyze Ambient Lighting
        if let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any],
           let rawExif = metadata["{Exif}"] as? [String: Any],
           let brightness = rawExif["BrightnessValue"] as? Double {
            Task { @MainActor in
                self.isLowLight = brightness < -0.5
            }
        }

        // Vision Text Recognition Request with Arabic & English
        let request = VNRecognizeTextRequest { [weak self] req, err in
            guard let self, err == nil, let observations = req.results as? [VNRecognizedTextObservation] else { return }
            self.parseObservations(observations, sampleBuffer: sampleBuffer)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.recognitionLanguages = ["ar-SA", "en-US"]
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    private nonisolated func parseObservations(
        _ observations: [VNRecognizedTextObservation],
        sampleBuffer: CMSampleBuffer
    ) {
        var recognizedStrings: [String] = []
        for observation in observations {
            if let topCandidate = observation.topCandidates(1).first {
                recognizedStrings.append(topCandidate.string)
            }
        }

        let rawText = recognizedStrings.joined(separator: "\n")
        let parsed = extractFinancialData(from: rawText)
        let candidateImage = self.imageFromSampleBuffer(sampleBuffer)

        Task { @MainActor in
            let hasValidChequeSignals = !parsed.chequeNumber.isEmpty || !parsed.bankName.isEmpty || rawText.contains("⑆") || rawText.contains("⑈")

            self.isChequeDetected = hasValidChequeSignals

            if hasValidChequeSignals {
                var preview = ""
                if !parsed.chequeNumber.isEmpty {
                    preview = String(
                        format: Language.get("PPScanner_DetectedNumber", alter: "شيك رقم %@"),
                        parsed.chequeNumber
                    )
                }
                if !parsed.bankName.isEmpty {
                    let bankShort = parsed.bankName.components(separatedBy: " • ").first ?? parsed.bankName
                    preview += (preview.isEmpty ? "" : " • ") + bankShort
                }
                if let amt = parsed.amount {
                    preview += String(
                        format: " • %.2f %@",
                        amt,
                        Language.get("QAR", alter: "ر.ق")
                    )
                }
                self.detectedPreviewText = preview.isEmpty ? Language.get("PPScanner_ChequeDetected", alter: "تم التعرف على الشيك") : preview

                self.consecutiveValidFrames += 1

                // Create intermediate candidate cheque
                if let image = candidateImage {
                    self.latestCandidateCheque = PPScannedCheque(
                        image: image,
                        chequeNumber: parsed.chequeNumber,
                        bankName: parsed.bankName,
                        amount: parsed.amount,
                        dateString: parsed.dateString,
                        rawText: rawText
                    )
                }

                // Handle Auto-Capture Timeline
                if self.isDeviceSteady, !self.isLowLight, self.consecutiveValidFrames >= 3 {
                    if self.autoCaptureStartTime == nil {
                        self.autoCaptureStartTime = Date()
                    }
                    let elapsed = Date().timeIntervalSince(self.autoCaptureStartTime!)
                    let progress = min(CGFloat(elapsed / 0.8), 1.0)
                    self.onAutoCaptureProgress?(progress)

                    if progress >= 1.0, let candidate = self.latestCandidateCheque {
                        self.autoCaptureStartTime = nil
                        self.onCaptureComplete?(candidate)
                    }
                } else {
                    self.autoCaptureStartTime = nil
                    self.onAutoCaptureProgress?(0.0)
                }
            } else {
                self.consecutiveValidFrames = 0
                self.detectedPreviewText = nil
                self.autoCaptureStartTime = nil
                self.onAutoCaptureProgress?(0.0)
            }
        }
    }

    // MARK: - Financial Data Extraction & Optical Intelligence

    private nonisolated func extractFinancialData(from rawText: String) -> (chequeNumber: String, bankName: String, amount: Double?, dateString: String?) {
        var chequeNumber = ""
        var bankName = ""
        var amount: Double? = nil
        var dateString: String? = nil

        // Normalize Eastern Arabic Numerals (٠-٩) and punctuation across entire text
        let normalizedText = PPScannerEngine.normalizeArabicNumerals(rawText)
        let lines = normalizedText.components(separatedBy: .newlines)

        // 1. Detect Bank Name (Comprehensive Qatar & GCC Catalog)
        let uppercaseNormalized = normalizedText.uppercased()
        let uppercaseRaw = rawText.uppercased()

        for bank in kQatarBankCatalog {
            for pattern in bank.patterns {
                let patternUpper = pattern.uppercased()
                if uppercaseNormalized.contains(patternUpper) || uppercaseRaw.contains(patternUpper) {
                    bankName = bank.canonicalName
                    break
                }
            }
            if !bankName.isEmpty { break }
        }

        // 2. Detect Cheque Number (MICR Line or Explicit Label or Standalone Serial)
        // Strategy A: Strict MICR Delimiters (⑆004821⑆ or ⑈004821⑈)
        for line in lines {
            if let micrMatch = line.range(of: "[⑆⑈:#|c] *([0-9]{6,8}) *[⑆⑈:#|c]", options: .regularExpression) {
                let segment = String(line[micrMatch])
                let digitsOnly = segment.filter { $0.isNumber }
                if digitsOnly.count >= 6 && digitsOnly.count <= 8 {
                    chequeNumber = digitsOnly
                    break
                }
            }
        }

        // Strategy B: Labeled Cheque Number (e.g. "Cheque No: 004821" or "رقم الشيك : 004821")
        if chequeNumber.isEmpty {
            for line in lines {
                if let labelMatch = line.range(of: "(?i)(?:cheque|chq|no|num|رقم|شيك)[^0-9\n]{0,10}([0-9]{6,8})", options: .regularExpression) {
                    let segment = String(line[labelMatch])
                    let digitsOnly = segment.filter { $0.isNumber }
                    if digitsOnly.count >= 6 && digitsOnly.count <= 8 {
                        chequeNumber = digitsOnly
                        break
                    }
                }
            }
        }

        // Strategy C: Standalone 6-8 digit line (common on GCC cheques)
        if chequeNumber.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 6 && trimmed.count <= 8 && trimmed.allSatisfy({ $0.isNumber }) {
                    chequeNumber = trimmed
                    break
                }
            }
        }

        // 3. Detect Amount (e.g. 1500.00, 1,250.00, ***1500.00/-***, QAR 175)
        for line in lines {
            // Regex matching amounts with optional currency, comma grouping, and decimal
            if let amountRange = line.range(of: #"([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]{2,7}\.[0-9]{1,2}|\b[0-9]{3,7}\b)"#, options: .regularExpression) {
                let rawSegment = String(line[amountRange])
                let clean = rawSegment.replacingOccurrences(of: ",", with: "")
                if let val = Double(clean), val >= 1.0, val <= 10_000_000.0 {
                    // Check if line contains cheque number so we don't confuse cheque serial with amount
                    if !chequeNumber.isEmpty && clean == chequeNumber {
                        continue
                    }
                    if amount == nil || val > (amount ?? 0) {
                        amount = val
                    }
                }
            }
        }

        // 4. Detect Date (DD/MM/YYYY, YYYY/MM/DD, DD-MM-YYYY)
        for line in lines {
            if let dateRange = line.range(of: "\\b((?:20[2-3][0-9][/-](?:0?[1-9]|1[0-2])[/-](?:0?[1-9]|[12][0-9]|3[01]))|(?:(?:0?[1-9]|[12][0-9]|3[01])[/-](?:0?[1-9]|1[0-2])[/-]20[2-3][0-9]))\\b", options: .regularExpression) {
                dateString = String(line[dateRange])
                break
            }
        }

        return (chequeNumber, bankName, amount, dateString)
    }

    private nonisolated func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

    // Manual Shutter Photo Capture
    func capturePhotoManually() {
        guard session.isRunning else {
            onCameraUnavailable?()
            return
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor [weak self] in
                self?.onCameraUnavailable?()
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.processImportedImage(image) { parsedCheque in
                Task { @MainActor in
                    self.onCaptureComplete?(parsedCheque)
                }
            }
        }
    }

    // Process Image from Photo Library
    func processImportedImage(_ image: UIImage, completion: @escaping @Sendable (PPScannedCheque) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(PPScannedCheque(image: image))
            return
        }

        visionQueue.async { [weak self] in
            guard let self else { return }
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async {
                        completion(PPScannedCheque(image: image))
                    }
                    return
                }

                var strings: [String] = []
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        strings.append(top.string)
                    }
                }
                let rawText = strings.joined(separator: "\n")
                let parsed = self.extractFinancialData(from: rawText)

                DispatchQueue.main.async {
                    let result = PPScannedCheque(
                        image: image,
                        chequeNumber: parsed.chequeNumber,
                        bankName: parsed.bankName,
                        amount: parsed.amount,
                        dateString: parsed.dateString,
                        rawText: rawText
                    )
                    completion(result)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(iOS 16.0, *) {
                request.recognitionLanguages = ["ar-SA", "en-US"]
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
