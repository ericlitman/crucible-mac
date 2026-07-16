---
spec_format_version: "0.1"
title: "Crucible.app Live Fleet Observability"
artifact_type: "prd"
spec_revision: 1
author: "Eric Litman"
created_at: "2026-07-15T22:42:50-04:00"
updated_at: "2026-07-15T22:42:50-04:00"
linked_github_repo: "ericlitman/crucible-mac"
applies_to:
  - component: "Crucible.app"
  - component: "Crucible CLI live fleet status contract"
---

## Problem

The Crucible fleet has no reliable front door for understanding the current queue, hosts, jobs, or lanes. Stalls, repeated recoveries, accidental concurrency limits, and runaway time or token budgets can remain invisible until they have already wasted time, tokens, and code quality.

## Hypothesis

If the fleet operator can inspect the exact current state on demand and receive timely, trustworthy alerts from the same CLI intelligence used by agents, operational problems will be noticed and corrected before their costs compound.

## Product Summary

Build a native Swift macOS menu bar app that presents live fleet state from a versioned Crucible CLI contract. The app provides a compact overview, contextual drill-down, background and foreground refresh behavior, and configurable notifications while treating the CLI as the sole operational front door.

## Scope

```productspec-scope
in:
  - Display the current queue, host, job, lane, and pipeline-stage state supplied by a versioned Crucible CLI contract.
  - Add missing fleet intelligence to the Crucible CLI before consuming it in the app.
  - Notify for important operational problems and optionally for all major state changes.
  - Ship a native macOS menu bar experience using the approved Crucible artwork and an update path through Sparkle.
out:
  - Do not connect Crucible.app directly to any host in the fleet.
  - Do not mutate queued or running jobs in this version; future queue actions must be introduced through the CLI.
  - Do not edit fleet configuration in this spec.
  - Do not provide historical reporting beyond the context required to explain the current state.
cut:
  - Do not support Windows.
  - Do not rebuild or copy CodexBar; use it only as a directional interaction and design reference.
```

## Acceptance Criteria

```productspec-acceptance-criteria
- id: AC-1
  criterion: Given any live fleet refresh, Crucible.app obtains fleet data only by invoking a versioned, machine-readable Crucible CLI contract and initiates no direct connection to a fleet host.
- id: AC-2
  criterion: When the operator opens the menu bar surface, it shows every known host and the current queue, with clear counts and status for active, waiting, completed, failed, blocked, and stalled work.
- id: AC-3
  criterion: When the operator selects a host, job, or lane, the app shows the available lifecycle state, current stage, elapsed time, last meaningful progress, retry or restart history, recoverable failures, token use, applicable time and token bounds, and the source timestamp from the CLI response.
- id: AC-4
  criterion: While automatic polling is enabled and the app is in the background, it schedules refresh at a five-minute cadence subject to macOS scheduling and never polls more frequently, while the selected foreground cadence is measurably faster and is justified by a documented CLI load test before release.
- id: AC-5
  criterion: On the first successful refresh that observes a task with no meaningful progress for at least ten minutes, a lane beyond its time bound, or a lane beyond a soft or hard token bound, the app sends an actionable macOS notification identifying the affected host, job, lane, and condition.
- id: AC-6
  criterion: The operator can choose between notifications for all major state changes and notifications for important conditions only, and the app does not repeat a notification for the same unchanged transition or boundary condition.
- id: AC-7
  criterion: When the CLI is unavailable, incompatible, or returns stale or incomplete data, the app preserves the last known state, labels it as stale, shows the last successful refresh time, and exposes a useful error without presenting the state as live.
- id: AC-8
  criterion: The approved app artwork is represented in the application icon asset catalog, and a derived transparent template image remains legible as the menu bar icon in both light and dark appearances.
- id: AC-9
  criterion: A signed release of Crucible.app can discover and install an application update through Sparkle.
```

## Success Metrics

```productspec-success-metrics
- id: SM-1
  metric: active stalled or failed jobs waiting for operator awareness or resolution
  target: "0"
  window: within 7 days of launch and at each weekly review thereafter
```

## User Experience

The default surface should be glanceable from the menu bar, with progressive disclosure rather than a dashboard compressed into a popover. Status must not rely on color alone, and verification evidence for each user-visible acceptance criterion must include light- and dark-appearance screenshots.

## Open Questions

- `RESOLVE-IN-PLAN:` Measure CLI and fleet pressure and select the foreground polling cadence that is faster than five minutes without creating material operational load.
- `RESOLVE-IN-PLAN:` Bind each required fleet field and state transition to the current Crucible CLI schema, adding missing intelligence to the CLI rather than inventing an app-only source.

## Related Artifacts

```productspec-related-artifacts
- type: linear_issue
  url: "https://linear.app/mobilyze-llc/issue/CRUMAC-2/build-live-fleet-observability-and-alerts"
  title: "CRUMAC-2 Build live fleet observability and alerts"
  section_id: acceptance_criteria
- type: code
  url: "../../STRATEGY.md"
  title: "Crucible.app Strategy"
  section_id: hypothesis
- type: code
  url: "../../Assets/Brand/README.md"
  title: "Crucible source artwork"
  section_id: user_experience
- type: other
  url: "https://github.com/steipete/CodexBar"
  title: "CodexBar directional reference"
  section_id: user_experience
```
