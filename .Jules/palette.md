## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [General] Manual Generation File Edits
**Learning:** Editing generated localization files (`app_localizations.dart` etc.) manually is an anti-pattern as they will be overwritten during the next generation step. Furthermore, temporary python scripts used for text manipulation should be strictly removed to avoid repository pollution.
**Action:** Always rely strictly on standard framework generation commands (e.g., `flutter gen-l10n`) and `.arb` source truth files to generate bindings. Always clean up temporary one-off scratchpad scripts.
