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

**SPM link strip (native Crashlytics off):** The **dev** scheme runs `strip_dev_crashlytics_spm_package.sh` as a **Build pre-action** (before Xcode resolves SwiftPM). Immediately **before and after** Flutter's `xcode_backend.sh build`
(same Run Script phase, then again in the derived-registrant prep, and on dev `pod install`),
`strip_dev_crashlytics_spm_package.sh` removes `firebase_crashlytics` from
`FlutterGeneratedPluginSwiftPackage/Package.swift` and drops the `.packages/firebase_crashlytics`
symlink on dev only — **before** Xcode resolves SPM. Do not add a separate SPM-only build phase.
Prod configurations fail closed if `firebase_crashlytics` is absent from that manifest.
`pod install` runs `tashil_strip_crashlytics_from_dev_pod_support.sh` to drop Crashlytics from **`*-dev`** Pods xcconfigs / framework filelists only.

After **`[CP] Embed Pods Frameworks`** (and Copy Pods Resources), the **`[Tashil] Dev strip Crashlytics from app`** phase runs `strip_dev_crashlytics_from_app.sh` and **fails closed** if any Crashlytics framework/bundle remains in the `.app`.
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
The switching script runs **`flutter build ios --config-only`** + **`pod install`** per flavor, then
**`flutter build ios --debug --simulator`** (SwiftPM includes the **`Flutter`** package). Sequence:
**dev → prod → dev**; derived registrant under **`DERIVED_FILE_DIR`** must register Crashlytics only on prod.
