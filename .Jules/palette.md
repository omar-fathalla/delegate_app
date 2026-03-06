## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-06-15 - [Auth] Missing Tooltip on Password Visibility Toggle
**Learning:** The password visibility toggle button lacked a `tooltip` description, making it difficult for screen reader users to understand its purpose. Icon-only buttons should always include descriptions.
**Action:** When using an `IconButton` to toggle state like password visibility, always provide a dynamically updating `tooltip` property to describe the action ("Show Password" vs "Hide Password").
