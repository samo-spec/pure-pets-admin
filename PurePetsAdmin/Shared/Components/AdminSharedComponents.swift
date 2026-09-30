import SwiftUI
import UIKit
import CoreText
import Kingfisher
import AVFoundation
import AudioToolbox

/// The only remote-image pipeline used by the Admin app. Its named Kingfisher cache
/// persists catalog, POS, banner, and profile media on disk for subsequent screens.
@MainActor
enum AdminRemoteImageCache {
    static let cache: ImageCache = {
        let cache = ImageCache(name: "com.pb.purepets.admin.remote-images")
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()

    static var options: KingfisherOptionsInfo {
        [
            .targetCache(cache),
            .cacheOriginalImage,
            .transition(.fade(0.20)),
            .scaleFactor(UIScreen.main.scale),
            .keepCurrentImageWhileLoading,
            .backgroundDecode
        ]
    }

    /// Sanitizes any string or URL candidate into a valid, percent-encoded URL.
    /// Safely handles whitespace trimming, unicode/Arabic characters, and pre-existing URLs.
    static func sanitizeURL(from raw: Any?) -> URL? {
        guard let raw else { return nil }
        if let url = raw as? URL {
            return sanitizeURL(from: url.absoluteString)
        }
        guard let rawString = raw as? String else { return nil }
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Fast path: already a valid URL with scheme
        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }

        // Percent-encode if string contains unencoded spaces or characters
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }

        return nil
    }
}

/// Shared, cache-backed SwiftUI remote image view. Every Admin SwiftUI screen uses
/// this component instead of `AsyncImage`, while UIKit uses `PPAdminImageLoader`
/// below against the same Kingfisher cache.
struct AdminRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: SwiftUI.ContentMode
    let targetSize: CGSize?
    private let placeholder: Placeholder

    init(
        url: URL?,
        contentMode: SwiftUI.ContentMode = .fill,
        targetSize: CGSize? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = AdminRemoteImageCache.sanitizeURL(from: url)
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.placeholder = placeholder()
    }

    init(
        urlString: String?,
        contentMode: SwiftUI.ContentMode = .fill,
        targetSize: CGSize? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = AdminRemoteImageCache.sanitizeURL(from: urlString)
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let url {
                let scale = UIScreen.main.scale
                if let targetSize {
                    let pixelSize = CGSize(width: max(targetSize.width * scale, 1), height: max(targetSize.height * scale, 1))
                    KFImage(url)
                        .placeholder { placeholder }
                        .targetCache(AdminRemoteImageCache.cache)
                        .setProcessor(DownsamplingImageProcessor(size: pixelSize))
                        .scaleFactor(scale)
                        .cacheOriginalImage()
                        .cancelOnDisappear(true)
                        .fade(duration: 0.20)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    KFImage(url)
                        .placeholder { placeholder }
                        .targetCache(AdminRemoteImageCache.cache)
                        .scaleFactor(scale)
                        .cacheOriginalImage()
                        .cancelOnDisappear(true)
                        .fade(duration: 0.20)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                placeholder
            }
        }
    }
}

extension AdminRemoteImage where Placeholder == AnyView {
    init(
        url: URL?,
        contentMode: SwiftUI.ContentMode = .fill,
        targetSize: CGSize? = nil
    ) {
        self.init(url: url, contentMode: contentMode, targetSize: targetSize) {
            AnyView(
                Color(.systemGray6)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(.tertiaryLabel))
                    )
            )
        }
    }

    init(
        urlString: String?,
        contentMode: SwiftUI.ContentMode = .fill,
        targetSize: CGSize? = nil
    ) {
        self.init(urlString: urlString, contentMode: contentMode, targetSize: targetSize) {
            AnyView(
                Color(.systemGray6)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(.tertiaryLabel))
                    )
            )
        }
    }
}

private struct SendableClosureBox<T>: @unchecked Sendable {
    let closure: T
}

/// Objective-C-compatible bridge for the established UIKit portions of Admin.
/// It intentionally shares the exact cache and URL keys used by `AdminRemoteImage`.
@MainActor
@objc(PPAdminImageLoader)
final class PPAdminImageLoader: NSObject {
    @objc(setImageWithURLString:onImageView:placeholder:completion:)
    class func setImage(
        urlString: String?,
        on imageView: UIImageView,
        placeholder: UIImage?,
        completion: ((UIImage?) -> Void)?
    ) {
        guard let url = AdminRemoteImageCache.sanitizeURL(from: urlString) else {
            imageView.image = placeholder
            completion?(placeholder)
            return
        }

        let box = SendableClosureBox(closure: completion)
        imageView.kf.setImage(
            with: url,
            placeholder: placeholder,
            options: AdminRemoteImageCache.options
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value): box.closure?(value.image)
                case .failure: box.closure?(placeholder)
                }
            }
        }
    }

    @objc(loadImageWithURLString:completion:)
    class func loadImage(
        urlString: String?,
        completion: @escaping (UIImage?, NSError?, Bool) -> Void
    ) {
        guard let url = AdminRemoteImageCache.sanitizeURL(from: urlString) else {
            completion(nil, NSError(domain: "PPAdminImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL"]), false)
            return
        }

        let box = SendableClosureBox(closure: completion)
        KingfisherManager.shared.retrieveImage(with: url, options: AdminRemoteImageCache.options) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value): box.closure(value.image, nil, value.cacheType != .none)
                case .failure(let error): box.closure(nil, error as NSError, false)
                }
            }
        }
    }

    @objc(cancelLoadForImageView:)
    class func cancelLoad(for imageView: UIImageView) {
        imageView.kf.cancelDownloadTask()
    }

    @objc(cachedImageForURLString:)
    class func cachedImage(urlString: String?) -> UIImage? {
        guard let url = AdminRemoteImageCache.sanitizeURL(from: urlString) else { return nil }
        return AdminRemoteImageCache.cache.retrieveImageInMemoryCache(forKey: url.absoluteString)
    }

    @objc(removeImageForCacheKey:completion:)
    class func removeImage(cacheKey: String?, completion: (() -> Void)?) {
        guard let cacheKey else {
            completion?()
            return
        }
        let box = SendableClosureBox(closure: completion)
        AdminRemoteImageCache.cache.removeImage(forKey: cacheKey, fromMemory: true, fromDisk: true) {
            box.closure?()
        }
    }

    @objc(calculateDiskCacheSizeWithCompletion:)
    class func calculateDiskCacheSize(completion: @escaping (NSNumber?) -> Void) {
        let box = SendableClosureBox(closure: completion)
        AdminRemoteImageCache.cache.calculateDiskStorageSize { result in
            switch result {
            case .success(let size): box.closure(NSNumber(value: size))
            case .failure: box.closure(nil)
            }
        }
    }

    @objc(clearAllCachedImagesWithCompletion:)
    class func clearAllCachedImages(completion: (() -> Void)?) {
        let box = SendableClosureBox(closure: completion)
        AdminRemoteImageCache.cache.clearMemoryCache()
        AdminRemoteImageCache.cache.clearDiskCache {
            box.closure?()
        }
    }
}

