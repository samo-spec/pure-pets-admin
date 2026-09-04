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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Scanner State Phase

public enum PPScannerPhase: Equatable {
    case scanning
    case autoCapturing(progress: CGFloat)
    case reviewing(PPScannedCheque)
    case permissionDenied
    case error(String)
}

// MARK: - Master PPScanner View

public struct PPScannerView: View {
    let cartTotal: Double
    let onAttach: (PPScannedCheque) -> Void
    let onDismiss: () -> Void

    @StateObject private var engine = PPScannerEngine()
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: PPScannerPhase = .scanning
    @State private var isShowingPhotoPicker = false
    @State private var reviewCheque: PPScannedCheque? = nil

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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            phase = .scanning
                            engine.resume()
                        }
                    },
                    onConfirm: { confirmedCheque in
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        onAttach(confirmedCheque)
                    }
                )
            case .scanning, .autoCapturing:
                liveScannerDeck
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            engine.onCaptureComplete = { capturedCheque in
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.phase = .reviewing(capturedCheque)
                }
            }
            engine.onAutoCaptureProgress = { progress in
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
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            PPPhotoPickerRepresentable { selectedImage in
                if let selectedImage {
                    engine.processImportedImage(selectedImage) { parsedCheque in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.phase = .reviewing(parsedCheque)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Live Scanner Deck

    private var liveScannerDeck: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            ZStack {
                // 1. Full-Bleed Camera Viewport
                PPScannerCameraPreview(session: engine.session)
                    .ignoresSafeArea()

                // 2. Translucent Optical Mask & Vignette
                PPScannerVignetteMask(reticleSize: reticleSize(for: screenSize))
                    .ignoresSafeArea()

                // 3. Central Spatial Reticle & Telemetry
                VStack(spacing: 12) {
                    Spacer(minLength: 60)

                    // Top Quality Telemetry Gauges
                    telemetryGauges

                    // The Aspect-Engineered Cheque Reticle (~2.2:1)
                    PPScannerReticle(
                        size: reticleSize(for: screenSize),
                        isLocked: engine.isChequeDetected,
                        autoCaptureProgress: autoCaptureProgress
                    )

                    // Live Recognized Field HUD
                    if let detected = engine.detectedPreviewText, !detected.isEmpty {
                        liveFieldHUD(text: detected)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    Spacer(minLength: 20)

                    // Bottom Flight Deck Controls
                    bottomControls
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)

                // 4. Sovereign Frosted Navigation Bar Chrome
                VStack {
                    sovereignNavigationBar
                    Spacer()
                }
            }
        }
    }

    private var autoCaptureProgress: CGFloat {
        if case .autoCapturing(let p) = phase {
            return p
        }
        return 0.0
    }

    private func reticleSize(for screenSize: CGSize) -> CGSize {
        // Standard Cheque Aspect Ratio is ~2.2 : 1
        let maxWidth = min(screenSize.width - 36, 520)
        let height = maxWidth / 2.18
        return CGSize(width: maxWidth, height: height)
    }

    // MARK: - Sovereign Navigation Bar

    private var sovereignNavigationBar: some View {
        HStack(spacing: 12) {
            // Dismiss Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))

            Spacer()

            // Title and Intelligence Subtitle
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                    Text(Language.get("PPScanner_Title", alter: "ماسح الشيكات"))
                        .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline))
                        .foregroundColor(.white)
                }

                Text(Language.get("PPScanner_Subtitle", alter: "محرك المسح المالي الضوئي"))
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    .foregroundColor(Color.white.opacity(0.70))
            }

            Spacer()

            // Trailing Actions Cluster (Gallery & Torch)
            HStack(spacing: 8) {
                // Photo Gallery Import Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isShowingPhotoPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel(Language.get("PPScanner_Gallery", alter: "من ألبوم الصور"))

                // Torch Toggle Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    engine.toggleTorch()
                } label: {
                    Image(systemName: engine.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(engine.isTorchOn ? Color(red: 0.96, green: 0.62, blue: 0.04) : .white)
                        .frame(width: 40, height: 40)
                        .background(
                            engine.isTorchOn
                                ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.25)
                                : Color.black.opacity(0.45),
                            in: Circle()
                        )
                        .overlay(
                            Circle().stroke(
                                engine.isTorchOn
                                    ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.60)
                                    : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                        )
                }
                .accessibilityLabel(Language.get("PPScanner_Torch", alter: "إضاءة الفلاش"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.75)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Telemetry Gauges

    private var telemetryGauges: some View {
        HStack(spacing: 8) {
            // Lighting Gauge
            HStack(spacing: 4) {
                Image(systemName: engine.isLowLight ? "sun.min.fill" : "sun.max.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(engine.isLowLight ? .orange : .green)
                Text(engine.isLowLight
                    ? Language.get("PPScanner_LowLight", alter: "إضاءة خافتة")
                    : Language.get("PPScanner_GoodLight", alter: "إضاءة مثالية"))
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            // Alignment Confidence Gauge
            HStack(spacing: 4) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(engine.isChequeDetected ? .green : .yellow)
                Text(engine.isChequeDetected
                    ? Language.get("PPScanner_Aligned", alter: "متطابق 96%")
                    : Language.get("PPScanner_Aligning", alter: "جاري المحاذاة"))
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            // Stability Gauge
            HStack(spacing: 4) {
                Circle()
                    .fill(engine.isDeviceSteady ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(engine.isDeviceSteady
                    ? Language.get("PPScanner_Steady", alter: "ثابت")
                    : Language.get("PPScanner_HoldStill", alter: "ثبّت الهاتف"))
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    // MARK: - Live Field Recognition HUD

    private func liveFieldHUD(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))

            Text(text)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.70))
                .background(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).stroke(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.60), lineWidth: 1))
        )
        .shadow(color: Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.35), radius: 8, x: 0, y: 2)
    }

    // MARK: - Bottom Controls Bar

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // Status Guidance Subtitle
            Text(guidanceText)
                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black, radius: 4, x: 0, y: 2)

            // Kinetic Dual-Ring Shutter Button
            HStack {
                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    engine.capturePhotoManually()
                } label: {
                    ZStack {
                        // Outer Ambient Ring
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 4)
                            .frame(width: 76, height: 76)

                        // Kinetic Auto-Capture Progress Fill
                        if autoCaptureProgress > 0 {
                            Circle()
                                .trim(from: 0, to: autoCaptureProgress)
                                .stroke(
                                    Color(red: 0.96, green: 0.62, blue: 0.04),
                                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 76, height: 76)
                        }

                        // Inner Core Shutter
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                }
                .buttonStyle(ScannerButtonPressStyle())
                .accessibilityLabel(Language.get("PPScanner_ManualCapture", alter: "التقاط يدوي"))

                Spacer()
            }
        }
    }

    private var guidanceText: String {
        if engine.isChequeDetected {
            return Language.get("PPScanner_ReadyToCapture", alter: "تم ضبط الشيك • جاري الالتقاط التلقائي...")
        } else if !engine.isDeviceSteady {
            return Language.get("PPScanner_HoldSteady", alter: "ثبّت الكاميرا فوق الشيك للتركيز")
        } else {
            return Language.get("PPScanner_AlignCheque", alter: "وجّه الشيك داخل الإطار المخصص")
        }
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.orange)

            Text(Language.get("PPScanner_CameraPermissionRequired", alter: "مطلوب إذن استخدام الكاميرا"))
                .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                .foregroundColor(.white)

            Text(Language.get("PPScanner_CameraPermissionDesc", alter: "يرجى تمكين إذن الكاميرا من إعدادات الجهاز لمسح الشيكات البنكية."))
                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(Language.get("Settings", alter: "فتح الإعدادات"))
                    .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .callout))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white, in: Capsule())
            }
            .padding(.top, 8)

            Button {
                onDismiss()
            } label: {
                Text(Language.get("Cancel", alter: "إلغاء"))
                    .font(Font.custom("Beiruti-Medium", size: 14, relativeTo: .callout))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.red)

            Text(message)
                .font(Font.custom("Beiruti-Medium", size: 15, relativeTo: .body))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text(Language.get("Close", alter: "إغلاق"))
                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
        }
    }
}

