# Android `dev` flavor (tashil-dev)

The **`dev`** product flavor installs **beside** the store app (`com.tashil.delegate.dev` vs `com.tashil.delegate`), uses Firebase project **tashil-dev**, and is wired in `android/app/build.gradle.kts`.

| Item | `prod` | `dev` |
|------|--------|-------|
| `applicationId` | `com.tashil.delegate` | `com.tashil.delegate.dev` (`applicationIdSuffix = ".dev"`) |
| `google-services.json` | `android/app/google-services.json` | `android/app/src/dev/google-services.json` |
| Firebase project | `practice-firebase-72df1` | `tashil-dev` |
| Dart `ENV` | `prod` or unset | **`dev`** (`--dart-define=ENV=dev`) |
| Label | Tashil Employee | Tashil Dev |

Gradle **fails closed** if `--flavor` is missing, if flavor and `ENV` disagree, or if the dev Maps key is unset. See `docs/DEV_WORKFLOW_RULES_AR.md`.

## Build commands

**Debug** (local emulator / device):

```bash
# Requires dev Maps key — android/README_MAPS_KEYS.md
flutter build apk --debug --flavor dev --dart-define=ENV=dev
```

**Release** (smoke / App Distribution; not Play Store):

```bash
export DEV_MAPS_ANDROID_KEY='<from GCP tashil-dev Dev Maps Android key>'
# Optional: place android/app/upload-keystore.jks locally (gitignored) so release
# uses the same cert as CI debug-signed prod PR builds when key.properties is absent.

flutter build apk --release --flavor dev --dart-define=ENV=dev
# Output: build/app/outputs/flutter-apk/app-dev-release.apk
```

**Run:**

```bash
flutter run --flavor dev --dart-define=ENV=dev
```

Signing configs and keystores are **unchanged** from store release: this doc does not add or rotate keys.

## Firebase App Distribution (manual)

There is **no** automated CI upload for dev APKs (no Firebase tokens in the repo). Build locally or on the Mac runner, then distribute with the Firebase CLI.

1. Install [Firebase CLI](https://firebase.google.com/docs/cli) and sign in (`firebase login`).
2. Build the release dev APK (command above).
3. Upload:

```bash
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-dev-release.apk \
  --app "1:582609039627:android:40c38c45d1bdb99add720e" \
  --project tashil-dev \
  --release-notes "Android dev build (manual)"
```

Or use the wrapper (same flags, optional env overrides):

```bash
bash scripts/android_dev_distribute.sh
```

Tester groups / emails: configure in the [Firebase Console](https://console.firebase.google.com/project/tashil-dev/appdistribution) (App Distribution → testers). The CLI can add `--groups` or `--testers` when needed.

## SHA-1 fingerprints for Mohamed (Firebase Console)

Register these on the **tashil-dev** Android app **`com.tashil.delegate.dev`**  
(Firebase Console → Project settings → Your apps → Android → **Add fingerprint**).

| Certificate | When it applies | SHA-1 |
|-------------|-----------------|-------|
| **Upload / CI release** (`upload-keystore.jks`, alias `upload`) | `flutter build apk --release` when `android/key.properties` is **missing** (same pattern as PR User Test prod APKs) and when the upload keystore file is present under `android/app/` | `42:52:13:BF:B1:59:48:A1:CB:FB:A4:29:89:60:5E:BF:B5:58:A4:7E` |
| **Upload / CI release** | SHA-256 (optional in Console) | `EF:C4:0A:A9:B7:1F:32:90:F5:90:25:7E:7D:FB:DB:CA:D9:62:3D:CA:8F:B9:7F:2C:99:F1:72:58:E8:9A:6D:21` |
| **Local debug** | `flutter run` / `--debug` using the machine’s `~/.android/debug.keystore` | **Per machine** — run locally (do not commit): |

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1
```

Also add that debug SHA-1 to the **Dev Maps Android key** restrictions in GCP (`tashil-dev`) if Maps fails on debug builds (`android/README_MAPS_KEYS.md`).

**Store release** (`key.properties` + upload keystore on `main`) uses the **same upload certificate** SHA-1 above for Play builds; the dev flavor does not introduce a separate release keystore.

## Firebase Android app IDs (reference)

| App | Package | Firebase App ID |
|-----|---------|-----------------|
| Dev | `com.tashil.delegate.dev` | `1:582609039627:android:40c38c45d1bdb99add720e` |
| Prod (delegate) | `com.tashil.delegate` | see `android/app/google-services.json` |