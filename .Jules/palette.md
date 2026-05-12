## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - Password Visibility Tooltip Accessibility
**Learning:** Icon-only buttons used for toggling password visibility in Flutter require dynamic tooltips to provide accurate state-based accessibility labels (e.g., "Show Password" vs "Hide Password") to screen readers.
**Action:** When adding or modifying suffix icon toggles for `obscureText` fields, always include a dynamic tooltip that switches based on the obscure state to ensure proper accessibility.
