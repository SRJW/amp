# Interactive Liquid Glass for the floating controls

Reference: the supplied `video_2026-11-21_07-06-54.mp4`. Scope: the existing floating mini player and four-icon navigation. Keep all navigation metrics, icon centres, hit-target sizes, mini-player height and existing functions.

## Changes

- `FloatingControlGlass` applies iOS 26's native `.regular.interactive()` glass to the actual control container, in a real capsule. Previously the material was a detached non-hit-testable background. The system now owns contact refraction, highlights and the elastic material response.
- The navigation surface now belongs to the persistent navigation row. Its reserved slot in `AppBottomBar` no longer paints a second capsule. A symmetrical visual outset gives the material its original 60 pt height around the unchanged 48 pt row, without changing layout measurements.
- The current continuous player-transition progress is preserved. During the dissolve, only the material fades; the existing interpolation of icon colours and the listener's optional player capsule remain intact.
- Dragging stretches only the selection lens, about its own centre. Icon geometry is untouched. The lens returns with a spring, and Reduce Motion suppresses that deformation.
- A press changes control ink intensity slightly, without scaling or translating the icon. Play/Pause uses the native SF Symbol replacement transition. Existing metadata slides, cover dissolves, scrubbing, swipe gestures and swipe haptics remain.
- The mini player's glass ends are fully rounded. No final clip cuts off the interactive glass's edge highlights.

The new implementation was rebased onto `4cd2795` before publication. It preserves the newer menu, localisation, artwork palettes, player background preferences, widget redesign and appearance propagation. On pre-iOS 26 systems the existing material fallback remains; the transparency preference remains available.

## Validation

The ten Python tooling checks pass. The existing native navigation test compares all four buttons' screen coordinates and sizes between Library and Now Playing. Mini-player tests exercise opening, scrubbing and track swipes. A stale test of the removed drawer was adapted to the actual native tool-menu route; the numeric-first index test now drags to Z instead of Y. Search history is verified before force-terminating, and the keyboard check accounts for iOS's predictive row rather than treating it as app navigation.

The exported IPA passes device compilation and FlareStore patch verification for both bundles, with one injected load per executable and preserved entitlements. Native unit tests in run 45064952522 have passed; full UI and rendering results are still being collected. In focused run 45064350040, all sixteen individual frame comparisons passed (centre X/Y and width/height for all four buttons), as did return-to-Library alignment, menu/settings navigation, Search and the selection drag. The overall case failed only its initial 10-second polling predicate: eight separate AX resolutions exceeded the entire deadline on the busy runner. Revision `9862a34` now reads one consistent AX tree snapshot, retaining the same 0.5 pt tolerance and all sixteen concrete assertions. Its focused rerun is 45066529591 and is pending. The earlier renderer fixture needed its own AppRouter after the router ownership change in the baseline, and the source-navigation test no longer models the removed drawer as an open settings tool.

Final export: `v0.1.0-amp.189`, app code equivalent to 188 (subsequent changes only repair test fixtures). SHA-256: `1373c8541ba4bd1cf57ec557ff0b751dbf89f68d7403272779a516cbc300feb7`. One release IPA, `amp.ipa`.

## Reverting only this appearance change

The visual implementation is isolated in `36ac8b6` and `1fcf316`, on top of baseline `4cd2795`. Revert the newer commit first, then the older one, and build a new version. Keep the later source-navigation test fix (`2a508d9`). This restores the previous floating surfaces and press styling without reverting the other recent features, changing the app identity or migrating/deleting user data. Install the replacement IPA as an update using the same FlareStore Profile App-ID; uninstalling is unnecessary.
