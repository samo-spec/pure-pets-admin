# Pure Pets wholesale buying desk

2026-10-27 · Scope: the storefront and staff workspace in `ws/`.

## Direction

A product-first wholesale buying desk, with Pure Pets rose (#CB2654), graphite text, light surfaces, locally hosted Manrope and Noto Sans Arabic, the existing official logo, and an original pet portrait. The image supports the brand; catalog imagery always comes from actual catalog records. No product, price, sales metric or availability is invented in the shipped application.

Three useful interactions define the experience:

- Switch between visual product cards and a compact purchasing list without losing search or category selection.
- Compose a pack order with an explicit default selling unit, quantity stepper and immediate unit/price calculation in integer minor units.
- Keep the next order in view through a desktop order desk or a mobile cart dock. Cart, saved products and requests share one buyer workspace.

Surfaces use 16–24px corners, fields/buttons 8–10px, close controls are circular. Motion is limited to initial hierarchy, panel entry, hover and press feedback. All motion stops with `prefers-reduced-motion`. Both directions use logical layout properties; language and display preferences persist when browser storage permits.

## Preserved integration boundaries

The existing Firebase Auth, App Check, callable names, request payloads, branch permissions, request-only checkout, audited staff acceptance/rejection and cancellation flow remain. No schema, rules, native Admin code or production route changes. Accepting a request still creates no sale, payment or inventory reservation.

## State and accessibility coverage

- Catalog: skeleton, loaded, search empty/reset, unconfigured/error/retry, retained catalog on pagination error, unavailable stock and image failure.
- Detail: selected default pack, live quote, invalid quantity, unavailable product and guest continuation.
- Buyer: sign-in/register, empty and populated cart/saved/orders, retained branch selection, blocked concurrent mutations, retryable save failure, incomplete pricing, separate currency subtotals, acknowledged request with failed cart cleanup.
- Staff: guest/service error, authorized branches, no access, loading, empty queue, request error, translated statuses, accept/reject confirmation, inline review failure and stale branch-response protection.
- Native dialogs, labelled inputs, keyboard focus containment/restoration, background inertness, accessible status announcements, reduced motion and forced-colors support.

## Validation

`npm ci --ignore-scripts --no-audit --no-fund` followed by `npm run check` in `ws/`.

27 tests pass, including DOM interaction tests using synthetic records and mocked callables. No test signs in or writes to real Firebase data. Browser observations confirm Arabic/English storefront rendering, loaded local fonts/images, staff sign-in/service-error presentation and no desktop page overflow. A 390px mobile capture and fixture catalog capture show no page overflow. Fixture screenshots validate layout only, not production data or live Firebase authorization.

Real catalog/auth/cart/order/staff E2E remains unverified because the preview has no Firebase client configuration or App Check site key. No Lighthouse, real-device Safari or production Core Web Vitals measurement is claimed.

## Asset provenance

`assets/companions.webp` is an original image generated with the built-in image tool, encoded to WebP for the site (about 92KB). The original PNG was not needed in the shipped bundle. Generation prompt:

> Use case: photorealistic-natural. Asset type: premium Pure Pets wholesale storefront hero photograph, landscape composition about 3:2. An exquisitely art directed studio photograph of a friendly cream golden retriever and an elegant grey British shorthair cat sitting together. Dog on the left, cat a little in front on the right, both facing the camera. The dog has a subtle rose pink collar. Background is seamless cool pale rose pink #F5E7EC, floor same material. Soft natural directional studio light, tactile fur detail, genuine calm expressions, candid charm, soft shadow grounding the animals. Full heads and ears visible with generous headroom and margin. Subjects placed in the middle-lower area, enough margin for responsive crops. Contemporary luxury pet-care editorial photography, realistic anatomy, refined and warm without looking artificial. No words, no logos, no text, no packaging, no products, no badges, no watermarks.

Fonts are distributed under SIL OFL; the Phosphor icon sprite under MIT. License texts are in `docs/licenses/`. The official Pure Pets logo is unchanged.
