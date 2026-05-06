## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [Tasks] Missing Dynamic Tooltip on Stateful Action Button
**Learning:** Action buttons that toggle between multiple states (like Edit vs. Save Changes) often change their icon to match the state, but if they lack a dynamic tooltip, screen reader users cannot perceive the current action they are about to perform.
**Action:** When an `IconButton` toggles its icon based on a state (e.g., `_isEditing`), always provide a dynamic `tooltip` property that uses localized strings corresponding to the current state (e.g., `tooltip: _isEditing ? l10n.saveChanges : l10n.editAdmin`) to ensure accessibility.
