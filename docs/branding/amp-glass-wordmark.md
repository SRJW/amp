# amp glass wordmark: light and dark

Applied the listener-approved lowercase amp wordmark in pale optical glass and smoked graphite glass, with cyan/magenta corner refractions. Production masters fill the icon canvas; their outer presentation margins were removed during artwork preparation. The original generated files remain in the workspace.

- `AppIcon.appiconset` contains the default/light and luminosity-dark 1024×1024 RGB PNGs. iOS selects the Home Screen icon according to its icon appearance setting (Automatic/Light/Dark on supported iOS versions). The default resource also serves older systems.
- `AmpLogo.imageset` uses the same two images, so About and the welcome illustration follow the app’s effective SwiftUI color scheme.
- The welcome illustration uses the new logo within its existing 88 pt slot. Other onboarding pages and the player watermark remain as before.
- `Tools/verify_brand_assets.py` checks resolution, opacity, default/dark mappings, distinct appearances and identical masters for the app icon and in-app logo. The device workflow runs this before asset-catalog compilation.
- The `branding-only` validation scope builds, packages and verifies the actual device IPA. Unrelated playback simulator scenarios are excluded for this resource change.

Light SHA-256: `5500d76f860ef027b6563b2fcd593685b9dc0fbdaeb5b7888879cedafcf111cf`.
Dark SHA-256: `b79bd10443c7b8766a9a4dfb3c0a685fe347cce9cac69013e23701d1dbc2db86`.

Source: `1254f25`. Local and CI brand validation passed. Run **45895190532** (build **236**) passed device compilation, patch verification and publication. The downloaded IPA retains `com.amp` and `com.amp.playerwidget`, both build 236. Each bundle contains one patch load and retains its entitlements. The compiled default Home Screen icon was extracted, normalized from Apple CgBI PNG for inspection and visually checked.

Single release asset: `https://github.com/SRJW/amp/releases/download/v1.1.236/amp-v1.1.236.ipa`.
IPA SHA-256: `c7231b2b950e72acf365d060c94bf8fe445db864f724df5eb9a3f682375be20e`. The work is scoped for rollback through that commit, preserving the app identity and listener data.
