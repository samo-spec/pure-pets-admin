//
//  PPAdminStickerKit.swift
//  PurePetsAdmin
//
//  Chat Stickers subsystem for Pure Pets Admin, maintaining 100% interoperability
//  and exact wire-contract parity with Pure Pets iOS consumer app.
//

import SwiftUI
import UIKit
import FirebaseStorage

// MARK: - Sticker Model

@objc(PPChatSticker)
public final class PPChatSticker: NSObject, Identifiable, Sendable {
    @objc public let storagePath: String
    @objc public let downloadURLString: String
    @objc public let displayName: String

    public var id: String { cacheKey }

    @objc public var cacheKey: String {
        storagePath.isEmpty ? downloadURLString : storagePath
    }

    @objc public init(
        storagePath: String,
        downloadURLString: String,
        displayName: String
    ) {
        self.storagePath = storagePath
        self.downloadURLString = downloadURLString
        self.displayName = displayName
        super.init()
    }
}

private struct PPStickerManifestEntry: Codable {
    let storagePath: String
    let downloadURLString: String
    let displayName: String
}

public enum PPAdminStickerPickerPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case offline
    case failed
}

// MARK: - Sticker Store

@objc(PPAdminStickerStore)
public final class PPAdminStickerStore: NSObject, ObservableObject, @unchecked Sendable {
    @objc public static let shared = PPAdminStickerStore()

    @Published public private(set) var stickers: [PPChatSticker] = []
    @Published public private(set) var phase: PPAdminStickerPickerPhase = .idle
    @Published public private(set) var isRefreshing = false

    private let workQueue = DispatchQueue(label: "com.purepets.admin.stickers.cache", qos: .userInitiated)
    private var hasLoadedRemoteManifest = false

    private lazy var cacheDirectory: URL = {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root.appendingPathComponent("PPAdminStickerCache", isDirectory: true)
    }()

    private var manifestURL: URL {
        cacheDirectory.appendingPathComponent("stickers.json", isDirectory: false)
    }

    public override init() {
        super.init()
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        let cached = loadCachedManifest()
        if !cached.isEmpty {
            stickers = cached
            phase = .ready
        }
    }

    @objc public func warmStickerCache() {
        refreshStickers(force: false)
    }

