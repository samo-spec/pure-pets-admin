# Pure Pets Wholesale — /ws

A separate wholesale customer storefront inside the Admin repository, **not** an internal admin surface.

- Admin Git branch: `ws`
- Production target: `https://pure-pets.net/ws/`, presently **not deployed**
- Host: Cloudflare Workers Static Assets; route only `pure-pets.net/ws` and `pure-pets.net/ws/*` after release approval
- Backend: canonical Firebase Infra callable endpoints (`listWholesaleCatalog`, `getWholesaleBuyerState`, `saveWholesaleBuyerState`, `createWholesaleOrderRequest`, `listWholesaleOrderRequests`)
- Authentication: Firebase email/password provider, when enabled by project owner.
- Public catalog: no sign-in; all protected actions interrupt with modal then resume.
- Payment: NOT collected by this site; checkout submits a wholesale request pending staff confirmation. Neither POS payment nor inventory deduction is bypassed.

## Development

`npm install`
`npm test`
`npm run build`
`npx wrangler dev`

Set `FIREBASE_CLIENT_CONFIG` in Cloudflare Worker environment to a JSON Firebase web app config (no service-account keys). It is safe for the Firebase web API key and project IDs to reach browsers, **not** privileged credentials. Set `FUNCTIONS_REGION` if different from us-central1.

Production requires a separately reviewed Infra backend deployment, rules review, preview QA, Cloudflare route attachment, and fresh release approval. Client routes outside /ws must remain with the existing Pages site. Never widen the staff-only `processTransaction` callable.

Set `FIREBASE_APPCHECK_SITE_KEY` to a registered Firebase Web App Check reCAPTCHA v3 site key before preview. The Firebase callables enforce App Check; sign-in and browsing must fail closed if no valid site key is configured.

## Staff operations

Staff review: `/ws/manage.html` (same deployed Worker, separate protected UI). Firebase staff login is validated by `listWholesaleStaffBranches` and branch-specific `listWholesaleStaffRequests`; review decisions use `reviewWholesaleStaffRequest`. This does not perform POS checkout or collect money. Buyer cancellations use `cancelMyWholesaleRequest`.

GitHub Action `ws-checks.yml` runs syntax, focused unit tests, a static build and a production-route guard.
