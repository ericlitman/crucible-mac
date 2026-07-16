# Crucible.app

Crucible.app is a native, menu-bar-only macOS operator surface for the Crucible
fleet. The current foundation implements the fixture-backed CRUMAC-6 vertical
slice governed by `docs/product-specs/live-fleet-observability.product-spec.md`
revision 2 (partial AC-2, the asset portion of AC-8, and partial AC-10).

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

The normal Debug launch intentionally starts without fleet data. For local UI
inspection only, opt into the DEBUG-only, clearly labelled fixture harness:

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

Release builds exclude the fixture payload and never fall back to preview data.
There is no CLI invocation, refresh loop, direct host connection, networking,
or production data adapter in this slice. Future fleet I/O remains owned by the
versioned Crucible CLI contract described in
`docs/design/codexbar-alignment.md`.
