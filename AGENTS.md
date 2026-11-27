# Project Rules and Policies

## Flutter SDK (3.50.1)
- **Pinned version:** Flutter **3.50.1** on app CI and local mirror — `.fvmrc`, `.github/workflows/ci.yml`, `pr-user-test-builds.yml` (`flutter-version: '3.50.1'`), and `scripts/local_ci.sh`, which reads the version from the tested commit's `.fvmrc` and uses `~/toolchains/flutter-<version>` (`scripts/ci/flutter_sdk.sh`, TAS-342; `LOCAL_CI_FLUTTER_SDK` still overrides). Bumping Flutter = change `.fvmrc` + the workflow pins + install the new toolchain on the Mac; local CI follows by itself. `deploy-ios.yml` is also pinned to 3.50.1 (since the 3.50.1 bump the lockfile needs Dart >=3.13, so the old 3.41.2 pin can no longer run `pub get`). `android-release.yml` still uses the action's latest `stable` channel (3.50.1 at the time of the bump); pin it in a release PR if stable moves past a version the lockfile accepts.
- **Local setup:** `fvm install && fvm use` (reads `.fvmrc`), or install Flutter 3.50.1 manually. `pubspec.yaml` declares Dart `^3.11.0`, but the lockfile's dev tooling (freezed 4, test 1.32) needs Dart >=3.13; Flutter 3.50.1 bundles Dart 3.14.0.
- **Validation:** Run `flutter pub get --enforce-lockfile` before analyze/test when checking lock compatibility; on Mac billing lock use `bash scripts/local_ci.sh <sha>`.
- **Do not** change `pubspec.lock` as a side effect — keep it byte-identical when only pinning docs/tooling. It changes on purpose in a Flutter/Dart bump or a dependency upgrade done as its own Linear ticket and branch (user decision 2026-11-26: prefer the newest packages, especially for design, instead of building on old versions; e.g. TAS-374 moved the app to `material_ui` / `cupertino_ui`). Check `flutter pub get --enforce-lockfile` and the minimum Flutter version the lock needs against CI and the release workflows.

## Binary Builds & Compilation
- **Do NOT execute `flutter build apk` (or any build variant like `flutter build appbundle`, `flutter build ipa`) automatically or proactively.**
- Only run build commands when the user explicitly and directly asks to build the APK/app.
- For all code changes, validations, and tests, use only `flutter analyze` and `flutter test`.

## Git & Version Control Policy
- **Do NOT run `git push` (or push commits to GitHub / remote repositories) automatically or proactively.**
- Only push to GitHub when the user explicitly and directly asks to push (e.g. "ارفع على جيت هب" أو "push on github").
- قواعد سير العمل العربي (فروع منفصلة، اختبار قبل الدمج، فشل البيلد عند إعدادات Firebase غلط): انظر `docs/DEV_WORKFLOW_RULES_AR.md`.

## Header & App Bar Popup Menu Ordering (Across all 9 User Roles)
- In all App Bars / Header Menus / `PopupMenuButton`s across all user roles (Delegate, Promoter, Supervisor, Admin, Super Admin, Organization Admin, Technical Support, Marketing, Branches Marketing Manager):
  - The **Profile (`profile`)** and role-specific feature options (e.g. Search, Tasks, Private Label, Admin tools, Org Switch, Wallet) must always appear at the top.
  - Whenever **المخالفات والغرامات (`penalties` / `penalties_management`)** is present:
    - If **تسجيل الخروج (`logout`)** is present: **المخالفات والغرامات** MUST be placed directly and immediately above **تسجيل الخروج** (so the two red-accented operational items sit seamlessly together without any other options between them).
    - If **تسجيل الخروج (`logout`)** is NOT present: **المخالفات والغرامات** MUST be placed as the last option right above the divider and Settings (`settings`).
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
- All animations, transitions, and micro-interactions follow `docs/design/design-system.md` (Motion) and `.agent/skills/material_design_3_motion/SKILL.md`:
  - **No Arbitrary Durations or Curves**: Use ONLY tokens: `TashilSpring` / `TashilEasing` (`lib/core/design/motion.dart`) for new work, `AppMotionDurations` / `AppMotionCurves` (`lib/config/theme/app_motion.dart`) where existing code already uses them. `Curves.linear` is strictly prohibited for visible UI animations. Wrap durations so the system "remove animations" setting turns motion off.
  - **One transition per kind of navigation**: every route uses `M3PageTransitionsBuilder` / `AppMotionPage` (same shared axis).
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

