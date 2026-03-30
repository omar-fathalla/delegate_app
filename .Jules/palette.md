## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-06-15 - [A11y] Screen reader support for common IconButtons
**Learning:** Icon buttons used for common interactions (like toggling password visibility or closing dialogs) were missing tooltips, causing screen reader users to hear "button" without context.
**Action:** Always include a descriptive `tooltip` for `IconButton` widgets. For generic actions like close or back, use built-in `MaterialLocalizations.of(context).closeButtonTooltip` to ensure standard translations. For custom actions like "Show password", add custom strings to `AppLocalizations`.
