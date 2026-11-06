# iOS Firebase config (dev / prod)

- `prod/GoogleService-Info.plist` — production Firebase (`practice-firebase-72df1`), committed.
- `dev/GoogleService-Info.plist` — tashil-dev app (`com.tashil.delegate.dev`). **Not committed**
  (gitignored). Copy from Firebase Console for tashil-dev or from the project store
  `dev-GoogleService-Info_*.plist` into `ios/config/dev/` before building the **dev** flavor.

Build phases (`scripts/firebase_config.sh`) copy the correct plist into the app and fail closed
if this file is missing or does not match `APP_ENV` and `PRODUCT_BUNDLE_IDENTIFIER`.

For **dev** configurations only (`Debug-dev`, `Profile-dev`, `Release-dev`), a Runner build phase
runs `scripts/strip_dev_crashlytics_plugin_registration.sh` after code generation to remove the
Firebase Crashlytics plugin block from `GeneratedPluginRegistrant.m`, so native Crashlytics never
initializes on dev; **prod** builds are unchanged.
