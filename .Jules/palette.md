## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - [Profile] Accessibility Tooltips on Password Toggles
**Learning:** Icon-only buttons used for toggling password visibility in profile management lacked ARIA-equivalent tooltips, making them inaccessible to screen readers. Relying solely on visual cues (Icons.visibility_off_outlined) is insufficient.
**Action:** Added `tooltip` property with localized strings (`l10n.showPassword` / `l10n.hidePassword`) to `IconButton` suffix toggles in `_buildTextField`.