## Design System: Material 3 (m3-kit) — single source of truth (TAS-345, user decision 2026-11-26)
The design references live in `docs/design/` (start with `docs/design/README.md`): `m3-catalog.md` gives every M3 item a fixed ID (F foundations, C components) and the review steps; `design-system.md` holds the rules. Code: `lib/core/design/` (tokens, typography, motion, bidi, money, layout, M3 Expressive widgets) wired through `lib/config/theme/app_theme.dart`. Review procedure: `.claude/skills/m3-review/`. Any older design rule elsewhere that disagrees is superseded.
- **Colour (F-01..F-04):** every role is generated from one seed (`TashilColors.seed`, the app purple; the user may pick another in settings). Never hand-pick tones, never write a hex colour or `Colors.*` in a screen. Use `Theme.of(context).colorScheme` roles in their pairs (fill with its `on` colour) and `TashilSemanticColors.of(context)` for success / warning. `error` is for errors and for a state that blocks the person's action (outside the attendance zone blocks check-in: `errorContainer`, user decision 2026-11-27, TAS-387); absence counts and penalty amounts are values, not errors. Status colours never tint a whole card: a compact status label or pill only. Zero / not-started values are neutral (`onSurfaceVariant`).
- **Icons on cards (TAS-384, user decision 2026-11-26):** every icon in a circle / rounded square on a surface card and every icon button on a card is `primary` fill + `onPrimary` icon (`IconButton.filled`), the same on every screen. Never `primaryContainer` / `secondaryContainer` there (they fade into `Card.filled`). Only a card that is itself `primary` uses the light container for its icon. Read-only values (active organization, a status) are an icon + text label, not a chip. Exception: notification kinds each use their own role pair (error / success / warning / primary / secondary / tertiary) for the icon and a small kind label (user decision 2026-11-27, TAS-387).
- **Surfaces:** body `surface`; navigation areas `surfaceContainer`; cards and groups use the container roles for hierarchy (one card style per screen, from the theme, no alpha borders).
- **Type (F-05):** text styles only from `Theme.of(context).textTheme` (Cairo variable, M3 scale with Arabic line height). No hand-written `fontSize`. `test/design/no_new_raw_styles_test.dart` is a ratchet: the count of `fontSize:` and hex colours in `lib/` may only go down; lower its baselines in the same change when you clean a screen.
- **Shape and spacing (F-06, F-11, F-13):** `TashilRadius` and `TashilSpacing` only; `EdgeInsetsDirectional` / `AlignmentDirectional` always; phone numbers, codes and dates inside Arabic go through `Bidi.ltr()`.
- **Components (C-xx):** official Flutter widget first (`material_ui` / `cupertino_ui`), then `lib/core/design/widgets/`, hand-built only when neither exists (record it in the catalog). The component table in `design-system.md` decides which one: e.g. 2-5 exclusive options → connected `ButtonGroup` (not `SegmentedButton`, not hand-made pills); filters → `FilterChip` (never `ChoiceChip`); one value in a form → `DropdownMenu`; actions on an item → `MenuAnchor` menu; icon-only buttons always have a `tooltip`.
- **Dialogs and sheets (C-27, C-28):** confirm an irreversible action with `showTashilDialog` (`AlertDialog`, text buttons, confirm at the end = left in Arabic, named after its result). A create/edit form is a `FormDialog` (full screen on compact, basic dialog from 600dp). A modal bottom sheet is for lists of actions or options; it opens at content height, never above 50%, and can be pulled to full screen. Side sheets from 840dp (`showAdaptiveSheet`). Short results → `showTashilSnackBar` (text only, one action).
- **Buttons (C-01):** one `FilledButton` (main action) per screen, `FilledButton.tonal` / `OutlinedButton` for secondary, `TextButton` for low emphasis. No `ElevatedButton` for actions. 48dp minimum targets (theme).
- **Navigation (C-17, C-18):** `NavigationBar` with 3-5 labelled destinations on compact, rail from 600dp, never both. Secondary destinations in a modal navigation rail, not a drawer.
- **Icons:** official Material icons only (`Icons.*_rounded` / `*_outlined`); no emoji or unicode glyphs in labels.
- **HR web layout (kept):** desktop action buttons are content-sized, never stretched across the window; on desktop (>= 840dp) search, filters and the primary action sit on one toolbar row.
- **Every design change:** update the catalog row (Code, Test, Reviewed), before/after screenshots on the Linear issue, tests, and goldens checked by eye.
