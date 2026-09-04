import SwiftUI
import UIKit
import CoreText
import Kingfisher

/// The only remote-image pipeline used by the Admin app. Its named Kingfisher cache
/// persists catalog, POS, banner, and profile media on disk for subsequent screens.
enum AdminRemoteImageCache {
    static let cache: ImageCache = {
        let cache = ImageCache(name: "com.pb.purepets.admin.remote-images")
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()

    static let options: KingfisherOptionsInfo = [
        .targetCache(cache),
        .cacheOriginalImage
    ]
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
        self.url = url
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let url {
                if let targetSize {
                    KFImage(url)
                        .placeholder { placeholder }
                        .targetCache(AdminRemoteImageCache.cache)
                        .setProcessor(DownsamplingImageProcessor(size: targetSize))
                        .cacheOriginalImage()
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    KFImage(url)
                        .placeholder { placeholder }
                        .targetCache(AdminRemoteImageCache.cache)
                        .cacheOriginalImage()
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                placeholder
            }
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
        guard let urlString, let url = URL(string: urlString) else {
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
        guard let urlString, let url = URL(string: urlString) else {
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
        guard let urlString else { return nil }
        return AdminRemoteImageCache.cache.retrieveImageInMemoryCache(forKey: urlString)
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(AdminSurface.secondaryText).font(.system(size: 15, weight: .medium))
            TextField(placeholder, text: $text).font(AdminType.callout).foregroundColor(AdminSurface.primaryText)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(AdminSurface.secondaryText).font(.system(size: 16)) }.frame(minWidth: 44, minHeight: 44).accessibilityLabel(Language.get("Clear", alter: nil)) }
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

/// Signature pill action button (e.g. "✓ حفظ" Save pill) with brand glow shadow.
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
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .heavy))
                    Text(title)
                        .font(AdminType.calloutBold)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AdminSurface.primary, in: Capsule())
            .shadow(color: AdminSurface.primary.opacity(0.35), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// Sovereign Glassmorphic Navigation Bar pinned to safe area with squircle back button, title stack, and trailing action.
public struct AdminSovereignNavigationBar<TrailingContent: View>: View {
    public let title: String
    public var subtitle: String?
    public var statusDotColor: Color?
    public var isModal: Bool
    public var onBack: () -> Void
    public let trailingContent: TrailingContent

    public init(
        title: String,
        subtitle: String? = nil,
        statusDotColor: Color? = Color(uiColor: .ppSuccess),
        isModal: Bool = false,
        onBack: @escaping () -> Void,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusDotColor = statusDotColor
        self.isModal = isModal
        self.onBack = onBack
        self.trailingContent = trailingContent()
    }

    public var body: some View {
        VStack(spacing: 0) {
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
                        HStack(spacing: 6) {
                            if let dotColor = statusDotColor {
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 6, height: 6)
                            }
                            Text(sub)
                                .font(AdminType.caption2)
                                .foregroundStyle(statusDotColor ?? AdminSurface.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }

                Spacer(minLength: 8)

                trailingContent
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                Color.clear
                    .ignoresSafeArea(edges: .top)
            )
        }
    }
}

extension AdminSovereignNavigationBar where TrailingContent == EmptyView {
    public init(
        title: String,
        subtitle: String? = nil,
        statusDotColor: Color? = Color(uiColor: .ppSuccess),
        isModal: Bool = false,
        onBack: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            statusDotColor: statusDotColor,
            isModal: isModal,
            onBack: onBack,
            trailingContent: { EmptyView() }
        )
    }
}

// MARK: - Sovereign English Numeric Input & Normalization

extension String {
    /// Normalizes Arabic-Indic (٠-٩) and Eastern Arabic (۰-۹) numerals into ASCII English digits (0-9).
    /// If `allowsDecimal` is true, replaces Arabic decimal separators (٫, ،, ,) with `.`, ensuring at most one decimal point.
    /// If `allowsDecimal` is false, discards any non-digit character.
    public func normalizedEnglishDigits(allowsDecimal: Bool = true) -> String {
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

    /// Convenience getter for decimal-tolerant English numeric normalization.
    public var normalizedEnglishDigits: String {
        normalizedEnglishDigits(allowsDecimal: true)
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
