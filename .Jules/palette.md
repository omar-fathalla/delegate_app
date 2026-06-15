## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - [Auth & Profile] Password Visibility Toggle Missing Tooltips
**Learning:** Obscure text fields often have a visibility toggle, but developers commonly forget to add the `tooltip` property to the `IconButton`, making the action invisible to screen readers and mouse hover users. The tooltip needs to be dynamic, matching the state (e.g. 'Show Password' vs 'Hide Password').
**Action:** When adding a suffix icon toggle for `obscureText` fields, always include a dynamic `tooltip` property using localized strings that switch based on the visibility state to ensure proper accessibility.
