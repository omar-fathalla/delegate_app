## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2024-04-29 - Accessible Password Toggles
**Learning:** Found that password visibility toggles (`IconButton` with an eye icon) in `LoginScreen` and `UserProfileScreen` lacked screen reader tooltips, making them completely inaccessible to visually impaired users attempting to manage their credentials. The toggle text needs to dynamically switch based on the obscure state.
**Action:** When creating toggle buttons without visual text labels (especially security-sensitive ones like password visibility), always bind the `tooltip` property to a dynamic localized string (e.g., `_obscurePassword ? l10n.showPassword : l10n.hidePassword`). Ensure new generic interaction strings are added to both English and Arabic ARB files and propagated via `flutter gen-l10n`.
