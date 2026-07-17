---
spec_format_version: "0.1"
title: "Crucible.app Operational History and Trends"
artifact_type: "prd"
spec_revision: 1
author: "Eric Litman"
created_at: "2026-07-15T22:42:50-04:00"
updated_at: "2026-07-16T23:02:50-04:00"
linked_github_repo: "ericlitman/crucible-mac"
applies_to:
  - component: "Crucible.app"
  - component: "Crucible CLI operational history contract"
---

## Problem

Crucible jobs can stall, restart, recover from failures, or consume excessive time and tokens without leaving an operator-visible explanation once they eventually succeed. Without comparable recent history, systemic bottlenecks and costly workarounds must be rediscovered manually.

## Hypothesis

If every meaningful attempt, transition, recovery, duration, and token cost can be inspected and compared across useful time windows, the fleet operator can find recurring causes of token burn and processing delay and reduce both over time.

## Product Summary

Add recent operational reporting to Crucible.app using versioned historical data supplied by the Crucible CLI. The operator can compare the last 24 hours, 7 days, and 30 days across the fleet and drill down by host, task type, job, lane, and pipeline stage.

## Scope

```productspec-scope
in:
  - Report tokens, elapsed time, errors, failures, retries, restarts, recoveries, stalls, and boundary exceedances for at least the most recent 30 days.
  - Provide fleet-wide aggregates and drill-down by host, task type, job, lane, and pipeline stage.
  - Attribute recovered and failed attempts to the final issue and PR so eventual success does not hide their cost.
  - Add missing historical intelligence to a versioned Crucible CLI contract before displaying it in the app.
out:
  - Do not collect telemetry directly from fleet hosts in Crucible.app.
  - Do not make the app's local cache the authoritative operational record.
  - Do not provide predictive recommendations or automated remediation in this version.
cut:
  - Do not add reporting windows longer than 30 days until retention cost and usefulness are measured.
```

## Acceptance Criteria

```productspec-acceptance-criteria
- id: AC-1
  criterion: The Crucible CLI exposes a versioned, machine-readable history contract containing stable event identity, timestamps, host, job, lane, stage, state transitions, retries, restarts, recoveries, errors, time bounds, token bounds, and input, output, and cached token usage when those values exist.
- id: AC-2
  criterion: When the operator selects 24 hours, 7 days, or 30 days, the app shows fleet-wide token totals, elapsed time by task or stage type, error and failure counts, retry and restart counts, recovery counts, stall counts, and boundary exceedances for exactly that window.
- id: AC-3
  criterion: From any aggregate, the operator can drill down by host and task type to the contributing jobs, lanes, stages, and events without losing the selected time window.
- id: AC-4
  criterion: For each issue and successful PR, token burn includes all attributable failed, restarted, retried, and recovered attempts rather than only the final successful attempt.
- id: AC-5
  criterion: The app reports issue-to-PR processing time from queue admission through the first successful PR gate and makes queue wait, active work, retries, and recovery time distinguishable when the CLI supplies those intervals.
- id: AC-6
  criterion: When historical data is incomplete, duplicated, outside retention, or produced by an unsupported schema revision, the app identifies the affected interval and does not silently include unreliable values in aggregates.
```

## Success Metrics

```productspec-success-metrics
- id: SM-1
  metric: tokens consumed per successful issue PR
  target: "< 30-day pre-launch baseline"
  window: within 60 days of launch
- id: SM-2
  metric: average issue-to-PR processing time
  target: "< 30-day pre-launch baseline"
  window: within 60 days of launch
```

## User Experience

Charts and summaries must remain useful without requiring the operator to understand the underlying event schema. Every aggregate must expose its time window, population, unit, and route to the contributing records, and verification evidence must include screenshots for fleet and host drill-down.

## Open Questions

- `RESOLVE-IN-PLAN:` Bind the required history fields to existing Crucible CLI artifacts and identify which events or usage fields must be added at the CLI layer.
- `RESOLVE-IN-PLAN:` Confirm the authoritative definition of queue admission and successful PR gate against current pipeline events before implementing SM-2.

## Related Artifacts

```productspec-related-artifacts
- type: linear_issue
  url: "https://linear.app/mobilyze-llc/issue/CRUMAC-3/add-operational-history-and-trend-reporting"
  title: "CRUMAC-3 Add operational history and trend reporting"
  section_id: acceptance_criteria
- type: product_spec
  product_spec_path: "docs/product-specs/live-fleet-observability.product-spec.md"
  product_spec_revision: 5
  relation: depends_on
  title: "Crucible.app Live Fleet Observability"
- type: code
  url: "../../STRATEGY.md"
  title: "Crucible.app Strategy"
  section_id: hypothesis
```
