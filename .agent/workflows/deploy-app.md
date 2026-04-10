---
description: Build and deploy the app using CI/CD (GitHub Actions or Codemagic) with signing and Play Console integration.
---

# Deploy App (CI/CD)

## 1. Local Build (Debug)

// turbo
```
flutter build apk --debug
```

## 2. Local Build (Release)

```
flutter build apk --release
```

For App Bundle (recommended for Play Store):
```
flutter build appbundle --release
```

For iOS:
```
flutter build ipa --release
```

## 3. GitHub Actions CI/CD

Create `.github/workflows/ci.yml`:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [develop, main]
  pull_request:
    branches: [develop, main]

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage

  build-android:
    runs-on: ubuntu-latest
    needs: analyze-and-test
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - run: flutter pub get

      # Decode signing key from secrets
      - name: Decode Keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore.jks

      - name: Build App Bundle
        run: flutter build appbundle --release
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}

      - name: Upload to Play Console
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_SERVICE_ACCOUNT }}
          packageName: com.tashil.delegate
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: internal
```

## 4. Pre-deploy Checklist

- [ ] All tests pass: `flutter test`
- [ ] No analysis issues: `flutter analyze`
- [ ] Version bumped in `pubspec.yaml` (Semantic Versioning)
- [ ] Conventional commit message: `feat:`, `fix:`, `release:`
- [ ] No `print()` statements in code
- [ ] No hardcoded API keys
- [ ] Firebase configuration matches production project
- [ ] Signing keys are in CI secrets (never in repo)

## 5. Versioning

Follow Semantic Versioning in `pubspec.yaml`:

```yaml
version: 1.2.3+45
#        │ │ │  └── Build number (auto-increment in CI)
#        │ │ └───── Patch (bug fixes)
#        │ └─────── Minor (new features, backwards compatible)
#        └───────── Major (breaking changes)
```

## 6. Branch Strategy

```
main      ← Production releases (protected)
develop   ← Staging / integration
feature/* ← Feature development
hotfix/*  ← Urgent production fixes
```

## 7. Commit Convention

```
feat: add attendance check-in page
fix: correct geo-fence radius calculation
refactor: extract location verification to use case
docs: update README with deployment steps
test: add bloc tests for attendance feature
chore: update dependencies
```
