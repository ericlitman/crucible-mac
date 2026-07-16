---
spec_format_version: "0.1"
title: "Crucible.app Safe Fleet Configuration"
artifact_type: "prd"
spec_revision: 1
author: "Eric Litman"
created_at: "2026-07-15T22:42:50-04:00"
updated_at: "2026-07-15T23:20:26-04:00"
linked_github_repo: "ericlitman/crucible-mac"
applies_to:
  - component: "Crucible.app"
  - component: "Crucible CLI configuration and deployment contracts"
---

## Problem

Crucible configuration can contain effective constraints that are difficult to see, such as an implicit one-lane-per-host cap or a 200K-token investigate limit. The operator cannot reliably inspect where an effective value came from or change fleet configuration through the same interface the agents use.

## Hypothesis

If Crucible.app makes effective configuration and provenance legible, validates proposed changes, and delegates every mutation and deployment to the CLI, the operator can prevent hidden constraints without creating a second control plane.

## Product Summary

Add a configuration surface for hosts, lanes, models, concurrency, time bounds, and token bounds. Crucible.app presents CLI-supplied effective values and provenance, previews and validates edits, and asks the CLI to own the git and asynchronous fleet deployment workflow.

## Scope

```productspec-scope
in:
  - Display configured and effective host, lane, model, concurrency, time-bound, and token-bound values with their provenance.
  - Edit supported configuration through versioned Crucible CLI planning and mutation contracts.
  - Validate and preview a configuration diff before the operator confirms it.
  - Trigger and monitor a CLI-owned git, merge, and asynchronous fleet deployment workflow.
out:
  - Do not connect directly to hosts or mutate host state from Crucible.app.
  - Do not implement git push, merge, or deployment logic inside the app.
  - Do not add direct control of queued or running jobs in this spec.
  - Do not allow the app to edit configuration fields the CLI cannot validate and apply.
cut:
  - Do not silently apply or deploy a configuration change without an explicit operator confirmation.
```

## Acceptance Criteria

```productspec-acceptance-criteria
- id: AC-1
  criterion: For every supported host, lane, model, concurrency, time-bound, and token-bound setting, the app shows the configured value, effective value, provenance or override chain, and the CLI response revision from which it was derived.
- id: AC-2
  criterion: When a configured value conflicts with the effective value, the app highlights the difference and identifies the default, override, or implicit constraint responsible when the CLI supplies that provenance.
- id: AC-3
  criterion: When the operator edits supported lane or model configuration, the app asks the CLI to validate the proposal and displays field-level validation errors without changing repository or fleet state.
- id: AC-4
  criterion: When the operator edits supported host configuration, the app asks the CLI to validate the proposal and displays field-level validation errors without changing repository or fleet state.
- id: AC-5
  criterion: Before deployment, the app displays the CLI-produced configuration diff and impact summary and requires explicit operator confirmation of the exact validated revision.
- id: AC-6
  criterion: When the operator confirms deployment, the app invokes one versioned CLI operation that owns the git push, merge, and asynchronous fleet deployment workflow, then reports durable operation identity and per-stage status without performing those operations itself.
- id: AC-7
  criterion: If validation, git, merge, or deployment fails or becomes stale, the app shows the failing stage and CLI-provided recovery guidance and does not report the proposed configuration as effective until a later CLI read confirms it.
```

## Success Metrics

```productspec-success-metrics
- id: SM-1
  metric: known effective configuration contradictions that remain undiscovered for more than one operator review
  target: "0"
  window: within 30 days of launch
- id: SM-2
  metric: Crucible.app configuration or deployment operations that bypass the Crucible CLI
  target: "0"
  window: from launch onward
```

## User Experience

The configuration surface should optimize for understanding before editing: effective values and provenance are primary, edits are deliberate, and deployment progress survives closing and reopening the popover. Verification evidence must include screenshots of read-only configuration, a validation failure, a pending diff, deployment progress, and a failed deployment state.

## Open Questions

- `RESOLVE-IN-PLAN:` Bind configuration read, validation, apply, and deployment behavior to current Crucible CLI commands or identify the smallest versioned CLI contracts that must be added.
- `RESOLVE-IN-PLAN:` Define the CLI's durable deployment operation identity and status model before building asynchronous progress UI.

## Related Artifacts

```productspec-related-artifacts
- type: linear_issue
  url: "https://linear.app/mobilyze-llc/issue/CRUMAC-4/add-safe-fleet-configuration-and-deployment"
  title: "CRUMAC-4 Add safe fleet configuration and deployment"
  section_id: acceptance_criteria
- type: product_spec
  product_spec_path: "docs/product-specs/live-fleet-observability.product-spec.md"
  product_spec_revision: 2
  relation: depends_on
  title: "Crucible.app Live Fleet Observability"
- type: code
  url: "../../STRATEGY.md"
  title: "Crucible.app Strategy"
  section_id: hypothesis
```
