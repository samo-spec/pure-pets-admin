# CLAUDE.md — Pure Pets Project Brain Satellite: Staff Admin iOS

This repository is the internal staff iOS application for Pure Pets (`pure-pets-49199`).

## Brain Boot Contract
1. For cross-repository context, locate sibling `PurePetsProjects` and read `AGENTS.md` and `docs/agent/INDEX.md`.
2. `pure-pets-infra` is authoritative for backend schema, rules, Cloud Functions, and lifecycle.
3. Machine pointer: `project-brain.json`.

## Admin Architecture
- Objective-C primary with UIKit/MVC/singleton architecture.
- App Check + Firebase Auth + `staff_users` RBAC.
- Sensitive writes route through audited Cloud Functions. Client UI permission checks do not replace server authorization.
- Execution policy: Connected physical device (iPhone 13 Pro Max) only. Never simulator.
- Arabic primary (RTL) / English secondary (LTR).
