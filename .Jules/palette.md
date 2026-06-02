## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2026-02-17 - [Auth] Missing Tooltips on Password Visibility Toggles
**Learning:** Icon-only password visibility toggles (`Icons.visibility_outlined`) lacked descriptive tooltips. This is problematic for screen reader users and those navigating quickly who may rely on tooltips for clarity, violating accessibility guidelines.
**Action:** When adding suffix icon toggles for `obscureText` fields, always provide a `tooltip` property using localized strings that alternate between states (e.g., "Show Password" and "Hide Password"). Ensure to pass `AppLocalizations` down to generic text field builder functions to properly localize these tooltips.
