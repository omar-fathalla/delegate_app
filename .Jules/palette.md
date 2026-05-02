## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2025-02-16 - Dynamic tooltips for password visibility toggles
**Learning:** Using dynamic tooltips for icon buttons that toggle states (e.g. password visibility) improves screen reader accessibility by providing context on the *current* action the button performs.
**Action:** Always verify if an icon-only button that changes state could benefit from a dynamically changing tooltip. Use `l10n` to provide localized tooltip text.