struct AdminStatusBadge: View {
    enum Status { case success, warning, error, info, neutral, processing }
    let text: String
    let status: Status
    var color: Color {
        switch status {
        case .success: return .green; case .warning: return .orange; case .error: return .red
        case .info: return .blue; case .neutral: return AdminSurface.secondaryText; case .processing: return AdminSurface.primary
        }
    }
    var icon: String {
        switch status {
        case .success: return "checkmark.circle.fill"; case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"; case .info: return "info.circle.fill"
        case .neutral: return "circle.fill"; case .processing: return "arrow.triangle.2.circlepath"
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(AdminType.captionBold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
        .accessibilityLabel(text)
    }
}

struct AdminEmptyStateView: View {
    let symbol: String; let title: String; var subtitle: String?; var actionTitle: String?; var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 48)
            Image(systemName: symbol).font(.system(size: 48, weight: .light)).foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            Text(title).font(AdminType.headline).foregroundColor(AdminSurface.primaryText).multilineTextAlignment(.center)
            if let sub = subtitle { Text(sub).font(AdminType.subheadline).foregroundColor(AdminSurface.secondaryText).multilineTextAlignment(.center).padding(.horizontal, 32) }
            if let atitle = actionTitle, let act = action { Button(action: act) { Text(atitle).font(AdminType.headline).padding(.horizontal, 24).frame(minHeight: 48) }.buttonStyle(.borderedProminent).tint(AdminSurface.primary).padding(.top, 8) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityElement(children: .combine)
    }
}

struct AdminSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var showBarcodeScanner: Bool = false
    var onScannedBarcode: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(AdminSurface.secondaryText).font(.system(size: 15, weight: .medium))
            TextField(placeholder, text: $text).font(AdminType.callout).foregroundColor(AdminSurface.primaryText)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(AdminSurface.secondaryText).font(.system(size: 16))
                }
                .frame(minWidth: 32, minHeight: 32)
                .accessibilityLabel(Language.get("Clear", alter: nil))
            }
            if showBarcodeScanner || onScannedBarcode != nil {
                AdminBarcodeScanButton(isCircle: true) { scanned in
                    if let onScannedBarcode {
                        onScannedBarcode(scanned)
                    } else {
                        text = scanned
                    }
                }
            }
        }
        .padding(.horizontal, 16).frame(height: 48)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
    }
}

struct AdminCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline)) }
}

struct AdminLoadingOverlay: View {
    var message: String?
    var body: some View { ZStack { Color.clear; VStack(spacing: 12) { ProgressView().tint(AdminSurface.primary).scaleEffect(1.2); if let m = message { Text(m).font(AdminType.callout).foregroundColor(AdminSurface.secondaryText) } }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous)) } }
}

/// Reusable SwiftUI wrapper for Lottie animations backed by `LOTAnimationView`.
public struct PPLottieAnimationView: UIViewRepresentable {
    public let name: String
    public var loop: Bool
    public var contentMode: UIView.ContentMode

