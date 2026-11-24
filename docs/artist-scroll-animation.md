# Artist portrait scroll animation

Reference: `ScreenRecording_11-24-2026 16-58-04_1-2.mp4` (11.4 seconds).

## Observed behavior

- Pull-down at approximately 1.5–2.5 and 4.5 seconds stretches the portrait proportionally, keeping it against the top of the screen. The artist name and action row travel with the content.
- Upward scrolling at approximately 6–6.5 and 8–8.5 seconds moves the portrait more slowly than the foreground and progressively softens it as it departs.
- Release uses the scroll view’s natural deceleration/rubber-band return. The bottom controls remain independent of the portrait animation.

## Implementation

Based on upstream `014986d`, preserving the current editorial artist layout, Info/Play/Favorite actions, discography sections, lyrics changes and navigation.

`ArtistScrollPortrait.swift` reads local geometry in the artist scroll view’s named coordinate space. Its `ArtistPortraitCanvas` applies the same proportional stretch and parallax transform to both the sharp photo and its existing lower mist. The photo stays attached to the viewport top during overscroll. A smoothstep blur ramps with upward departure; no extra implicit animation trails the finger. No frame-by-frame library or page state is updated, and image requests retain the same cached 1200-pixel size during scrolling. Missing-photo monograms are not blurred. Reduce Motion disables the added stretch, parallax and departure blur.

`DetailPages.swift` replaces only the static artist portrait layers and names that scroll view’s coordinate space. Metadata, buttons, sections, navigation metrics, album pages and Now Playing remain untouched.

## Verification

The UI probe uses local files and a generated textured portrait; no external artist lookup is required. The native test exercises pull/release, scrolling back, stable bottom navigation and the Info sheet. A renderer regression checks top coverage during pulling and departure, portrait extension and exact return to the original frame. CI records the real simulator interaction.

Local Python tooling checks: 10 passed. Build 219, source `60df494`, passed device compilation, patch verification and all **40 rendering tests**, including portrait top coverage, extension and return. Native interaction verification in run 45497820247 was interrupted by a real update prompt appearing above the artist controls. The recording and AX failure hierarchy both identify that modal (Download update / Skip for now), rather than a portrait assertion failure.

`129086c` suppresses automatic release checks only for DEBUG interaction-probe launches. It leaves Release builds and normal update behavior unchanged. Run **45501970021** repeats verification using the same production portrait implementation. Both native UI cases **passed** (159 seconds total): artist pull/release, scrolling back, fixed navigation and Info/Done interaction; and Library/Now Playing coordinate parity, menu/settings and section dragging. The simulator recording was inspected across pull, upward departure, return and the Info sheet.

All **31 PlayerRenderingTests passed**, including the artist regression. The broader run is **not green**: two existing CarouselMotionTests failed six assertions about deadline cleanup (`testBusyMainActorDoesNotRestartAnimationCleanupTimers` and `testCleanupDeadlineDoesNotDependOnAVisibleSwiftUIRenderer`). Neither that implementation nor those tests changed in this work. Those two tests passed in build 219’s earlier 40-test rendering run. This documents the inconsistent broader result rather than treating all checks as passing; no carousel implementation was modified.

Release asset: `https://github.com/SRJW/amp/releases/download/v1.1.219/amp-v1.1.219.ipa`. App/widget identifiers: `com.amp` and `com.amp.playerwidget`; build 219. The single patched IPA preserves entitlements and injects each executable once. SHA-256: `447ada7c20c38927a2566f4e00207c8bb1c06d5a5a7ceecf814316b32ca00deb`. Artist-specific interaction and rendering verification is complete; the broader carousel timing failures are recorded above.

## Scoped rollback

`git revert 60df494` restores the prior static artist portrait and removes its test/probe/workflow additions, preserving the preceding upstream changes. Distribute a newer IPA as an update with the same signing identity; do not uninstall the app.
