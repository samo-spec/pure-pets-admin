# Migration plan from `UserModel`

This is a strangler migration. Keep the application shipping while moving one responsibility at a time. Do not maintain two authoritative user systems.

## Data preflight before enabling capability gates

The new policy intentionally denies missing state. Before routing protected UI through it, backfill active production users with explicit canonical values:

- `accountStatus: "active"`;
- the nested `features` keys used by the app;
- the nested `restrictions` keys with explicit `false` where unrestricted;
- the canonical permission collection, including explicit denials;
- normalized string role claims for privileged users.

Run this as a backend/admin migration, not as a client fallback. Verify counts and sample accounts before rollout.

## Phase 0 — Establish the new source of truth

- Add `PurePetsUserKit` and application adapters.
- Construct one shared `PPUserSession`.
- Start the session at the authenticated app root.
- Add smoke logging for state transitions without logging public UID values.

Exit criterion: sign-in, sign-out, profile loading, permission loading, and account switching are visible through the session.

## Phase 1 — Replace authorization reads

Replace direct reads such as:

```text
user.isAdmin
user.canUseChatFeature
user.chatBlocked
user.canPostPetAdsFeature
user.permissions[...] 
```

with:

```swift
session.decision(for: capability)
```

or the Objective-C bridge equivalent.

Migrate the most sensitive flows first:

1. admin and management entry points;
2. posting and selling;
3. chat;
4. purchases and withdrawals;
5. partner/provider/vet tools.

Exit criterion: no protected UI flow derives its own authorization rule.

## Phase 2 — Replace profile reads

Move screens from `UserModel` profile fields to `PPUser`:

- identity and display name;
- avatar and cover images;
- contact information;
- presence;
- reputation.

Keep formatting and localization in views/formatters, not in the model.

Exit criterion: the old model is no longer required for rendering current-user profile data.

## Phase 3 — Replace profile writes

Remove direct Firestore profile updates and model-side save methods. Route all user-edit screens through `PPUserProfilePatch`.

Exit criterion: there is one allowlisted profile-write path.

## Phase 4 — Remove old infrastructure

Delete or deprecate from `UserModel`:

- Firebase fetches;
- permission listeners;
- permission writes;
- cache and secure coding;
- role/claim mapping;
- feature/restriction merge logic;
- notification ownership.

Keep only a temporary read adapter when an unmigrated screen still requires it.

Exit criterion: `UserModel` is no longer a repository, policy engine, or cache.

## Phase 5 — Remove the compatibility model

After call-site search confirms no consumers remain:

- delete mutable authorization properties;
- delete camel-case aliases and duplicated field spellings;
- delete the legacy cache;
- delete `UserModel.h/.m` or reduce it to a clearly named DTO used only for an external contract.

## Search-based completion checks

Search the repository for:

```text
UserModel
isAdmin =
isSuperAdmin =
canUseChatFeature
chatBlocked
canPostPetAdsFeature
permissions[
addSnapshotListener
getIDTokenResult
```

Every remaining occurrence must have an explicit justification.

## Rollback policy

Rollback is performed at the composition root by switching consumers back to the old adapter. Do not write new access state into the old model, because that creates two mutable sources of truth and makes rollback nondeterministic.
