# Wholesale integration handoff

2026-10-26: Created `ws` branch in `samo-spec/pure-pets-admin` from `main`.
Site is isolated inside `ws/`; no native iOS Admin modifications.

Implemented in this branch:
- Cloudflare Worker path routing, public static assets and runtime Firebase configuration.
- Public catalog and buyer-gated frontend (see subsequent commits).
- Unit and checkout-intent validation.

Security constraints:
- Existing Admin staff wholesale POS is staff-only.
- Wholesale pricing and writes belong in `samo-spec/pure-pets-infra`.
- Unconfigured backend must fail closed rather than fake order success.
- No production route or Firebase write deployment authorized as part of this integration.

Next: integrate canonical callable backend on Infra, run tests and preview, then request release approval.

Source integration: Admin ws includes public catalog UI, buyer authentication, saved/cart/order request states and browser App Check wiring. Infra ws includes read projection, buyer state and request-only callable backend. Deployment requires Firebase Web config, App Check site key, launch flags/branches and runtime test verification.

Next coding increment: staff operations UI at /ws/manage.html, buyer cancellation and quantity adjustments, checks in .github/workflows/ws-checks.yml. Pending: staff POS conversion handoff, browser/emulator testing and preview deployment.

2026-10-26 — Admin POS wholesale menu now opens a native request inbox sheet (new code in existing POSFastSellView.swift); branch scoping, staff decisions, product/pack line details and refresh. Native Xcode build not yet verified (simulator not used). Browser checkout now acknowledges submitted requests before attempting noncritical cart cleanup, preventing false retry messaging.

## Cloudflare deployment — 2026-10-26

- Preview Worker: `pure-pets-wholesale-preview` in account `66fa48e18ceed8c753ce22c4a092febd`.
- Preview URL: `https://pure-pets-wholesale-preview.long-meadow-a519.workers.dev/ws/` (Workers.dev enabled).
- Cloudflare Workers API deployed frontend HTML/CSS/JS snapshot to an isolated script, with assets embedded in the Worker module for preview only. Its code is derived from the `ws` branch and is **not** the canonical Wrangler static-assets production deployment.
- Firebase integration variables are not configured; catalog/auth/order services are not operational in preview.
- Cloudflare production routes remain empty: neither `pure-pets.net/ws` nor `pure-pets.net/ws/*` is attached.
- Release blocker: connect Firebase, deploy customer-safe backend functions + rules after security verification, create Firebase web app config and reCAPTCHA App Check key, publish approved wholesale branches/configuration, run E2E guest browsing and auth/cart/order tests. Then deploy canonical `ws/` Worker with Wrangler static assets and attach path-specific production routes.
- Do not deploy any existing Admin POS staff callables to public unprivileged access or mark quote requests paid.

## 2026-10-27 — Wholesale storefront redesign

- Replaced the layered stylesheet with one responsive system: editorial typography, Pure Pets rose controls, botanical brand panel, catalog tabs, product cards, detail/auth modals and buyer drawers. Official LogoV5 is served locally, optimized from 808 KB to 60 KB.
- Preserved callable names, payloads, buyer-gated actions and request-only checkout semantics. No Infra, Firebase rules, native Admin or production route changes.
- Fixed default wholesale pack selection, category keyboard focus, drawer focus containment/background inertness/Escape dismissal, translated control labels, saved-state feedback and order-history loading/error/retry. Fixed translation values equal to their key being skipped.
- Fixed build output to include manage.html. Added isolated preview snapshot builder reusing the canonical Worker and dist assets; preview configuration bindings are inherited.
- Validation: 13 Node tests pass, build and syntax checks pass, 10 temporary DOM interaction assertions pass with synthetic catalog/buyer data (no Firebase writes). Cloud browser verified Arabic/English storefront and guest cart sign-in gate; Cloudflare rendering verified the 390×844 mobile view. Product/cart/order UI checks with fixtures do not prove real Firebase integration.
- Tool limits: 12ui improve could not capture because its browser runtime was unavailable; browser installation download failed. Built-in image generation supplied the visual direction; actual app logo replaces the illustrative pet photography and invented brand mark from the concept.
- Updated existing Workers.dev preview only. Firebase client configuration and App Check site key remain absent (settings expose only FUNCTIONS_REGION). Real catalog/auth/order E2E remains blocked; preview reports catalog unavailable and does not simulate order success. pure-pets.net/ws is not attached.
