# Project Rules and Policies

## Binary Builds & Compilation
- **Do NOT execute `flutter build apk` (or any build variant like `flutter build appbundle`, `flutter build ipa`) automatically or proactively.**
- Only run build commands when the user explicitly and directly asks to build the APK/app.
- For all code changes, validations, and tests, use only `flutter analyze` and `flutter test`.

## Git & Version Control Policy
- **Do NOT run `git push` (or push commits to GitHub / remote repositories) automatically or proactively.**
- Only push to GitHub when the user explicitly and directly asks to push (e.g. "ارفع على جيت هب" أو "push on github").

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

## Google Cloud & Firebase Functions Isolation Policy (Zero Deletion / Zero Conflict)
- **Shared GCP Project Architecture**: The GCP / Firebase project (`practice-firebase-72df1` / `Tashil`) hosts 22+ active production Cloud Functions and Cloud Run services supporting the Web portal and other external systems (e.g., `approvecreaterequest`, `createorganization`, `deleteuser`, `verifyrecaptcha`, etc.).
- **Mandatory Codebase Isolation**: All Cloud Functions developed in this mobile application repository MUST strictly belong to an isolated codebase (defined as `"codebase": "tashil-mobile-notifications"` in `firebase.json`).
- **Targeted Deployment ONLY**: NEVER execute blanket un-scoped deployment commands like `firebase deploy --only functions`. Always use targeted deployment by function name or isolated codebase:
  - Example: `firebase deploy --only functions:tashil-mobile-notifications` or `firebase deploy --only functions:tashil-mobile-notifications:onNotificationCreated,...`
- **Zero Deletion / Zero Edit Rule**:
  - NEVER delete, edit, or override any Cloud Function, Cloud Run service, or trigger belonging to other systems sharing this Google Cloud project.
  - All operations must be ADDITIVE ONLY (`--only` targeted to mobile notification functions).

## Strict Multi-Tenant Company Data Isolation Policy (قاعدة عزل بيانات الشركات الصارمة)
- **Absolute Company Scoping (حظر تسريب بيانات الشركات)**:
  - Whenever a user belongs to a specific company (`companyUID.isNotEmpty`), including:
    - **HR (`UserRole.hr`)**
    - **Company Admins (`UserRole.admin`)**
    - **Supervisors (`UserRole.delegate` / supervisor position)**
    - **Promoters & Delegates (`UserRole.delegate`, `UserRole.marketingPromotion`)**
    - **Branches Marketing Managers (`UserRole.branchesMarketingManager`)**
    - **Accountants (`UserRole.accountant`)**
  - **The Entire System MUST Strictly Scope All Data to Their Company Only**:
    1. **Delegates & Supervisors**: Only delegates/supervisors belonging to `companyUID` (`/organizations/{org}/companies/{comp}/delegates` or `where('companyUID', isEqualTo: companyUID)`).
    2. **Attendance & Absence Logs**: Strictly queried and filtered by `companyId` / `companyUID`.
    3. **Security & Anti-Fraud Logs (`security_audit_logs`)**: Strictly queried and filtered by `companyUID`. Metrics (Total attempts, Today attempts, Unique delegates, Unique devices) and dropdowns must only count/reflect the company's violations.
    4. **Device Unbind Requests (`device_unbind_requests`)**: Strictly queried and filtered by `companyUID`.
    5. **Photos, Permissions, Penalties, & Leaves**: Strictly scoped to `companyUID`.
  - **Zero Leakage Rule**: No record, name, branch, count, or metric belonging to any other company may ever appear or be calculated in any view of a company-scoped user.
  - **Dual-Layer Enforcement**:
    - Query-level scoping via `.where('companyUID', isEqualTo: user.companyUID)` whenever supported by indexes.
    - Mandatory in-memory client-side post-filtering (`removeWhere` or `where`) before calculating summary counters or rendering lists.
  - **Global Roles Exemption**:
    - Only `UserRole.superAdmin` and `UserRole.technicalSupport` (and Organization Admins operating at the organization root with an empty companyUID) have cross-company visibility.

## Web-First Enterprise Tables, Toolbars, & Single-Seed Theme Standard (HR System & Backoffice)
- **Web-First Desktop Application Mindset (تطبيق ويب ابليكيشن وليس مجرد شاشة موبايل)**:
  - The system is primarily accessed and operated from Desktop Web browsers.
  - **No Full-Width Button Stretching**: Action buttons (such as "إيقاف التتبع لجميع الحاضرين" / bulk actions / export) MUST NEVER stretch across the entire screen width (no 1600px banner buttons). They must always be natural, content-sized buttons (`MainAxisSize.min`, standard height 44dp, padding horizontal 16dp).
  - **Single-Row Filter Toolbar (صف أفقي واحد)**: On desktop viewports (`maxWidth >= 768px`), the Search bar, Status filter dropdown, Branch filter dropdown, and Primary/Bulk action buttons must sit on **ONE single horizontal line** (`Row`) at the exact same vertical level.
- **Material Design 3 Dropdown Menus & Google Icons Only**:
  - **Google Icons Exclusively**: Only official Flutter Google Material Icons (`Icons.*_rounded` or `Icons.*_outlined`) may be used throughout the UI.
  - **M3 Dropdown Specification**: All filter dropdowns must use M3 standards via `PopupMenuButton`:
    - Menu container: `colorScheme.surfaceContainerHigh`, elevation `3`, rounded corners `14px`, border `colorScheme.outlineVariant.withValues(alpha: 0.5)`.
    - Menu items: Leading Google icon, item label, optional count pill/badge, and trailing `Icons.check_rounded` for the active selection.
    - Trigger button: Height `44px`, background `colorScheme.surfaceContainerLow`, border `colorScheme.outlineVariant`, leading Google icon, label in bold, and trailing `Icons.expand_more_rounded`.
- **Single-Seed Theme Harmony & Contrast (تناسق الألوان واشتقاقها من سيمز النظام)**:
  - The entire design must derive organically from the primary seed theme (`colorScheme.primary`, `colorScheme.surface`, `colorScheme.surfaceContainerLow`, `colorScheme.outlineVariant`).
  - **Forbidden**: Do NOT tint entire cards or card outer borders with intense status colors (e.g. green background/border for all present delegates). Status colors (green, amber, grey) are strictly confined to:
    1. A subtle 3.5px start border line on the card.
    2. A compact status pill/chip (`Container` with 12px radius, icon, and text).
  - The card itself must always have `colorScheme.surface` background, `colorScheme.outlineVariant` border, and smooth hover state highlighting (`colorScheme.primary.withValues(alpha: 0.05)`).


