# Pure Pets Project Brain Satellite — Admin iOS

This repository is a core Pure Pets platform repository. These instructions make the Project Brain active when Admin is opened independently.

## Brain Boot Contract

1. For cross-repository work, locate the sibling `PurePetsProjects` checkout when available and read the umbrella bootloader, governance, affected feature-map entry and security map when applicable.
2. If unavailable, use current Admin source as local truth and do not invent backend/client contracts.
3. `pure-pets-infra` is authoritative for Firebase schema, security, Cloud Functions and backend lifecycle.
4. Do not recursively inspect every Pure Pets repository by default.

Machine pointer: `project-brain.json`.

## Local Authority

Admin is the internal staff iOS surface. Preserve its current UIKit/MVC/singleton architecture, App Check/Auth bootstrap, `staff_users` RBAC and audited server mutation boundaries.

## Invariants

- Sensitive writes must preserve backend permission and audit contracts.
- Client permission visibility does not replace server authorization.
- Reuse existing managers/components and localization patterns before introducing competing systems.
- Preserve Arabic RTL and English LTR behavior.
- Do not rename Firebase collections or silently bypass callable workflows.
- QIB/payment, delivery-company, branch/agent, service/vet/pharmacy and notification operations remain domain-sensitive.

## Security & Approval

Never ingest `.env`, Firebase/service credentials, API keys, private keys, signing material or auth tokens into memory. Canonical/historical memory never grants current deployment, production or destructive approval.

## Execution Boundary

The umbrella execution policy governs agent-run iOS verification when repo documentation contains build examples. Build documentation is not execution authorization.

## Freshness

When the umbrella brain is available, compare this repository HEAD with the recorded Admin snapshot and inspect only task-relevant changed ranges on mismatch.
