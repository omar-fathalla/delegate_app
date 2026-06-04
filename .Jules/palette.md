## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - [Auth/Profile] Tooltip on Password Visibility Toggle
**Learning:** Adding a tooltip that changes state (e.g., "Show Password" to "Hide Password") to a password visibility icon improves accessibility for screen readers. It provides clear, localized feedback on what the toggle button does.
**Action:** When adding suffix icon toggles for `obscureText` fields, always include a dynamic tooltip that switches between 'Show Password' and 'Hide Password' localized strings (e.g., `obscureText ? l10n.showPassword : l10n.hidePassword`) to ensure proper accessibility.
