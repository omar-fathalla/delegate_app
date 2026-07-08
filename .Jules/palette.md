## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-18 - Dynamic Tooltips on State-Toggling Icons
**Learning:** When using IconButton for a state toggle (like show/hide password), a static label is insufficient for screen readers. The tooltip must dynamically update based on state (e.g., `obscureText ? l10n.showPassword : l10n.hidePassword`) to accurately convey the current action.
**Action:** Always provide dynamic, localized tooltip properties corresponding to the current state for toggle icons to ensure proper accessibility.
