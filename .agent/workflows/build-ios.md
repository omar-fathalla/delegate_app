---
description: Build, sign, export, and distribute iOS IPA with auto-incremented build number
---

# iOS Auto Build & Distribute

This workflow automatically increments the build number, builds the iOS archive with signing, exports the IPA, and uploads it to Firebase App Distribution.

## Quick Run (One Command)
// turbo-all
1. Run the auto build script:
```bash
./scripts/auto_build_ios.sh
```

This script does everything automatically:
- ✅ Increments Build Number in `pubspec.yaml`
- ✅ Runs `flutter clean` and `flutter pub get`
- ✅ Builds iOS Release
- ✅ Creates signed Xcode Archive (Team: TX5G7GZL6T)
- ✅ Exports IPA
- ✅ Uploads to Firebase App Distribution

## Manual Steps (If Needed)

1. Increment build number in `pubspec.yaml`:
```bash
# Current: version: 1.0.0+N → New: version: 1.0.0+(N+1)
```

2. Clean and get dependencies:
```bash
flutter clean && flutter pub get
```

3. Build iOS release:
```bash
flutter build ios --release --no-codesign
```

4. Archive with signing:
```bash
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner -sdk iphoneos -configuration Release \
  archive -archivePath build/ios/Runner.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TX5G7GZL6T \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development"
```

5. Export IPA:
```bash
xcodebuild -exportArchive \
  -archivePath build/ios/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

6. Upload to Firebase:
```bash
firebase appdistribution:distribute build/ios/ipa/delegate_app.ipa \
  --app 1:564223619997:ios:6a342f9eb34ad80f233574 \
  --release-notes "iOS build" \
  --project practice-firebase-72df1
```

## Configuration
- **Team ID**: TX5G7GZL6T
- **Firebase App ID**: 1:564223619997:ios:6a342f9eb34ad80f233574
- **Firebase Project**: practice-firebase-72df1
- **Bundle ID**: com.tashil.delegate