    public func resolveURL(for storagePath: String, completion: @escaping (URL?) -> Void) {
        let trimmed = storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil)
            return
        }
        if let existing = stickers.first(where: { $0.storagePath == trimmed }),
           let url = URL(string: existing.downloadURLString) {
            completion(url)
            return
        }
        Storage.storage().reference(withPath: trimmed).downloadURL { (url: URL?, _: Error?) in
            completion(url)
        }
    }

    public func refreshStickers(force: Bool = false) {
        if isRefreshing { return }
        if hasLoadedRemoteManifest, !force, !stickers.isEmpty {
            return
        }

        let cached = loadCachedManifest()
        if !cached.isEmpty, stickers.isEmpty {
            stickers = cached
            phase = .ready
        } else if stickers.isEmpty {
            phase = .loading
        }

        isRefreshing = true

        let folder = Storage.storage().reference().child("stickers")
        listStickerReferences(in: folder) { [weak self] references, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.isRefreshing = false
                    self.phase = self.isOfflineError(error) ? .offline : .failed
                }
                return
            }

            let items = references
                .filter { self.isSupportedStickerReference($0) }
                .sorted { $0.fullPath.localizedStandardCompare($1.fullPath) == .orderedAscending }

            guard !items.isEmpty else {
                DispatchQueue.main.async {
                    self.isRefreshing = false
                    self.stickers = []
                    self.phase = .empty
                    self.persistManifest([])
                }
                return
            }

            self.resolveDownloadURLs(for: items)
        }
    }

    private func listStickerReferences(
        in folder: StorageReference,
        completion: @escaping ([StorageReference], Error?) -> Void
    ) {
        folder.listAll { result, error in
            if let error {
                completion([], error)
                return
            }

            var references = result?.items ?? []
            let prefixes = result?.prefixes ?? []
            guard !prefixes.isEmpty else {
                completion(references, nil)
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var firstError: Error?

            for prefix in prefixes {
                group.enter()
                self.listStickerReferences(in: prefix) { nestedReferences, nestedError in
                    lock.lock()
                    if let nestedError, firstError == nil {
                        firstError = nestedError
                    }
                    references.append(contentsOf: nestedReferences)
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(references, firstError)
            }
        }
    }

    private func resolveDownloadURLs(for items: [StorageReference]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var resolved: [PPChatSticker] = []

        for item in items {
            group.enter()
            item.downloadURL { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let sticker = PPChatSticker(
                    storagePath: item.fullPath,
                    downloadURLString: url.absoluteString,
                    displayName: (item.name as NSString).deletingPathExtension
                )
                lock.lock()
                resolved.append(sticker)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let sortedStickers = resolved.sorted {
                $0.storagePath.localizedStandardCompare($1.storagePath) == .orderedAscending
            }

            self.isRefreshing = false
            self.hasLoadedRemoteManifest = true
            self.stickers = sortedStickers
            self.phase = sortedStickers.isEmpty ? .empty : .ready
            self.persistManifest(sortedStickers)
        }
    }

    private func persistManifest(_ stickers: [PPChatSticker]) {
        let entries = stickers.map {
            PPStickerManifestEntry(
                storagePath: $0.storagePath,
                downloadURLString: $0.downloadURLString,
                displayName: $0.displayName
            )
        }
        let cacheDir = cacheDirectory
        let fileURL = manifestURL
        workQueue.async {
            try? FileManager.default.createDirectory(
                at: cacheDir,
                withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func loadCachedManifest() -> [PPChatSticker] {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([PPStickerManifestEntry].self, from: data) else {
            return []
        }

        return entries.map {
            PPChatSticker(
                storagePath: $0.storagePath,
                downloadURLString: $0.downloadURLString,
                displayName: $0.displayName
            )
        }
    }

    private func isSupportedStickerReference(_ reference: StorageReference) -> Bool {
        let name = reference.name
        guard !name.hasPrefix(".") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["png", "webp", "gif", "jpg", "jpeg", "heic"].contains(ext)
    }

    private func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorTimedOut,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorDataNotAllowed
            ].contains(nsError.code)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isOfflineError(underlying)
        }
        return false
    }
}

// MARK: - Sticker Picker Sheet

public struct PPAdminStickerPickerSheet: View {
    @ObservedObject private var store = PPAdminStickerStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let onSelect: (PPChatSticker) -> Void

    public init(onSelect: @escaping (PPChatSticker) -> Void) {
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 76.0, maximum: 96.0),
                spacing: AdminSpacing.md
            )
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if store.phase == .offline, !store.stickers.isEmpty {
                offlineBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            content
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .onAppear {
            store.refreshStickers(force: false)
        }
        .modifier(PPAdminStickerSheetPresentationModifier())
    }

    private var header: some View {
        HStack(spacing: AdminSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("chat_stickers_title", alter: "ملصقات المحادثة"))
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                Text(Language.get("chat_stickers_subtitle", alter: "اختر ملصقاً للمحادثة للتعبير الفوري"))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AdminSpacing.sm)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.refreshStickers(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline))
            }
            .accessibilityLabel(Language.get("chat_stickers_retry", alter: "تحديث"))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline))
            }
            .accessibilityLabel(Language.get("cancel", alter: "إلغاء"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.lg)
        .padding(.bottom, AdminSpacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if store.stickers.isEmpty {
            switch store.phase {
            case .loading, .idle:
                stateView(
                    icon: "hourglass",
                    title: Language.get("chat_stickers_loading_title", alter: "جارٍ تحميل الملصقات..."),
                    subtitle: Language.get("chat_stickers_loading_subtitle", alter: "يرجى الانتظار قليلاً"),
                    showsProgress: true
                )
            case .empty:
                stateView(
                    icon: "face.smiling",
                    title: Language.get("chat_stickers_empty_title", alter: "لا توجد ملصقات متاحة"),
                    subtitle: Language.get("chat_stickers_empty_subtitle", alter: "لم يتم العثور على أي ملصقات في التخزين السحابي."),
                    showsProgress: false
                )
            case .offline:
                retryStateView(
                    icon: "wifi.slash",
                    title: Language.get("chat_stickers_offline_title", alter: "لا يوجد اتصال بالإنترنت"),
                    subtitle: Language.get("chat_stickers_offline_subtitle", alter: "يرجى التحقق من اتصالك بالشبكة وإعادة المحاولة.")
                )
            case .failed:
                retryStateView(
                    icon: "exclamationmark.triangle",
                    title: Language.get("chat_stickers_error_title", alter: "تعذر تحميل الملصقات"),
                    subtitle: Language.get("chat_stickers_error_subtitle", alter: "حدث خطأ أثناء مزامنة الملصقات مع الخادم.")
                )
            case .ready:
                EmptyView()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AdminSpacing.md) {
                    ForEach(store.stickers) { sticker in
                        PPAdminStickerPickerItem(sticker: sticker) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSelect(sticker)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.xs)
                .padding(.bottom, AdminSpacing.xl)
            }
            .overlay(alignment: .top) {
                if store.isRefreshing {
                    ProgressView()
                        .tint(AdminSurface.primary)
                        .padding(.top, AdminSpacing.xs)
                }
            }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: AdminSpacing.xs) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(Language.get("chat_stickers_offline_cached", alter: "عرض الملصقات المحفوظة محلياً (وضع عدم الاتصال)"))
                .font(AdminType.caption2)
                .lineLimit(1)
        }
        .foregroundColor(Color(uiColor: .ppWarning))
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, AdminSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .ppWarning).opacity(0.12))
    }

    private func stateView(
        icon: String,
        title: String,
        subtitle: String,
        showsProgress: Bool
    ) -> some View {
        VStack(spacing: AdminSpacing.md) {
            if showsProgress {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.1)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Text(subtitle)
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, AdminSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryStateView(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: AdminSpacing.lg) {
            stateView(
                icon: icon,
                title: title,
                subtitle: subtitle,
                showsProgress: false
            )
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.refreshStickers(force: true)
            } label: {
                Label(Language.get("chat_stickers_retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                    .font(AdminType.calloutBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, AdminSpacing.xl)
                    .frame(height: 44)
                    .background(AdminSurface.primary, in: Capsule())
            }
            .padding(.bottom, AdminSpacing.xl)
        }
    }
}

// MARK: - Sticker Grid Item

private struct PPAdminStickerPickerItem: View {
    let sticker: PPChatSticker
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.5)
                    )

                if let url = URL(string: sticker.downloadURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(AdminSpacing.sm)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        case .empty:
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AdminSurface.primary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        }
        .buttonStyle(PPAdminStickerItemButtonStyle())
        .accessibilityLabel(sticker.displayName.isEmpty ? Language.get("chat_stickers_title", alter: "ملصق") : sticker.displayName)
    }
}

private struct PPAdminStickerItemButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.94 : 1.0))
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.08),
                radius: configuration.isPressed ? 3.0 : 8.0,
                x: 0,
                y: configuration.isPressed ? 1.0 : 4.0
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PPAdminStickerSheetPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
