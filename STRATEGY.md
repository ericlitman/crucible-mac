---
name: Crucible.app
last_updated: 2026-07-15
---

# Crucible.app Strategy

## Target problem

We have no reliable front-door visibility into what is happening across the Crucible fleet, allowing stalled jobs, repeated recoveries, accidental concurrency limits, and runaway token budgets to remain hidden. These problems waste time and tokens and lower code quality even when the pipeline eventually succeeds.

## Our approach

The Crucible CLI is the sole operational front door and owner of versioned, machine-readable contracts for observing or changing the fleet. Crucible.app is a native macOS oversight client that consumes those contracts for live visibility, history, and alerts; missing intelligence and future mutations are added to the CLI first, never implemented through direct host access.

## Who it's for

**Primary:** Crucible fleet operator - They're hiring Crucible.app to understand the exact state of every host, job, and lane on demand, learn about problems early, and identify positive and negative operational trends.

## Key metrics

- **Token burn per PR** - Total agent tokens across all stages, retries, and recoveries for each successful PR, measured from CLI usage history.
- **Issue-to-PR processing time** - Average elapsed pipeline time from queue admission to the first successful PR gate, measured from CLI event history.
- **Stalled job count** - Number of active jobs without meaningful progress for at least ten minutes; the target is zero.

## Tracks

### Queue visibility and management

Make current queue, host, job, and lane state legible on demand, with trustworthy state-change and boundary alerts; later queue mutations remain CLI-backed actions.

_Why it serves the approach:_ It shortens the time between a problem beginning and corrective action, before stalls, retries, serialization, or budget overruns compound.

### Historical reporting

Preserve and explain recent operational history, including recoveries and repeated work that would otherwise disappear behind an eventual success.

_Why it serves the approach:_ It makes token burn and processing-time trends attributable, so recurring systemic problems can be fixed rather than rediscovered.

### Configuration

Expose effective pipeline configuration and its provenance, and route any future configuration changes through the CLI.

_Why it serves the approach:_ It makes hidden lane, time, and token constraints visible while maintaining one operational contract for both agents and the app.

## Not working on

- Direct connections from Crucible.app to hosts in the fleet.
- A second app-specific pipeline API or duplicate pipeline business logic.
- Replacing the CLI as the primary interface used by agents.
