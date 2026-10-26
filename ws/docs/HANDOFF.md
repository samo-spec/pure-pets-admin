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
