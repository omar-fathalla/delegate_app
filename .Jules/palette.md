## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - [Accessibility] Dynamic Tooltips on Toggles
**Learning:** Icon buttons that toggle states (like `obscureText` for password visibility) lacked dynamic tooltips, leading screen readers to read generic or no labels for both states.
**Action:** When creating toggle `IconButton`s, always ensure the `tooltip` property dynamically reflects the *action* that will be taken if pressed, correctly mapped to the current state (e.g., `obscureText ? l10n.showPassword : l10n.hidePassword`).