// MARK: - Optical Reticle & Scanning Overlay

private struct PPScannerReticle: View {
    let size: CGSize
    let isLocked: Bool
    let autoCaptureProgress: CGFloat

    @State private var scanPhase: CGFloat = 0

    private var accentColor: Color {
        isLocked ? Color.green : Color(red: 0.96, green: 0.62, blue: 0.04)
    }

    var body: some View {
        ZStack {
            // Reticle Border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    accentColor.opacity(isLocked ? 0.9 : 0.4),
                    lineWidth: isLocked ? 2.0 : 1.2
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(isLocked ? 0.08 : 0.02))
                )

            // Chamfered Laser Corner Brackets
            PPScannerCornerBrackets(color: accentColor, cornerLength: 24, thickness: 3.5)

            // Animated Laser Scanning Beam
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, accentColor.opacity(0.65), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 2)
                    .offset(y: scanPhase * (geo.size.height - 4))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Lower MICR Readout Baseline
            VStack {
                Spacer()

                HStack(spacing: 8) {
                    Text("⑆")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(Language.get("PPScanner_MICRTrack", alter: "شريط التشفير المغناطيسي MICR"))
                        .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                    Text("⑈")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(accentColor.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.65))
                )
                .padding(.bottom, 10)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                scanPhase = 1.0
            }
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

