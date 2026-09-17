# Project Rules and Policies

## Binary Builds & Compilation
- **Do NOT execute `flutter build apk` (or any build variant like `flutter build appbundle`, `flutter build ipa`) automatically or proactively.**
- Only run build commands when the user explicitly and directly asks to build the APK/app.
- For all code changes, validations, and tests, use only `flutter analyze` and `flutter test`.

## Header & App Bar Popup Menu Ordering (Across all 9 User Roles)
- In all App Bars / Header Menus / `PopupMenuButton`s across all user roles (Delegate, Promoter, Supervisor, Admin, Super Admin, Organization Admin, Technical Support, Marketing, Branches Marketing Manager):
  - The **Profile (`profile`)** and role-specific feature options (e.g. Search, Tasks, Penalties, Admin tools, Org Switch) must always appear at the top.
  - The **Settings (`settings` / الإعدادات)** option **MUST ALWAYS BE THE LAST / BOTTOM-MOST item in the menu**, even when new items or options are added in the future.

## Firebase Storage & Security Rules (Feedback & Uploads Across All 9 User Roles)
- All authenticated users across all 9 roles must have full permission to upload feedback screenshots to `/feedback_screenshots/{fileName}` and submit to `/feedbacks`.
- Whenever upload paths are created or updated, ensure `storage.rules` and `firestore.rules` are synchronized and deployed to Firebase.

## Cache-First & Offline-First Performance Standard
- For frequently viewed data (Notifications, Photo Permissions, Penalties, Directory, Profiles):
  - Always render cached data instantly (0 ms) from local persistent cache (`SharedPreferences` or LocalDataSource) before waiting on network queries.
  - Revalidate and synchronize new or updated documents in the background (Stale-While-Revalidate pattern).
  - Attendance check-in and anti-fraud geo-verification must remain strictly verified with live server time.

## Material Design 3 (M3) Motion System Standard
- All animations, transitions, and micro-interactions across the entire app must strictly comply with `.agent/skills/material_design_3_motion/SKILL.md`:
  - **No Arbitrary Durations or Curves**: Use ONLY tokens from `AppMotionDurations` and `AppMotionCurves`. `Curves.linear` is strictly prohibited for visible UI animations.
  - **Exit < Enter Ratio**: Exiting/dismissing transitions must be ~50% faster than entering transitions.
  - **Zero Overshoot for Effects**: Opacity, surface tint, and color transitions must be strictly monotonic (no bounce/overshoot). Overshoot is reserved exclusively for spatial movements in the Expressive scheme.
  - **RTL-Aware Shared Axis**: In Arabic mode (`TextDirection.rtl`), horizontal directional motion (Shared Axis X) must be dynamically inverted.

