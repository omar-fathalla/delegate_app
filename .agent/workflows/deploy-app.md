---
description: Build and deploy the app using CI/CD (GitHub Actions or Codemagic) with signing and Play Console integration.
---

# Deploy App (CI/CD)

## 1. Local build (debug)

Android **requires** a flavor (`prod` or `dev`). iOS uses matching schemes. Without `--flavor`, Gradle fails with an explicit hint (see `android/app/build.gradle.kts`).

```bash
# Run on device/emulator
flutter run --flavor prod
flutter run --flavor dev --dart-define=ENV=dev

# Production Firebase (store package)
flutter build apk --debug --flavor prod

# tashil-dev (side-by-side com.tashil.delegate.dev)
flutter build apk --debug --flavor dev --dart-define=ENV=dev
```

Web / desktop: no flavor.

## 2. Local build (release)

```bash
flutter build apk --release --flavor prod
flutter build appbundle --release --flavor prod
```

Dev release (internal QA only):

```bash
flutter build apk --release --flavor dev --dart-define=ENV=dev
```

iOS:

```bash
flutter build ipa --release --flavor prod --dart-define=ENV=prod
flutter build ios --release --flavor dev --dart-define=ENV=dev
```

## 3. GitHub Actions CI/CD

Primary pipelines live under `.github/workflows/` (`ci.yml`, `android-release.yml`, `pr-user-test-builds.yml`). They pin **Flutter 3.44.5** and pass `--flavor prod` for store artifacts.

Example analyze/test job shape:

```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.44.5'
- run: flutter pub get --enforce-lockfile
- run: flutter analyze
- run: flutter test
```

Release Android (from `main` only, prod flavor):

```yaml
- run: flutter build appbundle --release --flavor prod
```

## 4. Pre-deploy checklist

- [ ] `flutter analyze` clean (Flutter **3.44.5**)
- [ ] `flutter test` pass
- [ ] Version bumped in `pubspec.yaml` when shipping
- [ ] Android/iOS flavor matches `ENV` (`docs/DEV_WORKFLOW_RULES_AR.md`)
- [ ] Firebase project matches flavor (prod vs tashil-dev)
- [ ] Signing keys in CI secrets only (never in repo)

## 5. Versioning

```yaml
version: 1.2.3+45
#        │ │ │  └── Build number
#        │ │ └───── Patch
#        │ └─────── Minor
#        └───────── Major
```

## 6. Branch strategy

```
main      ← Production releases (protected)
dev       ← Integration / User Test
cursor/*  ← Agent feature branches → PR to dev
```

## 7. Commit convention

```
feat: add attendance check-in page
fix: correct geo-fence radius calculation
chore: document Android --flavor in README
```