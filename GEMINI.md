# GEMINI.md — Pure Pets Project Brain Satellite: Staff Admin iOS

This repository is the internal staff iOS application for Pure Pets (`pure-pets-49199`).

## Brain Boot Contract
1. For cross-repository context, locate sibling `PurePetsProjects` and read `AGENTS.md` and `docs/agent/INDEX.md`.
2. `pure-pets-infra` is authoritative for backend schema, rules, Cloud Functions, and lifecycle.
3. Machine pointer: `project-brain.json`.

## Core Invariants
- UIKit/MVC/singleton architecture with `staff_users` RBAC.
- Preserved callable mutation boundaries and audit logs.
- Physical connected device only execution policy (iPhone 13 Pro Max).
- Arabic primary (RTL) localization.
- Never ingest secrets into memory.
