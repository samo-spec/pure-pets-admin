//
//  PPSwipeToPopNavigation.swift
//  PurePetsAdmin
//
//  Production-Grade Shared Swipe-to-Pop Navigation System.
//  Supports LTR / English (left edge swipe right) and RTL / Arabic (right edge swipe left).
//  Prefers Apple's native UINavigationController.interactivePopGestureRecognizer with robust delegate.
//  Includes a velocity-aware leading-edge fallback DragGesture only when native UINavigationController is absent.
//

import SwiftUI
import UIKit

// MARK: - SwiftUI View Modifier & API

extension View {
    /// Enables production-grade, language-aware swipe-to-pop navigation.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether swipe-to-pop is enabled (default `true`).
    ///   - onCustomPop: Optional custom closure to run on pop (e.g., to confirm unsaved changes).
    /// - Returns: A view that supports natural edge swipe navigation following layoutDirection.
    public func enableSwipeToPop(
        isEnabled: Bool = true,
        onCustomPop: (() -> Void)? = nil
    ) -> some View {
        modifier(PPSwipeToPopViewModifier(isEnabled: isEnabled, onCustomPop: onCustomPop))
    }
}

public struct PPSwipeToPopViewModifier: ViewModifier {
    public let isEnabled: Bool
    public let onCustomPop: (() -> Void)?

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.dismiss) private var dismissAction

    @State private var hasUIKitNavigationController: Bool = true
    @State private var isPopping: Bool = false

    public init(isEnabled: Bool = true, onCustomPop: (() -> Void)? = nil) {
        self.isEnabled = isEnabled
        self.onCustomPop = onCustomPop
    }

    public func body(content: Content) -> some View {
        let isRTL = layoutDirection == .rightToLeft

        content
            .background(
                PPSwipeToPopUIKitBridge(
                    isEnabled: isEnabled,
                    isRTL: isRTL,
                    onCustomPop: onCustomPop
                ) { hasNav in
                    if self.hasUIKitNavigationController != hasNav {
                        self.hasUIKitNavigationController = hasNav
                    }
                }
            )
            .overlay(alignment: .leading) {
                if isEnabled {
                    PPSwipeToPopFallbackEdgeStrip(
                        isRTL: isRTL,
                        onPop: {
                            performPop()
                        }
                    )
                }
            }
    }

    private func performPop() {
        guard !isPopping else { return }
        isPopping = true

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let onCustomPop = onCustomPop {
            onCustomPop()
        } else {
            dismissAction()
            PPAdminNavigationFallback.popOrDismiss()
        }

        // Reset debounce after animation window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPopping = false
        }
    }
}

// MARK: - UIKit Bridge (Re-enabling Native interactivePopGestureRecognizer)

public struct PPSwipeToPopUIKitBridge: UIViewControllerRepresentable {
    public let isEnabled: Bool
    public let isRTL: Bool
    public let onCustomPop: (() -> Void)?
    public let onNavigationStatusChanged: (Bool) -> Void

    public init(
        isEnabled: Bool,
        isRTL: Bool,
        onCustomPop: (() -> Void)?,
        onNavigationStatusChanged: @escaping (Bool) -> Void
    ) {
        self.isEnabled = isEnabled
        self.isRTL = isRTL
        self.onCustomPop = onCustomPop
        self.onNavigationStatusChanged = onNavigationStatusChanged
    }

    public func makeUIViewController(context: Context) -> PPSwipeToPopBridgeViewController {
        let controller = PPSwipeToPopBridgeViewController()
        controller.isEnabled = isEnabled
        controller.isRTL = isRTL
        controller.onCustomPop = onCustomPop
        controller.onNavigationStatusChanged = onNavigationStatusChanged
        return controller
    }

    public func updateUIViewController(_ uiViewController: PPSwipeToPopBridgeViewController, context: Context) {
        uiViewController.isEnabled = isEnabled
        uiViewController.isRTL = isRTL
        uiViewController.onCustomPop = onCustomPop
        uiViewController.onNavigationStatusChanged = onNavigationStatusChanged
        uiViewController.applyConfiguration()
    }
}

public final class PPSwipeToPopBridgeViewController: UIViewController {
    public var isEnabled: Bool = true
    public var isRTL: Bool = false
    public var onCustomPop: (() -> Void)?
    public var onNavigationStatusChanged: ((Bool) -> Void)?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyConfiguration()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyConfiguration()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyConfiguration()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyConfiguration()
    }

    public func applyConfiguration() {
        guard let nav = findEnclosingNavigationController() else {
            onNavigationStatusChanged?(false)
            return
        }

        onNavigationStatusChanged?(true)

        // Configure native interactive pop on the enclosing navigation controller
        nav.pp_enableSwipeToPop()

        if let gesture = nav.interactivePopGestureRecognizer as? UIScreenEdgePanGestureRecognizer {
            gesture.isEnabled = isEnabled
            gesture.edges = isRTL ? .right : .left
        } else if let gesture = nav.interactivePopGestureRecognizer {
            gesture.isEnabled = isEnabled
        }

        let expectedAttr: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        if nav.view.semanticContentAttribute != expectedAttr {
            nav.view.semanticContentAttribute = expectedAttr
        }
    }

    private func findEnclosingNavigationController() -> UINavigationController? {
        if let nav = navigationController {
            return nav
        }
        var current: UIViewController? = parent
        while let c = current {
            if let nav = c as? UINavigationController {
                return nav
            }
            if let nav = c.navigationController {
                return nav
            }
            current = c.parent
        }
        return nil
    }
}

// MARK: - Velocity-Aware Leading-Edge Fallback Drag Gesture

/// Fallback edge strip: Pinned to a narrow 28pt strip along the leading edge so it never
/// interferes with scrolling, carousels, sliders, cards, or buttons deeper in the screen.
public struct PPSwipeToPopFallbackEdgeStrip: View {
    public let isRTL: Bool
    public let onPop: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggered: Bool = false

    public init(isRTL: Bool, onPop: @escaping () -> Void) {
        self.isRTL = isRTL
        self.onPop = onPop
    }

    public var body: some View {
        Color.clear
            .frame(width: 28)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .onChanged { value in
                        guard !hasTriggered else { return }

                        let translationX = value.translation.width
                        let translationY = value.translation.height

                        // Ignore if movement is primarily vertical (preserve vertical scrolling)
                        guard abs(translationX) > abs(translationY) * 1.2 else { return }

                        // Validate direction:
                        // LTR: must swipe right (translationX > 0)
                        // RTL: must swipe left (translationX < 0)
                        let isValidDirection = isRTL ? (translationX < 0) : (translationX > 0)
                        guard isValidDirection else { return }

                        dragOffset = abs(translationX)

                        // Velocity / distance check:
                        let predictedX = abs(value.predictedEndTranslation.width)
                        if dragOffset > 75 || (dragOffset > 30 && predictedX > 140) {
                            hasTriggered = true
                            onPop()
                        }
                    }
                    .onEnded { value in
                        if !hasTriggered {
                            let translationX = value.translation.width
                            let translationY = value.translation.height
                            let isValidDirection = isRTL ? (translationX < 0) : (translationX > 0)

                            if isValidDirection && abs(translationX) > abs(translationY) * 1.2 {
                                let predictedX = abs(value.predictedEndTranslation.width)
                                if abs(translationX) > 60 || predictedX > 120 {
                                    hasTriggered = true
                                    onPop()
                                }
                            }
                        }
                        dragOffset = 0
                        hasTriggered = false
                    }
            )
            .frame(width: 28)
            .ignoresSafeArea(.container, edges: .leading)
    }
}
