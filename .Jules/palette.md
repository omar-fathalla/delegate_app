## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - Dynamic Tooltips for Stateful Toggles
**Learning:** For stateful icon-only buttons (like a password visibility toggle), a static tooltip or missing tooltip degrades the screen reader experience. It's important to provide a dynamic tooltip (and corresponding ARIA equivalent) that updates to reflect the current state (e.g., switching between "Show Password" and "Hide Password").
**Action:** Always provide localized, dynamic `tooltip` properties for stateful `IconButton` widgets in Flutter to ensure users reliant on accessibility tools receive accurate context about the button's current action.