    public init(name: String, loop: Bool = true, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.name = name
        self.loop = loop
        self.contentMode = contentMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.isOpaque = false

        let cleanName = (name as NSString).deletingPathExtension
        let animationView = LOTAnimationView(name: cleanName)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.contentMode = contentMode
        animationView.loopAnimation = loop
        animationView.backgroundColor = .clear
        animationView.isOpaque = false

        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.animationView = animationView
        context.coordinator.startObserving()

        animationView.play()
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if let animationView = context.coordinator.animationView {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject {
        weak var animationView: LOTAnimationView?
        private var isObserving = false

        func startObserving() {
            guard !isObserving else { return }
            isObserving = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        @objc private func handleWillEnterForeground() {
            guard let animationView, !animationView.isAnimationPlaying else { return }
            animationView.play()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

/// Reusable SwiftUI wrapper for Lottie animations fetched from Firebase Storage via `Styling`.
public struct PPLottieFirebaseView: UIViewRepresentable {
    public let fileName: String
    public var loop: Bool
    public var speed: Float
    public var contentMode: UIView.ContentMode

    public init(fileName: String, loop: Bool = true, speed: Float = 1.0, contentMode: UIView.ContentMode = .scaleAspectFit) {
        let cleanName = (fileName as NSString).deletingPathExtension
        self.fileName = cleanName
        self.loop = loop
        self.speed = speed
        self.contentMode = contentMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.isOpaque = false
        container.isUserInteractionEnabled = false

        let animationView = LOTAnimationView()
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.contentMode = contentMode
        animationView.loopAnimation = loop
        animationView.backgroundColor = .clear
        animationView.isOpaque = false
        animationView.isUserInteractionEnabled = false

        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.animationView = animationView
        context.coordinator.startObserving()

        // Asynchronously fetch JSON from Firebase Storage and play
        Styling.setAnimationNamed(fileName, to: animationView, withSpeed: speed) { success in
            if !success {
                // If remote fetch failed, check if it exists in local app bundle
                if let bundleAnimation = LOTComposition(name: self.fileName) {
                    animationView.sceneModel = bundleAnimation
                    animationView.loopAnimation = self.loop
                    animationView.animationSpeed = CGFloat(self.speed)
                    animationView.play()
                }
            }
        }

        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if let animationView = context.coordinator.animationView {
            animationView.animationSpeed = CGFloat(self.speed)
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject {
        weak var animationView: LOTAnimationView?
        private var isObserving = false

        func startObserving() {
            guard !isObserving else { return }
            isObserving = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        @objc private func handleWillEnterForeground() {
            guard let animationView, !animationView.isAnimationPlaying else { return }
            animationView.play()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct AdminErrorBanner: View {
    let message: String; var retry: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 16))
            Text(message).font(AdminType.captionBold).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
            if let r = retry { Button(action: r) { Text(Language.get("Retry", alter: nil)).font(AdminType.captionBold).foregroundColor(.red) } }
        }.padding(12).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Sovereign Navigation Bar & Back Button Components

/// Flagship 44x44 continuous squircle back button matching the Sovereign Design System.
public struct AdminSquircleBackButton: View {
    public var action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Language.get("Back", alter: "رجوع"))
    }
}

/// Flagship 44x44 continuous squircle close button matching the Sovereign Design System for modals and sheets.
public struct AdminSquircleCloseButton: View {
    public var action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
    }
}

/// Sovereign 44x44 continuous squircle action button matching AdminSquircleBackButton.
public struct AdminSquircleActionButton: View {
    public let systemImage: String
    public var isLoading: Bool
    public var isPrimary: Bool
    public var accessibilityLabel: String?
    public var tintColor: Color?
    public var action: () -> Void

    public init(
        systemImage: String,
        isLoading: Bool = false,
        isPrimary: Bool = false,
        accessibilityLabel: String? = nil,
        tintColor: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.isPrimary = isPrimary
        self.accessibilityLabel = accessibilityLabel
        self.tintColor = tintColor
        self.action = action
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: isPrimary ? .medium : .light).impactOccurred()
            action()
        } label: {
            ZStack {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                }

                if isLoading {
                    ProgressView()
                        .tint(isPrimary ? .white : (tintColor ?? AdminSurface.primary))
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isPrimary ? Color.white : (tintColor ?? AdminSurface.primaryText))
                }
            }
            .frame(width: 44, height: 44)
            .shadow(
                color: isPrimary ? AdminSurface.primary.opacity(0.32) : Color.black.opacity(0.04),
                radius: 6,
                x: 0,
                y: isPrimary ? 3 : 2
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

/// Signature action button for top navigation bars (icon only, no title, 44x44 standard touch target).
public struct AdminPrimaryPillButton: View {
    public let title: String
    public let systemImage: String
    public var isLoading: Bool
    public var action: () -> Void

    public init(
        title: String = Language.get("Save", alter: "حفظ"),
        systemImage: String = "checkmark",
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AdminSurface.primary.opacity(0.32), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

/// Sovereign Glassmorphic Navigation Bar pinned to safe area with squircle back button, title stack, and trailing action.
@MainActor
public struct AdminSovereignNavigationBar<TrailingContent: View>: View {
    public let title: String
    public var subtitle: String?
    public var statusDotColor: Color?
    public var isModal: Bool
    public var customTopSpacing: CGFloat?
    public var showsTopFade: Bool
    public var onBack: () -> Void
    public var onSubtitleTap: (() -> Void)?
    public var isSubtitleActionActive: Bool
    public let trailingContent: TrailingContent

    public init(
        title: String,
        subtitle: String? = nil,
        statusDotColor: Color? = Color(uiColor: .ppSuccess),
        isModal: Bool = false,
        customTopSpacing: CGFloat? = nil,
        showsTopFade: Bool = true,
        onBack: @escaping () -> Void,
        onSubtitleTap: (() -> Void)? = nil,
        isSubtitleActionActive: Bool = false,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusDotColor = statusDotColor
        self.isModal = isModal
        self.customTopSpacing = customTopSpacing
        self.showsTopFade = showsTopFade
        self.onBack = onBack
        self.onSubtitleTap = onSubtitleTap
        self.isSubtitleActionActive = isSubtitleActionActive
        self.trailingContent = trailingContent()
    }

    private var topSpacing: CGFloat {
        if let customTopSpacing { return customTopSpacing }
        if isModal { return 0 }
        return PPStatusBarHelper.statusBarHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Optional custom top spacing if explicitly requested by caller
            if topSpacing > 0 {
                Color.clear
                    .frame(height: topSpacing)
            }

            HStack(spacing: 12) {
                if isModal {
                    AdminSquircleCloseButton(action: onBack)
                } else {
                    AdminSquircleBackButton(action: onBack)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if let sub = subtitle, !sub.isEmpty {
                        let subtitleRow = HStack(spacing: 5) {
                            if let dotColor = statusDotColor {
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 6, height: 6)
                            }
                            Text(verbatim: sub.normalizedEnglishDigits)
                                .font(AdminType.caption2)
                                .foregroundStyle(statusDotColor ?? AdminSurface.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            if onSubtitleTap != nil {
                                Image(systemName: isSubtitleActionActive ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(statusDotColor ?? AdminSurface.secondaryText)
                            }
                        }

                        if let onSubtitleTap {
                            Button(action: onSubtitleTap) {
                                subtitleRow
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            subtitleRow
                        }
                    }
                }

                Spacer(minLength: 8)

                trailingContent
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            Group {
                if showsTopFade {
                    PPGlobalNavigationTopFade(
                        surface: AdminSurface.background,
                        maskGeometry: .anchored(
                            solidHeight: topSpacing + 64,
                            bleed: 32
                        )
                    )
                } else {
                    Color.clear
                        .ignoresSafeArea(edges: .top)
                }
            },
            alignment: .top
        )
    }
}

extension AdminSovereignNavigationBar where TrailingContent == EmptyView {
    public init(
        title: String,
        subtitle: String? = nil,
        statusDotColor: Color? = Color(uiColor: .ppSuccess),
        isModal: Bool = false,
        customTopSpacing: CGFloat? = nil,
        showsTopFade: Bool = true,
        onBack: @escaping () -> Void,
        onSubtitleTap: (() -> Void)? = nil,
        isSubtitleActionActive: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            statusDotColor: statusDotColor,
            isModal: isModal,
            customTopSpacing: customTopSpacing,
            showsTopFade: showsTopFade,
            onBack: onBack,
            onSubtitleTap: onSubtitleTap,
            isSubtitleActionActive: isSubtitleActionActive,
            trailingContent: { EmptyView() }
        )
    }
}

// MARK: - Sovereign English Numeric Input & Normalization

extension String {
    /// Normalizes Arabic-Indic (٠-٩) and Eastern Arabic (۰-۹) numerals into ASCII English digits (0-9),
    /// preserving all words, letters, punctuation, whitespace, and symbols.
    public var normalizedEnglishDigits: String {
        let arabicToEnglishMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        var result = ""
        result.reserveCapacity(count)
        for ch in self {
            if let mapped = arabicToEnglishMap[ch] {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Sanitizes numeric user input to only allow ASCII digits (and optionally a single decimal point),
    /// transliterating Arabic-Indic numerals and decimal separators while discarding any other character.
    public func sanitizedNumericInput(allowsDecimal: Bool = true) -> String {
        let arabicToEnglishMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        var result = ""
        var hasDecimalPoint = false
        for ch in self {
            if let mapped = arabicToEnglishMap[ch] {
                result.append(mapped)
            } else if ch >= "0" && ch <= "9" {
                result.append(ch)
            } else if allowsDecimal && (ch == "." || ch == "٫" || ch == "،" || ch == ",") {
                if !hasDecimalPoint {
                    result.append(".")
                    hasDecimalPoint = true
                }
            }
        }
        return result
    }

    /// Backwards-compatible overload for callers explicitly passing `allowsDecimal: Bool`
    /// to sanitize numeric input fields (e.g. price or quantity textfields).
    public func normalizedEnglishDigits(allowsDecimal: Bool) -> String {
        sanitizedNumericInput(allowsDecimal: allowsDecimal)
    }
}

extension Int {
    /// Always returns standard ASCII English digits (0-9).
    public var englishDigits: String {
        "\(self)".normalizedEnglishDigits(allowsDecimal: false)
    }
}

extension Double {
    /// Always returns standard ASCII English digits (0-9) with formatted decimals.
    public func englishDigits(decimals: Int = 2, trimZeroDecimals: Bool = false) -> String {
        let formatted = String(format: "%.*f", decimals, self)
        let normalized = formatted.normalizedEnglishDigits(allowsDecimal: true)
        if trimZeroDecimals && normalized.hasSuffix(".00") {
            return String(normalized.dropLast(3))
        }
        return normalized
    }
}

extension CGFloat {
    /// Always returns standard ASCII English digits (0-9) with formatted decimals.
    public func englishDigits(decimals: Int = 2, trimZeroDecimals: Bool = false) -> String {
        Double(self).englishDigits(decimals: decimals, trimZeroDecimals: trimZeroDecimals)
    }
}

extension NSNumber {
    /// Always returns standard ASCII English digits (0-9).
    public var englishDigits: String {
        stringValue.normalizedEnglishDigits(allowsDecimal: true)
    }
}

public struct PPEnglishNumericInputModifier: ViewModifier {
    @Binding var text: String
    let allowsDecimal: Bool

    public init(text: Binding<String>, allowsDecimal: Bool = true) {
        self._text = text
        self.allowsDecimal = allowsDecimal
    }

    public func body(content: Content) -> some View {
        content
            .keyboardType(allowsDecimal ? .decimalPad : .asciiCapableNumberPad)
            .environment(\.layoutDirection, .leftToRight)
            .onChange(of: text) { newValue in
                let normalized = newValue.normalizedEnglishDigits(allowsDecimal: allowsDecimal)
                if normalized != newValue {
                    text = normalized
                }
            }
    }
}

extension View {
    /// Ensures that numeric and decimal inputs show only English numbers on keyboard, format LTR,
    /// and automatically normalize any typed or pasted Arabic-Indic numerals to standard ASCII English digits.
    public func englishNumericInput(text: Binding<String>, allowsDecimal: Bool = true) -> some View {
        modifier(PPEnglishNumericInputModifier(text: text, allowsDecimal: allowsDecimal))
    }

    /// Ensures that alphanumeric inputs (e.g. barcodes and SKUs) show ASCII keyboard,
    /// format LTR, convert letters to uppercase, and normalize Arabic-Indic numerals to ASCII digits.
    public func englishAlphanumericInput(text: Binding<String>) -> some View {
        modifier(PPEnglishAlphanumericInputModifier(text: text))
    }
}

public struct PPEnglishAlphanumericInputModifier: ViewModifier {
    @Binding var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public func body(content: Content) -> some View {
        content
            .keyboardType(.asciiCapable)
            .environment(\.layoutDirection, .leftToRight)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled(true)
            .onChange(of: text) { newValue in
                let normalized = newValue.normalizedEnglishAlphanumeric()
                if normalized != newValue {
                    text = normalized
                }
            }
    }
}

extension String {
    /// Normalizes Arabic-Indic numerals to standard ASCII English digits,
    /// allows ASCII letters (converting to uppercase), digits, hyphens, and underscores.
    public func normalizedEnglishAlphanumeric() -> String {
        let arabicToEnglishMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        var result = ""
        for char in self {
            if let mapped = arabicToEnglishMap[char] {
                result.append(mapped)
            } else if char.isASCII && (char.isLetter || char.isNumber || char == "-" || char == "_") {
                result.append(char.uppercased())
            }
        }
        return result
    }
}

// MARK: - Pure Pets Brand Typography

public enum PPBrandFont {
    public static func registerIfNeeded() {
        _ = _registrationToken
    }

    private static let _registrationToken: Void = {
        let fontNames = ["Beiruti-Bold", "Beiruti-Medium", "Beiruti-Regular"]
        let bundle = Bundle.main
        for name in fontNames {
            let url = bundle.url(forResource: name, withExtension: "ttf")
                ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Resourses")
                ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Resources")
            if let url = url {
                var error: Unmanaged<CFError>?
                if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    if let error = error?.takeRetainedValue() {
                        let code = CFErrorGetCode(error)
                        // Error code 105 is kCTFontManagerErrorAlreadyRegistered
                        if code != 105 {
                            print("[PPBrandFont] Registration notice for \(name): \(error)")
                        }
                    }
                }
            } else {
                print("[PPBrandFont] Font asset \(name).ttf not found in bundle")
            }
        }
    }()

    public static func bold(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        registerIfNeeded()
        return Font.custom("Beiruti-Bold", size: size, relativeTo: textStyle)
    }

    public static func medium(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        registerIfNeeded()
        return Font.custom("Beiruti-Medium", size: size, relativeTo: textStyle)
    }

    public static func regular(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        registerIfNeeded()
        return Font.custom("Beiruti-Regular", size: size, relativeTo: textStyle)
    }

    public static func bold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        bold(size: size, relativeTo: textStyle)
    }

    public static func medium(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        medium(size: size, relativeTo: textStyle)
    }

    public static func regular(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        regular(size: size, relativeTo: textStyle)
    }

    public static func uiFontBold(size: CGFloat) -> UIFont {
        registerIfNeeded()
        return UIFont(name: "Beiruti-Bold", size: size) ?? UIFont.boldSystemFont(ofSize: size)
    }

    public static func uiFontMedium(size: CGFloat) -> UIFont {
        registerIfNeeded()
        return UIFont(name: "Beiruti-Medium", size: size) ?? UIFont.systemFont(ofSize: size, weight: .medium)
    }

    public static func uiFontRegular(size: CGFloat) -> UIFont {
        registerIfNeeded()
        return UIFont(name: "Beiruti-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
    }
}

public typealias PPBeirutiFont = PPBrandFont

// MARK: - Reusable Barcode Scanner Trigger Button & Sheet Components

typealias AdminBarcodeScannerScreen = POSBarcodeScannerScreen

struct AdminBarcodeScanButton: View {
    let isCircle: Bool
    let onScanned: (String) -> Void
    @State private var isShowingScanner = false

    init(isCircle: Bool = false, onScanned: @escaping (String) -> Void) {
        self.isCircle = isCircle
        self.onScanned = onScanned
    }

    var body: some View {
        Button {
            isShowingScanner = true
        } label: {
            if isCircle {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.primarySoft, in: Circle())
                    .contentShape(Circle())
            } else {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .accessibilityLabel(Language.get("Scan_Barcode", alter: "مسح الباركود"))
        .accessibilityHint(Language.get("POS_Scan_Barcode_Hint", alter: "يفتح الكاميرا للبحث برمز المنتج"))
        .sheet(isPresented: $isShowingScanner) {
            POSBarcodeScannerScreen(
                onResult: { scannedCode in
                    isShowingScanner = false
                    let trimmed = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onScanned(trimmed)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                },
                onCancel: {
                    isShowingScanner = false
                }
            )
        }
    }
}

// MARK: - Permission-Aware Shared Barcode Scanner

enum POSBarcodeScannerPhase: Equatable {
    case permissionRequired
    case requesting
    case ready
    case denied
    case unavailable
}

struct POSBarcodeCameraState: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case starting, reading, interrupted, unavailable
    }

    var status: Status = .starting
    var isTorchAvailable = false
    var isTorchOn = false
}

struct POSBarcodeScannerScreen: View {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var phase: POSBarcodeScannerPhase
    @State private var cameraState = POSBarcodeCameraState()
    @State private var apertureFrame = CGRect.zero
    @State private var cameraFrame = CGRect.zero
    @State private var torchRequested = false
    @State private var showingManualEntry = false
    @State private var isVisible = true
    @State private var hasFinished = false

    private let ink = Color(red: 0.055, green: 0.065, blue: 0.08)

    init(onResult: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onResult = onResult
        self.onCancel = onCancel
        _phase = State(initialValue: Self.phaseForCurrentAuthorization())
    }

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if phase == .ready {
                POSBarcodeCameraView(
                    onResult: { code in
                        guard !showingManualEntry, scenePhase == .active else { return }
                        finish(code)
                    },
                    onFailure: {
                        guard !hasFinished else { return }
                        torchRequested = false
                        phase = .unavailable
                    },
                    scanRegion: BarcodeScanGeometry.normalizedAperture(apertureFrame, in: cameraFrame),
                    isActive: isVisible && scenePhase == .active && !showingManualEntry && !hasFinished,
                    isTorchRequested: torchRequested,
                    onStateChange: { state in
                        guard !hasFinished else { return }
                        cameraState = state
                        if state.status == .interrupted || !state.isTorchAvailable { torchRequested = false }
                    }
                )
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: BarcodeCameraPreferenceKey.self, value: geometry.frame(in: .global))
                    }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)

                GeometryReader { geometry in
                    let origin = geometry.frame(in: .global).origin
                    BarcodeApertureMask(aperture: apertureFrame.offsetBy(dx: -origin.x, dy: -origin.y))
                        .fill(Color.black.opacity(0.56), style: FillStyle(eoFill: true))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    scannerHeader
                    if phase == .ready {
                        if geometry.size.height < 440 {
                            HStack(spacing: 24) {
                                aimingStage
                                instructionShelf
                                    .frame(width: min(320, geometry.size.width * 0.42))
                            }
                            .padding(.horizontal, 24)
                        } else {
                            aimingStage
                                .padding(.horizontal, 24)
                            instructionShelf
                                .frame(maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.48 : 0.36))
                                .padding(.horizontal, 24)
                        }
                    } else {
                        scannerStateContent
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)
        .onPreferenceChange(BarcodeAperturePreferenceKey.self) { apertureFrame = $0 }
        .onPreferenceChange(BarcodeCameraPreferenceKey.self) { cameraFrame = $0 }
        .onAppear {
            isVisible = true
            refreshAuthorization()
        }
        .onDisappear {
            isVisible = false
            torchRequested = false
        }
        .onChange(of: scenePhase) { _, value in
            if value == .active {
                refreshAuthorization()
            } else {
                torchRequested = false
            }
        }
        .onChange(of: showingManualEntry) { _, _ in torchRequested = false }
        .onChange(of: cameraState.status) { old, new in
            guard old != new, isVisible, !showingManualEntry, !hasFinished else { return }
            UIAccessibility.post(notification: .announcement, argument: cameraStatusTitle)
        }
        .sheet(isPresented: $showingManualEntry) {
            BarcodeManualEntrySheet(
                onSubmit: { code in
                    showingManualEntry = false
                    finish(code)
                },
                onCancel: { showingManualEntry = false }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    private var scannerHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(ink, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
            .accessibilityLabel(Language.get("POS_Close", alter: nil))

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("POS_Scanner_Title", alter: nil))
                    .font(PPBrandFont.bold(25, relativeTo: .title2))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                if phase == .ready {
                    HStack(spacing: 7) {
                        if cameraState.status == .starting {
                            ProgressView().tint(.white).accessibilityHidden(true)
                        } else {
                            Image(systemName: cameraState.status == .reading ? "viewfinder" : "pause.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(cameraStatusTitle)
                            .font(PPBrandFont.medium(16, relativeTo: .subheadline))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(ink)
    }

    private var aimingStage: some View {
        GeometryReader { geometry in
            let width = max(24, min(geometry.size.width - 12, 520))
            let height = max(24, min(width * 0.65, max(24, geometry.size.height - 32), 300))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .overlay {
                    BarcodeApertureCorners()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .frame(width: max(24, width), height: height)
                .background {
                    GeometryReader { aperture in
                        Color.clear.preference(key: BarcodeAperturePreferenceKey.self, value: aperture.frame(in: .global))
                    }
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private var instructionShelf: some View {
        ViewThatFits(in: .vertical) {
            instructionContent
            ScrollView { instructionContent }
                .scrollIndicators(.hidden)
        }
    }

    private var instructionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Language.get("POS_Scanner_AimTitle", alter: nil))
                    .font(PPBrandFont.bold(28, relativeTo: .title2))
                    .foregroundStyle(.white)
                Text(Language.get(cameraState.status == .interrupted ? "POS_Scanner_InterruptedSubtitle" : "POS_Scanner_AimSubtitle", alter: nil))
                    .font(PPBrandFont.regular(19, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { scannerTools }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { scannerTools }
                    VStack(spacing: 10) { scannerTools }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var scannerTools: some View {
        Button { torchRequested.toggle() } label: {
            Label(Language.get("POS_Scanner_Light", alter: nil), systemImage: cameraState.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(PPBrandFont.medium(19, relativeTo: .body))
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(cameraState.isTorchAvailable ? Color.white : Color.white.opacity(0.5))
                .background(cameraState.isTorchOn ? AdminSurface.primary : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!cameraState.isTorchAvailable || cameraState.status != .reading)
        .accessibilityValue(Language.get(cameraState.isTorchAvailable ? (cameraState.isTorchOn ? "POS_Scanner_LightOn" : "POS_Scanner_LightOff") : "POS_Scanner_LightUnavailable", alter: nil))

        Button { showingManualEntry = true } label: {
            Label(Language.get("POS_Scanner_Manual", alter: nil), systemImage: "keyboard")
                .font(PPBrandFont.medium(19, relativeTo: .body))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var scannerStateContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: scannerStateIcon)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80, alignment: .leading)
                    .accessibilityHidden(true)
                Text(scannerStateTitle)
                    .font(PPBrandFont.bold(32, relativeTo: .title))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(scannerStateSubtitle)
                    .font(PPBrandFont.regular(21, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                scannerStateAction
                Button { showingManualEntry = true } label: {
                    Label(Language.get("POS_Scanner_Manual", alter: nil), systemImage: "keyboard")
                        .font(PPBrandFont.medium(21, relativeTo: .body))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }

    private var cameraStatusTitle: String {
        switch cameraState.status {
        case .starting: return Language.get("POS_Scanner_Starting", alter: nil)
        case .reading: return Language.get("POS_Scanner_Reading", alter: nil)
        case .interrupted: return Language.get("POS_Scanner_Interrupted", alter: nil)
        case .unavailable: return Language.get("POS_Scanner_UnavailableTitle", alter: nil)
        }
    }

    @ViewBuilder
    private var scannerStateAction: some View {
        switch phase {
        case .permissionRequired:
            scannerActionButton(Language.get("POS_Scanner_Allow", alter: "السماح بالكاميرا"), icon: "camera.fill") {
                requestCameraAccess()
            }
        case .requesting:
            HStack(spacing: AdminSpacing.sm) {
                ProgressView().tint(.white)
                Text(Language.get("POS_Scanner_Requesting", alter: "بانتظار إذن الكاميرا…"))
                    .font(PPBrandFont.medium(19, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .frame(minHeight: 52)
        case .denied:
            scannerActionButton(Language.get("POS_Scanner_OpenSettings", alter: "فتح الإعدادات"), icon: "gearshape.fill") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        case .unavailable:
            scannerActionButton(Language.get("POS_Scanner_Retry", alter: "إعادة فحص الكاميرا"), icon: "arrow.clockwise") {
                refreshAuthorization()
            }
        case .ready:
            EmptyView()
        }
    }

    private func scannerActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(PPBrandFont.bold(21, relativeTo: .headline))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 10)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
        }
    }

    private var scannerStateIcon: String {
        switch phase {
        case .permissionRequired, .requesting: return "camera.viewfinder"
        case .denied: return "camera.fill.badge.xmark"
        case .unavailable: return "exclamationmark.triangle.fill"
        case .ready: return "barcode.viewfinder"
        }
    }

    private var scannerStateTitle: String {
        switch phase {
        case .permissionRequired, .requesting:
            return Language.get("POS_Scanner_PermissionTitle", alter: "استخدم الكاميرا لمسح الرمز")
        case .denied:
            return Language.get("POS_Scanner_DeniedTitle", alter: "الوصول إلى الكاميرا متوقف")
        case .unavailable:
            return Language.get("POS_Scanner_UnavailableTitle", alter: "الماسح غير متاح")
        case .ready:
            return Language.get("POS_Scanner_Title", alter: "مسح رمز المنتج")
        }
    }

    private var scannerStateSubtitle: String {
        switch phase {
        case .permissionRequired, .requesting:
            return Language.get("POS_Scanner_PermissionSubtitle", alter: nil)
        case .denied:
            return Language.get("POS_Scanner_DeniedSubtitle", alter: "فعّل الكاميرا للتطبيق من الإعدادات، ثم عُد للمسح.")
        case .unavailable:
            return Language.get("POS_Scanner_UnavailableSubtitle", alter: "تعذر تشغيل كاميرا أو قارئ رموز متوافق على هذا الجهاز.")
        case .ready:
            return ""
        }
    }

    private func requestCameraAccess() {
        phase = .requesting
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard isVisible, !hasFinished else { return }
                phase = granted ? .ready : .denied
            }
        }
    }

    private func refreshAuthorization() {
        guard !hasFinished, phase != .requesting else { return }
        let authorization = Self.phaseForCurrentAuthorization()
        if authorization != phase {
            cameraState = POSBarcodeCameraState()
            phase = authorization
        }
    }

    private func finish(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isVisible, !hasFinished, !trimmed.isEmpty else { return }
        hasFinished = true
        torchRequested = false
        onResult(trimmed)
    }

    private func cancel() {
        guard !hasFinished else { return }
        hasFinished = true
        torchRequested = false
        onCancel()
    }

    private static func phaseForCurrentAuthorization() -> POSBarcodeScannerPhase {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .permissionRequired
        case .denied, .restricted: return .denied
        @unknown default: return .unavailable
        }
    }
}

private struct BarcodeAperturePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct BarcodeCameraPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Both frames share SwiftUI's global coordinate space. Normalization avoids
/// assuming that a pushed controller and an inset sheet share a window origin.
private enum BarcodeScanGeometry {
    static func normalizedAperture(_ aperture: CGRect, in preview: CGRect) -> CGRect {
        guard aperture.width > 0, aperture.height > 0, preview.width > 0, preview.height > 0,
              [aperture.minX, aperture.minY, aperture.width, aperture.height,
               preview.minX, preview.minY, preview.width, preview.height].allSatisfy(\.isFinite) else { return .zero }
        let visible = aperture.intersection(preview)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return .zero }
        return CGRect(x: (visible.minX - preview.minX) / preview.width,
                      y: (visible.minY - preview.minY) / preview.height,
                      width: visible.width / preview.width,
                      height: visible.height / preview.height)
    }
}

private struct BarcodeApertureMask: Shape {
    var aperture: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if aperture.width > 0, aperture.height > 0 {
            path.addRoundedRect(in: aperture, cornerSize: CGSize(width: 22, height: 22))
        }
        return path
    }
}

private struct BarcodeApertureCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = min(32, rect.width / 4, rect.height / 3)
        let radius = min(18, arm / 2)
        for (x, y, dx, dy) in [(rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
                               (rect.maxX, rect.minY, CGFloat(-1), CGFloat(1)),
                               (rect.minX, rect.maxY, CGFloat(1), CGFloat(-1)),
                               (rect.maxX, rect.maxY, CGFloat(-1), CGFloat(-1))] {
            path.move(to: CGPoint(x: x, y: y + dy * arm))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        return path
    }
}

private struct BarcodeManualEntrySheet: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var code = ""
    @FocusState private var isCodeFocused: Bool

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(Language.get("POS_Scanner_Manual", alter: nil))
                    .font(PPBrandFont.bold(28, relativeTo: .title2))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.control, in: Circle())
                }
                .accessibilityLabel(Language.get("POS_Close", alter: nil))
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Language.get("POS_Scanner_ManualSubtitle", alter: nil))
                        .font(PPBrandFont.regular(21, relativeTo: .body))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Language.get("POS_Scanner_CodeLabel", alter: nil))
                        .font(PPBrandFont.medium(17, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.get("POS_Scanner_CodePlaceholder", alter: nil), text: $code)
                        .font(PPBrandFont.medium(25, relativeTo: .title2))
                        .foregroundStyle(AdminSurface.primaryText)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(code.isEmpty && Language.isRTL() ? .trailing : .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(18)
                        .frame(minHeight: 56)
                        .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        .focused($isCodeFocused)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .accessibilityLabel(Language.get("POS_Scanner_CodeLabel", alter: nil))

                    Button(action: submit) {
                        Label(Language.get("POS_Scanner_UseCode", alter: nil), systemImage: "checkmark")
                            .font(PPBrandFont.bold(22, relativeTo: .headline))
                            .foregroundStyle(trimmedCode.isEmpty ? AdminSurface.secondaryText : .white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.vertical, 10)
                            .background(trimmedCode.isEmpty ? AdminSurface.control : AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(trimmedCode.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { isCodeFocused = true }
    }

    private func submit() {
        guard !trimmedCode.isEmpty else { return }
        isCodeFocused = false
        onSubmit(trimmedCode)
    }
}

struct POSBarcodeCameraView: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onFailure: () -> Void
    /// Visible aperture normalized to preview bounds. Nil preserves full-frame legacy scanning.
    var scanRegion: CGRect? = nil
    var isActive = true
    var isTorchRequested = false
    var onStateChange: (POSBarcodeCameraState) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.metadataDelegate = context.coordinator
        controller.onFailure = onFailure
        controller.onStateChange = onStateChange
        controller.scanRegion = scanRegion
        controller.setCaptureActive(isActive)
        controller.setTorchRequested(isTorchRequested)
        context.coordinator.isAcceptingResults = isActive
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        context.coordinator.onResult = onResult
        context.coordinator.isAcceptingResults = isActive
        uiViewController.onFailure = onFailure
        uiViewController.onStateChange = onStateChange
        uiViewController.scanRegion = scanRegion
        uiViewController.setCaptureActive(isActive)
        uiViewController.setTorchRequested(isTorchRequested)
    }

    static func dismantleUIViewController(_ controller: ScannerViewController, coordinator: Coordinator) {
        coordinator.isAcceptingResults = false
        controller.shutdown()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onResult: (String) -> Void
        var isAcceptingResults = false {
            didSet {
                // A callback rejected during a pause must not exhaust the resumed
                // attempt. The screen's hasFinished gate owns final completion.
                if isAcceptingResults && !oldValue { didEmitResult = false }
            }
        }
        private var didEmitResult = false

        init(onResult: @escaping (String) -> Void) {
            self.onResult = onResult
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard isAcceptingResults, !didEmitResult,
                  let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
            didEmitResult = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onResult(value)
        }
    }
}

/// All mutable capture/device state below is confined to one serial queue. Only
/// the preview layer and main-queue metadata delegate read the session externally.
private final class ScannerCaptureSessionDriver: @unchecked Sendable {
    enum Event: Sendable {
        case configured, starting, reading, interrupted, failed
        case torch(available: Bool, isOn: Bool)
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.purepets.admin.pos.scanner", qos: .userInitiated)
    private weak var metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?
    private let onEvent: @MainActor @Sendable (Event) -> Void
    private var device: AVCaptureDevice?
    private var output: AVCaptureMetadataOutput?
    private var torchObservations: [NSKeyValueObservation] = []
    private var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var configured = false
    private var configurationFailed = false
    private var wantsRunning = false
    private var wantsTorch = false
    private var interrupted = false
    private var disposed = false

    init(delegate: AVCaptureMetadataOutputObjectsDelegate?, onEvent: @escaping @MainActor @Sendable (Event) -> Void) {
        metadataDelegate = delegate
        self.onEvent = onEvent
    }

    func configure() {
        queue.async { [self] in
            guard !disposed, !configured else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                failConfiguration()
                return
            }

            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            let metadata = AVCaptureMetadataOutput()
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                failConfiguration()
                return
            }
            session.addInput(input)
            guard session.canAddOutput(metadata) else {
                session.removeInput(input)
                session.commitConfiguration()
                failConfiguration()
                return
            }
            session.addOutput(metadata)
            metadata.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
            session.commitConfiguration()

            let supported: [AVMetadataObject.ObjectType] = [
                .qr, .ean8, .ean13, .pdf417, .code128, .code39, .code93, .upce, .dataMatrix, .aztec, .itf14
            ]
            let available = Set(metadata.availableMetadataObjectTypes)
            let enabled = supported.filter { available.contains($0) }
            if !enabled.isEmpty {
                metadata.metadataObjectTypes = enabled
            } else if !metadata.availableMetadataObjectTypes.isEmpty {
                metadata.metadataObjectTypes = metadata.availableMetadataObjectTypes
            } else {
                metadata.metadataObjectTypes = [.qr, .ean8, .ean13, .code128]
            }
            metadata.rectOfInterest = regionOfInterest

            device = camera
            output = metadata
            configured = true
            torchObservations = [
                camera.observe(\.isTorchAvailable, options: [.new]) { [weak self] _, _ in self?.refreshTorchState() },
                camera.observe(\.isTorchActive, options: [.new]) { [weak self] _, _ in self?.refreshTorchState() }
            ]
            emit(.configured)
            reconcileRunning()
        }
    }

    func setRunning(_ running: Bool) {
        queue.async { [self] in
            guard !disposed else { return }
            wantsRunning = running
            if !running { wantsTorch = false }
            reconcileRunning()
        }
    }

    func setTorchRequested(_ requested: Bool) {
        queue.async { [self] in
            guard !disposed, wantsTorch != requested else { return }
            wantsTorch = requested
            applyTorch()
        }
    }

    func updateRegionOfInterest(_ region: CGRect) {
        queue.async { [self] in
            guard !disposed, regionOfInterest != region else { return }
            regionOfInterest = region
            output?.rectOfInterest = region
        }
    }

    func setInterrupted(_ value: Bool) {
        queue.async { [self] in
            guard !disposed else { return }
            interrupted = value
            if value {
                wantsTorch = false
                applyTorch()
                emit(.interrupted)
            } else {
                reconcileRunning()
            }
        }
    }

    func handleRuntimeError(mediaServicesWereReset: Bool) {
        queue.async { [self] in
            guard !disposed, wantsRunning else { return }
            wantsTorch = false
            applyTorch()
            if mediaServicesWereReset, configured, !interrupted {
                reconcileRunning()
            } else {
                emit(.failed)
            }
        }
    }

    func shutdown() {
        // Retain the driver until the queued teardown has actually released hardware.
        queue.async { [self] in
            guard !disposed else { return }
            wantsRunning = false
            wantsTorch = false
            applyTorch()
            if session.isRunning { session.stopRunning() }
            output?.setMetadataObjectsDelegate(nil, queue: nil)
            torchObservations.removeAll()
            disposed = true
        }
    }

    private func reconcileRunning() {
        guard !disposed else { return }
        // Setup can fail before SwiftUI's onAppear enables the first attempt.
        // Re-report it then, rather than leaving an inert starting screen.
        if configurationFailed {
            if wantsRunning { emit(.failed) }
            return
        }
        guard configured else { return }
        guard wantsRunning else {
            applyTorch()
            if session.isRunning { session.stopRunning() }
            return
        }
        guard !interrupted, !session.isInterrupted else {
            emit(.interrupted)
            return
        }
        if !session.isRunning {
            emit(.starting)
            session.startRunning()
        }
        guard session.isRunning else {
            emit(session.isInterrupted ? .interrupted : .failed)
            return
        }
        applyTorch()
        emit(.reading)
    }

    private func failConfiguration() {
        configurationFailed = true
        emit(.failed)
    }

    private func applyTorch() {
        guard let device else { return }
        let turnOn = wantsTorch && wantsRunning && session.isRunning && !interrupted && device.isTorchAvailable
        guard device.hasTorch else {
            emit(.torch(available: false, isOn: false))
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if turnOn, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: min(0.6, AVCaptureDevice.maxAvailableTorchLevel))
            } else if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
        } catch {
            wantsTorch = false
            emit(.torch(available: false, isOn: device.isTorchActive))
            return
        }
        publishTorchState()
    }

    private func refreshTorchState() {
        queue.async { [weak self] in
            guard let self, !disposed else { return }
            publishTorchState()
        }
    }

    private func publishTorchState() {
        emit(.torch(available: device?.isTorchAvailable == true && wantsRunning && session.isRunning,
                    isOn: device?.isTorchActive == true))
    }

    private func emit(_ event: Event) {
        let callback = onEvent
        DispatchQueue.main.async { callback(event) }
    }
}

/// Notification token disposal stays independent of the controller's actor lifetime.
private final class ScannerNotificationBag {
    var tokens: [NSObjectProtocol] = []
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

final class ScannerViewController: UIViewController {
    private lazy var captureDriver = ScannerCaptureSessionDriver(delegate: metadataDelegate) { [weak self] event in
        self?.handleCaptureEvent(event)
    }
    private let notifications = ScannerNotificationBag()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var state = POSBarcodeCameraState()
    private var captureRequested = true
    private var torchRequested = false
    private var isVisible = false
    private var isDisposed = false
    private var lastRunningRequest: Bool?

    weak var metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?
    var onFailure: (() -> Void)?
    var onStateChange: ((POSBarcodeCameraState) -> Void)?
    var scanRegion: CGRect? { didSet { if isViewLoaded { updatePreviewGeometry() } } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: captureDriver.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        installObservers()
        updatePreviewGeometry()
        captureDriver.configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewGeometry()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        reconcileCapture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        torchRequested = false
        reconcileCapture()
    }

    func setCaptureActive(_ active: Bool) {
        captureRequested = active
        if isViewLoaded { reconcileCapture() }
    }

    func setTorchRequested(_ requested: Bool) {
        guard torchRequested != requested else { return }
        torchRequested = requested
        if isViewLoaded { captureDriver.setTorchRequested(requested) }
    }

    func shutdown() {
        guard !isDisposed else { return }
        isDisposed = true
        isVisible = false
        onFailure = nil
        onStateChange = nil
        captureDriver.shutdown()
        notifications.tokens.forEach(NotificationCenter.default.removeObserver)
        notifications.tokens.removeAll()
    }

    private func reconcileCapture() {
        let shouldRun = captureRequested && isVisible && !isDisposed && UIApplication.shared.applicationState == .active
        guard lastRunningRequest != shouldRun else { return }
        lastRunningRequest = shouldRun
        captureDriver.setRunning(shouldRun)
    }

    private func updatePreviewGeometry() {
        guard let layer = previewLayer, !isDisposed else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = view.bounds
        if let connection = layer.connection,
           let orientation = view.window?.windowScene?.interfaceOrientation {
            let angle: CGFloat
            switch orientation {
            case .portrait: angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            default: angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        CATransaction.commit()

        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let scanRegion {
            let localRegion = CGRect(x: view.bounds.minX + scanRegion.minX * view.bounds.width,
                                     y: view.bounds.minY + scanRegion.minY * view.bounds.height,
                                     width: scanRegion.width * view.bounds.width,
                                     height: scanRegion.height * view.bounds.height)
            let visible = localRegion.intersection(view.bounds)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else {
                captureDriver.updateRegionOfInterest(.zero)
                return
            }
            let region = layer.metadataOutputRectConverted(fromLayerRect: visible).intersection(unit)
            captureDriver.updateRegionOfInterest(region.isNull ? .zero : region)
        } else {
            captureDriver.updateRegionOfInterest(unit)
        }
    }

    private func handleCaptureEvent(_ event: ScannerCaptureSessionDriver.Event) {
        guard !isDisposed else { return }
        switch event {
        case .configured:
            updatePreviewGeometry()
            captureDriver.setTorchRequested(torchRequested)
            return
        case .starting: state.status = .starting
        case .reading:
            updatePreviewGeometry()
            state.status = .reading
        case .interrupted:
            state.status = .interrupted
            torchRequested = false
        case .failed:
            state.status = .unavailable
            onStateChange?(state)
            onFailure?()
            return
        case .torch(let available, let isOn):
            state.isTorchAvailable = available
            state.isTorchOn = isOn
        }
        if isVisible, captureRequested { onStateChange?(state) }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let session = captureDriver.session
        notifications.tokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureDriver.setInterrupted(true) }
        })
        notifications.tokens.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureDriver.setInterrupted(false) }
        })
        notifications.tokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] notification in
            let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
            MainActor.assumeIsolated { self?.captureDriver.handleRuntimeError(mediaServicesWereReset: reset) }
        })
        notifications.tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastRunningRequest = false
                self?.torchRequested = false
                self?.captureDriver.setRunning(false)
            }
        })
        notifications.tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileCapture() }
        })
    }
}
