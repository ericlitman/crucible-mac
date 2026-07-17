# Crucible.app

Crucible.app is a native, menu-bar-only macOS operator surface for the Crucible
fleet. CRUMAC-7 connects the CRUMAC-6 interface to the versioned, read-only
live-fleet contract governed by
`docs/product-specs/live-fleet-observability.product-spec.md` revision 4.

The production data path is deliberately narrow:

```text
/Users/ericlitman/.local/bin/operator-supervisor
  live-fleet --contract-version 1 --format json
    -> strict v1 parser -> refresh coordinator -> AppState -> SwiftUI
```

The app does not use a shell, search `PATH`, connect to a host, read controller
artifacts, or reconstruct fleet semantics. Accepted fresh snapshots replace
state; partial coverage remains explicit and unavailable values stay unknown.
Stale, incompatible, and failed responses are labelled and retain the best
truthful prior snapshot without inventing token usage or bounds.

## Development

Open `Crucible/Crucible.xcodeproj` and use the shared `Crucible` scheme, or run:

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
xcodebuild test \
  -project Crucible/Crucible.xcodeproj \
  -scheme Crucible \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

The normal Debug and Release launches invoke the installed CLI immediately,
again when the menu or dashboard appears, every 60 seconds while either surface
is visible, and no more frequently than every 300 seconds in the background.
The 60-second choice follows the CRUMAC-5 measured fresh-read sample (3.05667s)
and should move to 120 seconds if the release load sample exceeds 10 seconds.

For local UI inspection only, opt into the DEBUG-only, clearly labelled fixture
harness:

```sh
CRUCIBLE_PREVIEW_DATA=1 ./script/build_and_run.sh
```

### Visual proof windows

DEBUG builds can present the production menu or dashboard view in a standard
window for screenshot verification, using the same clearly labelled fixtures:

```sh
open -n .build/DerivedData/Build/Products/Debug/Crucible.app \
  --args --preview-surface=menu --preview-appearance=light
open -n .build/DerivedData/Build/Products/Debug/Crucible.app \
  --args --preview-surface=dashboard --preview-appearance=dark
```

Both surfaces support `light` or `dark`. The proof launcher, arguments, and
fixture payload are DEBUG-only and absent from Release builds.
Append `--preview-stale`, `--preview-incompatible`, or `--preview-error` to a
dashboard proof launch to capture the corresponding retained-state or error
presentation without changing the installed CLI.

Release builds exclude the preview payload and never fall back to fake data.
The five CRUMAC-5 contract fixtures remain test-target-only. Fleet I/O remains
owned by the versioned Crucible CLI contract described in
`docs/design/codexbar-alignment.md`.
