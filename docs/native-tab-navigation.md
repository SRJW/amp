# Native navigation glass with amp's fixed geometry

## User request and baseline

Baseline `8b7bc96` restored amp's full-width, 60 pt navigation contour and the original icon positions shared with Now Playing. It also removed the system `UITabBar`, replacing its interaction with the previous manually moved lens. The listener requested the native effect back while keeping those corrected positions and the previous contour thickness. Now Playing must remain free of glass.

## Implementation

`NativeNavigationGlass.swift` hosts a real `UITabBarController` in a transparent full-window context for its material, selection tracking and press/drag response. It measures the resting geometry through public `UIView` / `UIControl` properties. The native controller keeps its normal vertical geometry. Only horizontal fitting and placement use a sublayer transform. Vertical scale stays exactly 1: the earlier vertical projection also enlarged UIKit’s contact deformation, producing the oversized lens reported by the listener. The original glyphs are rendered inside unchanged image canvases with inverse content scaling, at sufficient pixel density to preserve their physical size. The floating appearance ignored legacy item image insets in runtime measurements, so glyph pixels are offset inside their image canvases to align with amp’s shared fractions.

This adapter reads public geometry; it does not replace UIKit's internal views, change private child-view frames, call private selectors or use KVC. Geometry is recalibrated when the host size or window changes. Images are regenerated only for calibration, not for playback updates.

`AppBottomBar.swift` retains the single existing SwiftUI action/accessibility row and its 48 pt targets. UIKit's duplicate accessibility subtree is hidden. Direct navigation touches go to the native bar; the fourth action remains amp's existing SwiftUI Menu. UIKit cannot navigate to an empty fourth destination. The legacy window observer is disabled while native tracking is used.

The native surface and glyphs dissolve into the original bare player glyphs at the same coordinates. The native view becomes hidden and noninteractive at zero opacity. No glass contour is rendered in Now Playing. Earlier systems, disabled glass and Reduce Transparency keep the prior fallback. Mini-player styling, transport, waveform, artwork and shared positioning constants are unchanged.

## Runtime verification

Navigation validation captures a real simulator screenshot and a DEBUG-only geometry report before interactions. The report reads the actual alpha-pixel bounds of the images displayed by UIKit after layout and projects them into the shared row. It compares them with the original glyphs before projection, not only with accessibility target frames. CI requires four system controls and four glyphs, the 60 pt height, and centres within 0.5 pt of the original shared positions.

The existing focused interaction suite checks light/dark press actions, vertical cancellation, mini-player Play/Pause, cross-screen coordinates and sizes, selection dragging, and Menu → Wi-Fi → Settings. Rendering/blend checks run separately in the same pipeline.

The oversized version fitted a short, standalone UIKit surface vertically to the desired contour. That enlarged UIKit’s contact deformation as well. The corrected implementation uses a normal full-window tab controller, a native 62 pt material surface around the unchanged 60 pt target row, and vertical scale 1. Runtime capture on iPhone 11 confirms the full-window canvas, four controls and unchanged glyph dimensions. A single post-layout alpha-pixel correction compensates UIKit’s fractional template-image rounding without changing the native hit frames or deformation. Pixel scanning and image generation happen only on geometry calibration, never per animation frame.

Candidate export 250 uses production source `b761da8` (run `45940166645`). Its runtime report confirms a 414 × 896 host, four controls, native surface 372 × 62 before horizontal fitting, and vertical scale exactly 1. Actual icon centres differ from the shared targets by at most 0.21 pt. Alpha extents permit 1 pt total rounding: the original 2× reference and the inverse-fitted template have different fractional raster densities, allowing one physical pixel at each edge. Centre tolerance remains 0.5 pt. Revision `93bb19f` changes only this diagnostic tolerance, not production code or the existing interaction tests. The focused validation run is `45941164619`.

Local tooling checks: 10 passed. Device Release build and 40 rendering/blend tests passed in run `45940166645`. Its initial simulator preflight rejected alpha-extent rounding before interaction tests; the focused validation uses the same production code with the corrected raster-edge diagnostic. Runtime geometry preflight passed there, including all four centres and extents.

IPA: `amp-v1.1.250.ipa`, 12,758,363 bytes; SHA-256 `45144780b2ab35766874b432e64811f8867f45386d6164c41c89b20d96150464`. App `com.amp` and extension `com.amp.playerwidget` both contain build/version 250/1.1.250. Export verification found one patch load per binary and preserved app and extension entitlements. Automatic publication initially failed to create the draft (workflow token 403); creating the draft with the available authorized repository session and retrying only publication succeeded. Focused validation `45941164619` passed the runtime geometry preflight and all three existing navigation interaction tests: light/dark hold/tap/vertical cancellation and mini-player controls; identical Library/Now Playing coordinates, sizes and unique AX targets with selection dragging; and Menu → Wi-Fi → Settings without accidental tab switching. No interaction assertions were changed. The release and validation use identical production Swift code. The focused workflow completed successfully, including all 40 render/blend tests. The recorded dark-mode press sequence was visually reviewed: the native contact lens remains contained below the mini-player instead of the previous amplified vertical expansion.

The upstream baseline's full-player run `45917492548` already reported unrelated library title/reveal/query failures. This change does not alter those library functions. Superseded native prototypes were returned to draft releases. Navigation validation exports now remain drafts automatically until screenshot and interaction review is complete.

## Rollback

Revert this change on top of `8b7bc96` to return to the listener's aligned manual-glass bar, retaining all preceding unrelated work.
