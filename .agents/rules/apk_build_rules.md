# APK Build Execution Policy

## Explicit User Request Requirement
- **NEVER** run `flutter build apk`, `flutter build appbundle`, `flutter build ipa`, or any full application binary compilation commands proactively, automatically, or as part of general tasks/modifications.
- Binary builds (APK / AppBundle / IPA) must **ONLY** be executed when the user **EXPLICITLY** asks to build or export a binary/APK in their prompt.
- For code verification and validation, rely strictly on:
  1. `flutter analyze`
  2. `flutter test`
