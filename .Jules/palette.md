## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [Auth] Missing Tooltip for Password Visibility Toggle
**Learning:** Icon buttons that toggle state (like showing/hiding a password) are inaccessible to screen reader users if they lack a descriptive `tooltip` that matches the current state.
**Action:** When adding a visibility toggle for `obscureText` fields, always include a dynamic `tooltip` that alternates between localized 'Show Password' and 'Hide Password' labels to ensure proper accessibility.
