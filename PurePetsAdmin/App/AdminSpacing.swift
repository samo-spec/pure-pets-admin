//  AdminSpacing.swift — Core design system tokens for NextGen V6 SwiftUI rebuild.
//  Bridges PPDesignTokens.h UIKit constants into SwiftUI-native values.

import SwiftUI

// MARK: - Spacing (8pt Grid)

enum AdminSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let screenMargin: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let groupSpacing: CGFloat = 20
    static let rowMinimumHeight: CGFloat = 52
}

// MARK: - Corner Radii

enum AdminRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let card: CGFloat = 16
    static let large: CGFloat = 20
    static let hero: CGFloat = 24
    static let pill: CGFloat = 999
    static let button: CGFloat = 14
}

// MARK: - Touch Targets

enum AdminTouchTarget {
    static let minimum: CGFloat = 44
    static let comfortable: CGFloat = 48
    static let expanded: CGFloat = 56
}

// MARK: - Animation

enum AdminAnimation {
    static let fast = Animation.easeOut(duration: 0.15)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let slow = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let pressScale: CGFloat = 0.97
}

// MARK: - Shadow

enum AdminShadow {
    static let card: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.06), 8, 2)
    static let elevated: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.10), 16, 4)
    static let navigation: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.04), 4, 1)
}

// MARK: - Icon Sizes

enum AdminIconSize {
    static let small: CGFloat = 16
    static let medium: CGFloat = 20
    static let large: CGFloat = 24
    static let xl: CGFloat = 32
    static let hero: CGFloat = 44
}

// MARK: - Opacity

enum AdminOpacity {
    static let disabled: Double = 0.38
    static let secondary: Double = 0.60
    static let subtleBackground: Double = 0.07
    static let pressedOverlay: Double = 0.12
}

// MARK: - Stroke

enum AdminStroke {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1.0
    static let medium: CGFloat = 1.5
}