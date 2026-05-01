## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-22 - [Auth] Missing Tooltip on Password Visibility Toggle
**Learning:** Icon-only buttons used for state toggles (like password visibility) need dynamic tooltips that reflect the *action* that will occur when pressed, not just the current state. The tooltip text ("Show Password" vs "Hide Password") must stay in sync with the visual icon.
**Action:** When implementing suffix icon toggles for `obscureText` fields, always include a localized `tooltip` property that dynamically switches between state-appropriate actions to ensure screen reader clarity and desktop hover context.
