import SwiftUI
import UIKit
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
    public var onBack: () -> Void
    public let trailingContent: TrailingContent

    public init(
        title: String,
        subtitle: String? = nil,
        statusDotColor: Color? = Color(uiColor: .ppSuccess),
        onBack: @escaping () -> Void,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusDotColor = statusDotColor
        self.onBack = onBack
        self.trailingContent = trailingContent()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AdminSquircleBackButton(action: onBack)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

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
        onBack: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            statusDotColor: statusDotColor,
            onBack: onBack,
            trailingContent: { EmptyView() }
        )
    }
}