# Security contract

## Trust classes

### Trusted

- Firebase ID-token claims returned by Firebase Auth.
- Protected server/admin documents when enforced by Security Rules.
- Backend responses authenticated and authorized by trusted infrastructure.

### Untrusted

- User profile documents.
- Client-provided dictionaries.
- disk cache;
- UI state;
- Objective-C bridge properties;
- feature or permission values supplied by application callers.

Profile data can never become token claims.

## Client authorization

`PPUserAccess` is fail closed:

- unknown or cached trust denies;
- expired token denies;
- disabled account denies;
- blocked account denies;
- non-active account denies;
- missing capability rule denies;
- feature disabled denies;
- explicit restriction denies;
- explicit permission false denies.

The public module cannot construct verified access because the initializer is package-scoped.

## Cache contract

The cache may improve loading continuity, but never grants authorization. Every decoded snapshot is converted to cached trust, clears admin/super-admin state, clears permissions, and converts non-restriction rules into denied rules.

## Write contract

`PPUserProfilePatch` is the only profile-write command. Its schema contains no authorization fields.

The Firebase store checks that the patch user ID equals `Auth.currentUser.uid` before writing. Administrative user updates require a different, privileged repository.

## Session lifecycle

The auth adapter observes ID-token changes. This catches sign-in, sign-out, user changes, and refreshed claims. Repository generation and token revision checks prevent stale requests from publishing after account changes.

## Server requirements

Client checks are not a security boundary. Firestore Security Rules and backend authorization must:

- derive privileged access from authenticated claims or protected server data;
- reject client writes to role, admin state, claims, features, restrictions, subscription and permission documents;
- restrict profile updates to the authenticated user's own document and an allowlist of fields;
- validate field types and lengths;
- deny protected operations for blocked or disabled accounts;
- validate ownership and tenant boundaries for every resource;
- use App Check as abuse resistance, not as authorization.

## Logging

Do not log Firebase UID, email, phone, token values, claim dictionaries, or permission documents as public production log fields. Use stable internal failure codes and privacy-safe diagnostics.
