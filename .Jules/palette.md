## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2024-04-28 - Dynamic Tooltips for State-Toggled Icon Buttons
**Learning:** Adding a static `tooltip` to an `IconButton` that toggles state (like a show/hide password visibility toggle) is insufficient for screen readers. The tooltip must dynamically update to reflect the current actionable state (e.g., switching from "Show Password" to "Hide Password"). If the tooltip remains static, the screen reader user loses context on what action the button will perform next.
**Action:** Always bind the `tooltip` property of stateful `IconButton` widgets to localized strings that reflect the conditional state of the toggle, ensuring accurate and contextual feedback for assistive technologies.
