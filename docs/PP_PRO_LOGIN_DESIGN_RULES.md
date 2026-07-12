# Pure Pets Pro Login Design Rules

This document is the local fallback for the requested design-system guidance because the Figma rules generator could not authenticate during this session.

## Intent

Build entry surfaces that feel premium, minimal, and calm while preserving the existing Objective-C authentication flow as the source of truth.

## Product Rules

- Keep `AdminLoginViewController` untouched as the legacy reference implementation.
- New login experiences may be hosted in SwiftUI, but auth logic must stay reusable and production-safe in Objective-C coordinators or services.
- App startup should route through `SceneDelegate` and app-level fallback roots instead of directly presenting the legacy login controller.
- All login copy must remain localized through the existing `.strings` files and `Language` helpers.

## Visual Rules

- Prefer a single strong hero surface instead of stacked cards or noisy chrome.
- Use generous spacing, sharp hierarchy, and restrained ornamentation.
- Keep the primary action visually dominant and keep secondary actions quiet.
- Use soft gradients, subtle glow, and material layering only when they support readability.
- Motion should be short, smooth, and purposeful: focus changes, button press feedback, and gentle state transitions.

## Typography

- Use the existing Beiruti family for a branded, polished Arabic-first presentation.
- Titles should feel confident and compact.
- Supporting copy should stay short, airy, and low-contrast relative to the headline.

## Color and Surface

- Favor the app’s existing color assets instead of introducing ad-hoc palette values.
- Primary references:
  - `AppBackgroundClr`
  - `AppBackgroundClrShiner`
  - `AppPrimaryClr`
  - `AppPrimaryClrDarker`
  - `AppPrimaryClrShiner`
  - `PrimaryTextClr`
  - `SeconderyTextClr`
  - `AppForgroundColr`
- Keep contrast high enough for form readability and error visibility.

## Interaction Rules

- Email and password fields should feel deliberate, roomy, and touch-friendly.
- Remember-me, forgot-password, biometric, and language actions should remain accessible without competing with the primary CTA.
- Loading and error states must feel stable; avoid layout jumps.
- Biometric affordances should appear only when the underlying service confirms availability.

## Engineering Rules

- Preserve the current Firebase auth, staff gating, claims fallback, and cached-user boot behavior.
- Do not duplicate business logic in SwiftUI views.
- Keep the screen modular: view, view model, and coordinator responsibilities should stay separate.
- Any future login redesign should extend this pattern rather than editing the legacy controller.
