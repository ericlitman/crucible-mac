---
spec_format_version: "0.1"
title: "Product Spec"
artifact_type: "prd"
spec_revision: 1
lifecycle_status: draft
author: "ProductSpec.io"
created_at: "2026-07-09T00:00:00Z"
updated_at: "2026-07-09T00:00:00Z"
---

## Problem

Crucible manages a complex development pipeline for a number of mission-critical applications, but currently there is no external visibility into its operations. As the product owner, I have no way of knowing the status of any given host or any jobs on that host, whether or not there are problems, what token burn looks like, how long jobs are taking, whether some problem may be spiraling out of control, or if things are all going well. 

## Hypothesis

With improved visibility, I will have a better handle on where the bottlenecks, cost sinks, and technical challenges exist in our development process and as a result I should be able to increase velocity and improve quality metrics. Moreover, with greater configurability of how our runner lanes work, I'll be able to more directly influence the shape of our crucible product in a world where model launches and new harness paradigms are launching on a weekly basis.

## Product Summary

This app should provide a Mac menu bar based front end styled after Codex Bar https://github.com/steipete/CodexBar that provides real-time visibility into the Crucible queue, configuration of Crucible's core capabilities, as well as aggregated statistics on Crucible's ongoing operations.

Acceptance criteria should be supported by screenshots.

## Scope

```productspec-scope
in:
  - Live visibility into the state of the crucible queue.This should show all states of the lifecycle of a job Together with visibility into the details of each job.
  - Aggregated and per host statistics on the ongoing operations of the pipeline.
  - Configuration of hosts, lanes, and other core Crucible configuration parameters.
out:
  - No direct control over jobs on a host.
cut:
  - No Windows support.
```

## Acceptance Criteria

```productspec-acceptance-criteria
- id: AC-1
  criterion: The app is capable of displaying the live status of the full crucible fleet.
- id: AC-2
  criterion: The configuration of our lanes and models can be displayed in a logical, well-designed layout and edited.
- id: AC-3
  criterion: The configuration of our hosts can be displayed in a logical, well-designed layout and edited.
- id: AC-4
  criterion: On our configuration page there's a Deploy button that pushes and merges the changes to git and deploys the changes across the fleet asynchronously.
- id: AC-5
  criterion: The app displays l24h/l7d/l30d stats aggregated and drill-down per host: tokens (input/output/cached) aggregate and per task type, time per task type, errors and failures.
- id: AC-6
  criterion: App updates occur via Sparkle.
```

## Success Metrics

```productspec-success-metrics
- id: SM-1
  metric: failed jobs waiting for resolution
  target: "0"
  window: within 7 days of launch
```