// MARK: - Vignette Mask

private struct PPScannerVignetteMask: View {
    let reticleSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let fullSize = proxy.size
            let xOffset = (fullSize.width - reticleSize.width) / 2
            let yOffset = (fullSize.height - reticleSize.height) / 2

            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color.black.opacity(0.55))
                )
                let reticleRect = CGRect(x: xOffset, y: yOffset, width: reticleSize.width, height: reticleSize.height)
                context.blendMode = .destinationOut
                context.fill(
                    Path(roundedRect: reticleRect, cornerRadius: 18),
                    with: .color(.black)
                )
            }
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
                        placeholder: "004821"
                    )

                    Divider().background(AdminSurface.hairline)

                    // Bank Name
                    dataInputRow(
                        title: Language.get("PPScanner_BankName", alter: "اسم البنك"),
                        icon: "building.columns.fill",
                        text: $editedBankName,
                        placeholder: "QNB / البنك الوطني"
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
                    if let parsed = Double(editedAmount.trimmingCharacters(in: .whitespacesAndNewlines)) {
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

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageSelected: (UIImage?) -> Void

        init(onImageSelected: @escaping (UIImage?) -> Void) {
            self.onImageSelected = onImageSelected
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) {
                self.onImageSelected(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.onImageSelected(nil)
            }
        }
    }
}

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

    var onCaptureComplete: ((PPScannedCheque) -> Void)?
    var onAutoCaptureProgress: ((CGFloat) -> Void)?

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

    func checkPermissionsAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    }
                }
            }
        default:
            break
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }

            self.videoDevice = device

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func resume() {
        sessionQueue.async { [weak self] in
            if let running = self?.session.isRunning, !running {
                self?.session.startRunning()
            }
        }
        consecutiveValidFrames = 0
        autoCaptureStartTime = nil
        latestCandidateCheque = nil
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

        // Vision Text Recognition Request
        let request = VNRecognizeTextRequest { [weak self] req, err in
            guard let self, err == nil, let observations = req.results as? [VNRecognizedTextObservation] else { return }
            self.parseObservations(observations, sampleBuffer: sampleBuffer)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

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

        let fullText = recognizedStrings.joined(separator: "\n")
        let parsed = extractFinancialData(from: fullText)
        let candidateImage = self.imageFromSampleBuffer(sampleBuffer)

        Task { @MainActor in
            let hasValidChequeSignals = !parsed.chequeNumber.isEmpty || !parsed.bankName.isEmpty || fullText.contains("⑆") || fullText.contains("⑈")

            self.isChequeDetected = hasValidChequeSignals

            if hasValidChequeSignals {
                var preview = ""
                if !parsed.chequeNumber.isEmpty {
                    preview = "شيك #\(parsed.chequeNumber)"
                }
                if !parsed.bankName.isEmpty {
                    preview += (preview.isEmpty ? "" : " • ") + parsed.bankName
                }
                if let amt = parsed.amount {
                    preview += String(format: " • %.2f ر.ق", amt)
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
                        rawText: fullText
                    )
                }

                // Handle Auto-Capture Timeline
                if self.isDeviceSteady, self.consecutiveValidFrames >= 3 {
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

    private nonisolated func extractFinancialData(from text: String) -> (chequeNumber: String, bankName: String, amount: Double?, dateString: String?) {
        var chequeNumber = ""
        var bankName = ""
        var amount: Double? = nil
        var dateString: String? = nil

        let lines = text.components(separatedBy: .newlines)

        // 1. Detect Cheque Number (MICR or standard 6-8 digit pattern)
        for line in lines {
            // Pattern for MICR delimiters ⑆004821⑆
            if let micrMatch = line.range(of: "[⑆#]?([0-9]{6,8})[⑆#]?", options: .regularExpression) {
                let raw = String(line[micrMatch]).replacingOccurrences(of: "⑆", with: "").replacingOccurrences(of: "#", with: "")
                if chequeNumber.isEmpty && raw.count >= 6 {
                    chequeNumber = raw
                }
            }
        }

        // 2. Detect Bank Name (Qatar & Regional Major Banks)
        let uppercaseText = text.uppercased()
        if uppercaseText.contains("QNB") || text.contains("الوطني") {
            bankName = "QNB"
        } else if uppercaseText.contains("QIB") || text.contains("المصرف") || text.contains("قطر الإسلامي") {
            bankName = "QIB"
        } else if uppercaseText.contains("COMMERCIAL BANK") || uppercaseText.contains("CBQ") || text.contains("التجاري") {
            bankName = "CBQ"
        } else if uppercaseText.contains("DOHA BANK") || text.contains("بنك الدوحة") {
            bankName = "Doha Bank"
        } else if uppercaseText.contains("RAYAN") || text.contains("الريان") {
            bankName = "Masraf Al Rayan"
        } else if uppercaseText.contains("DUKHAN") || text.contains("دخان") {
            bankName = "Dukhan Bank"
        } else if uppercaseText.contains("AHLI") || text.contains("الأهلي") {
            bankName = "Ahlibank"
        }

        // 3. Detect Amount (e.g. 1500.00, 1,250.00, QAR 175)
        for line in lines {
            if let amountRange = line.range(of: "([0-9]{1,3}(,[0-9]{3})*(\\.[0-9]{2}))", options: .regularExpression) {
                let clean = String(line[amountRange]).replacingOccurrences(of: ",", with: "")
                if let val = Double(clean), val > 0, amount == nil {
                    amount = val
                }
            }
        }

        // 4. Detect Date (DD/MM/YYYY or YYYY/MM/DD)
        for line in lines {
            if let dateRange = line.range(of: "\\b([0-9]{2}[/-][0-9]{2}[/-][0-9]{4}|[0-9]{4}[/-][0-9]{2}[/-][0-9]{2})\\b", options: .regularExpression) {
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
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }

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
                let fullText = strings.joined(separator: "\n")
                let parsed = self.extractFinancialData(from: fullText)

                DispatchQueue.main.async {
                    let result = PPScannedCheque(
                        image: image,
                        chequeNumber: parsed.chequeNumber,
                        bankName: parsed.bankName,
                        amount: parsed.amount,
                        dateString: parsed.dateString,
                        rawText: fullText
                    )
                    completion(result)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
