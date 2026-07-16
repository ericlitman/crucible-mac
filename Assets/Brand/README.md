# Crucible artwork

This directory preserves the canonical source artwork for Crucible.app.

| File | Purpose | Source size | SHA-256 |
| --- | --- | ---: | --- |
| `AppIcon.source.png` | Full-color application icon source | 1254 x 1254 | `f39a6cc48193ab4a52e58c9c2eef183c36158866119dfab334d534f58e92c5b0` |
| `MenuBarIcon.source.png` | Monochrome menu-bar mark source | 1254 x 1254 | `394c91c6363947726f5228aba7ef5038af88ce89a585ce2a06af16f1de96fdc3` |

These files are source art, not runtime-ready assets. Both source PNGs are
opaque. When the Xcode asset catalog is created:

- derive the required application-icon sizes from `AppIcon.source.png` and
  verify the icon boundary and transparent corners against the macOS icon mask;
- derive a transparent, monochrome template image from
  `MenuBarIcon.source.png`, render it at menu-bar scale, and mark the resulting
  `NSImage` as a template image so macOS controls light/dark appearance;
- keep generated asset-catalog derivatives separate from these source files.

Do not replace the source artwork as part of mechanical asset generation.
