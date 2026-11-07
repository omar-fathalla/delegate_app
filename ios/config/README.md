# iOS Firebase config (dev / prod)

- `prod/GoogleService-Info.plist` — production Firebase (`practice-firebase-72df1`), committed.
- `dev/GoogleService-Info.plist` — tashil-dev app (`com.tashil.delegate.dev`). **Not committed**
  (gitignored). Copy from Firebase Console for tashil-dev or from the project store
  `dev-GoogleService-Info_*.plist` into `ios/config/dev/` before building the **dev** flavor.

Build phases (`scripts/firebase_config.sh`) copy the correct plist into the app and fail closed
if this file is missing or does not match `APP_ENV` and `PRODUCT_BUNDLE_IDENTIFIER`.

## Derived plugin registrant (do not mutate Flutter output)

Flutter generates `Runner/GeneratedPluginRegistrant.m` during the Xcode “Run Script” phase that
invokes `xcode_backend.sh`. That file is **never edited in place**.

A second Run Script phase — **`[Tashil] Prepare derived plugin registrant`** — runs **after** Flutter
codegen and **before** Compile Sources. It writes **only** under Xcode’s per-configuration
**`DERIVED_FILE_DIR`** (so parallel dev/prod builds do not race on one shared path):

`$(DERIVED_FILE_DIR)/tashil_registrant/GeneratedPluginRegistrant.m` (ephemeral; not committed)

- **Dev** (`Debug-dev`, `Profile-dev`, `Release-dev`): copies from the generated file and strips
  native Crashlytics plugin registration so dev never initializes Crashlytics.
- **Prod** (all other configurations): copies the generated file verbatim and **fails the build**
  if Crashlytics registration lines are missing in the derived file (fail closed).

The Runner target’s **Compile Sources** entry is the **derived** `.m` file (via
`DERIVED_FILE_DIR` in the project), not `Runner/GeneratedPluginRegistrant.m`. The header
`GeneratedPluginRegistrant.h` stays in
`Runner/` (unchanged; still the Flutter-generated header next to the generated `.m`).

Switching schemes in Xcode without re-running Flutter therefore cannot ship prod with a stripped
registrant: the next prod compile copies from the shared generated file again.

Manual regression (macOS + Xcode): `scripts/test_derived_registrant_switching.sh` from `ios/`.
Quick path isolation (no full compile): `scripts/test_derived_registrant_path_isolation.sh`.
The script runs `flutter build ios --config-only` for **dev** and **prod** (simulator, no codesign),
then `pod install` after each, so plain `xcodebuild` resolves the Flutter module like a normal
Flutter+iOS workspace. It then runs **Debug-dev → Debug-prod → Debug-dev** without calling Flutter
again between those builds (only `DART_DEFINES` is overridden per configuration to match `ENV`).
