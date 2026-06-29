## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [Auth] Password Visibility Toggle Tooltip
**Learning:** Obscured text fields that toggle visibility are a good UX feature, but if they lack dynamic `tooltip` attributes on the `IconButton`, screen reader users miss crucial context about the current state of the field.
**Action:** When adding suffix icon toggles for `obscureText` fields, always include a dynamic tooltip that switches between 'Show Password' and 'Hide Password' localized strings (e.g., `obscureText ? l10n.showPassword : l10n.hidePassword`) to ensure proper accessibility.
