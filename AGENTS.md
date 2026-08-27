# Project Rules and Policies

## Binary Builds & Compilation
- **Do NOT execute `flutter build apk` (or any build variant like `flutter build appbundle`, `flutter build ipa`) automatically or proactively.**
- Only run build commands when the user explicitly and directly asks to build the APK/app.
- For all code changes, validations, and tests, use only `flutter analyze` and `flutter test`.
