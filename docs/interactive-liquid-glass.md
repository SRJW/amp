# Floating controls: appearance and interaction

The November 22 light/dark reference videos guide the contact response of amp’s existing four-icon bar. Navigation centres, icon sizes, safe-area positioning and the player layout remain unchanged; labels remain accessibility-only.

## Current implementation

- `FloatingControlGlass` applies native iOS 26 interactive glass to the floating control surface. The persistent navigation row owns one material; its reserved layout slot paints no duplicate capsule. The existing Now Playing dissolve interpolates material opacity and icon colours.
- The mini player retains the earlier build-160 outline: a 32 pt continuous corner radius at its existing 96 pt height (`8f29145`). Artwork/text dimensions, metadata slides, cover dissolves, Play/Pause symbol replacement, scrubbing, swipe gestures and haptics remain.
- A subdued well marks selection at rest. During a section touch, a clear native glass lens above the glyphs follows the finger, previews the nearest section and changes proportions with filtered velocity. Release settles with a spring. Glyph frames never move or scale.
- Contact observation is passive: native Buttons own taps and holds; only a horizontal drag to a different section commits a destination. Vertical exits, resizing, backgrounding and player presentation clear the preview. Reduce Motion suppresses deformation; Reduce Transparency and older iOS versions use the background well.

## November 22 menu regression

The listener’s 17:09 recording shows a magnifying bubble over native menu rows and repeated failure to open Settings from Wi-Fi Transfer. Build 193’s native navigation test also failed at Menu → Settings.

`d120205` changes `NavigationGlassContact.swift`: contact tracking accepts only the first three section buttons, excludes the native Menu’s hit area, and requires the touched view to belong to the same view controller as the navigation probe. This prevents overlapping popover rows from entering the decorative lens through a rectangle-only check. The observer also yields when a native recognizer takes over.

`testNativeMenuSettingsWorksAfterWifiTransferWithoutSwitchingTabs` repeats Wi-Fi → Settings twice through the real native menu. The focused workflow includes this regression alongside light/dark button response, vertical cancellation, mini-player Play/Pause, all four navigation frame comparisons and section dragging. Simulator video is retained for visual inspection.

## Validation and delivery

The ten local Python tooling tests pass and `git diff --check` is clean. The earlier mini-player outline export 190 and focused verification 45066529591 passed device compilation, native interaction and rendering checks. Build 193 exported successfully but failed Menu → Settings; it is not a validated fix for this issue.

Build **194** (run **45077395553**, source `d120205`) passed device compilation, all three native UI cases and all **39** rendering checks. The saved simulator recording confirms both Wi-Fi → Settings transitions, dismissing the menu without leaving a magnifying lens over its text. The native system menu retains its own brief opening/closing material transition. Navigation geometry, section dragging, light/dark native button actions, vertical cancellation and mini-player Play/Pause all pass.

One release asset: `https://github.com/SRJW/amp/releases/download/v0.1.0-amp.194/amp.ipa`. Bundle identifiers remain `com.amp` and `com.amp.playerwidget`, build 194. The app and widget each contain one patch load, with preserved entitlements. SHA-256: `afc663415df1bff0d9e39f650a6deff74d5b92cbf30a2b6bab7b1f11e17771b6`. Re-sign this single IPA in FlareStore with the same Profile App-ID before installing as an update.

## Reverting appearance changes

Keep rollback scoped to visual implementation, preserving later features, test-fixture repairs and the listener’s data. To remove the later contact lens, revert its implementation commits in reverse order (`d120205`, `90149d4`, `819848e`, `be73c15`, `30c4d4d`), resolving any test-source context changes. Keep `8f29145` to retain the preferred mini-player outline. To remove the underlying native glass work as well, also revert `8f29145`, `1fcf316`, then `36ac8b6`. Build a newer IPA and install it as an update with the same FlareStore Profile App-ID; uninstalling is unnecessary.
