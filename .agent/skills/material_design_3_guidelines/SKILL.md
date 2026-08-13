---
name: material_design_3_guidelines
description: Enforces Material Design 3 (M3) standards, unified button styles, consistent rounded corners, color scheme tokens, RTL Arabic compatibility, and page layout architecture for Flutter UI development in delegate_app.
---

# Material Design 3 (M3) Flutter UI Design System Skill

This skill provides comprehensive instructions, design tokens, code templates, and anti-patterns for designing and building Flutter widgets and pages in `delegate_app`. All UI code generated or updated MUST adhere strictly to these guidelines to ensure visual consistency, accessibility, and modern Material 3 aesthetics.

---

## 1. Core Material 3 Principles

1. **Theme Tokenization (`ThemeData(useMaterial3: true)`)**
   - Never hardcode colors (`Colors.blue`, `Color(0xFF...)`). Always consume colors dynamically from `Theme.of(context).colorScheme`.
   - Never hardcode fonts or text sizes. Always consume typography styles from `Theme.of(context).textTheme`.

2. **Unified Corner Radii (Corner Shapes)**
   - Every component category has a standardized corner radius. Never invent random border radii.

3. **Surface Tinting & Tonal Elevation**
   - M3 relies on surface container color shifts (`surfaceContainerLow`, `surfaceContainerHigh`, `surfaceContainerHighest`) rather than harsh drop shadows (`elevation: 8`).

4. **RTL & Arabic Localization Readiness**
   - Always use directional metrics (`EdgeInsetsDirectional`, `BorderRadiusDirectional`, `AlignmentDirectional`) to support Arabic and English seamlessly.

---

## 2. Corner Radii & Shape Matrix

| Component Category | Target Radius | Flutter Code Snippet |
| :--- | :--- | :--- |
| **Buttons (Primary, Tonal, Outlined)** | Stadium / Full Pill (28dp) | `StadiumBorder()` or `BorderRadius.circular(28)` |
| **Floating Action Button (FAB)** | Squircle (16dp) | `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` |
| **Chips / Badges** | Small Pill (8dp - 12dp) | `RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))` |
| **Cards & Container Boxes** | Medium (12dp - 16dp) | `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` |
| **Text Form Fields / Inputs** | Small-Medium (12dp) | `OutlineInputBorder(borderRadius: BorderRadius.circular(12))` |
| **Dialogs & Alert Modals** | Extra Large (28dp) | `RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))` |
| **Bottom Sheets (Modal)** | Top Extra Large (28dp) | `BorderRadius.vertical(top: Radius.circular(28))` |
| **Snackbars (Floating)** | Medium (12dp) | `RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))` |

---

## 3. Button Standards & Hierarchy

Choose the correct button type based on action emphasis:

```dart
// 1. Primary High-Emphasis Action (FilledButton)
FilledButton.icon(
  onPressed: () {},
  icon: const Icon(Icons.check),
  label: const Text('حفظ'), // Save
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48), // Standard tap height
    shape: const StadiumBorder(),
  ),
)

// 2. Secondary Medium-Emphasis Action (FilledButton.tonal)
FilledButton.tonal(
  onPressed: () {},
  child: const Text('عرض التفاصيل'), // View Details
  style: FilledButton.styleFrom(
    minimumSize: const Size(120, 48),
    shape: const StadiumBorder(),
  ),
)

// 3. Medium-Low Emphasis Action (OutlinedButton)
OutlinedButton(
  onPressed: () {},
  child: const Text('إلغاء'), // Cancel
  style: OutlinedButton.styleFrom(
    minimumSize: const Size(100, 48),
    shape: const StadiumBorder(),
    side: BorderSide(color: Theme.of(context).colorScheme.outline),
  ),
)

// 4. Low-Emphasis / Inline Dialog Action (TextButton)
TextButton(
  onPressed: () {},
  child: const Text('تخطي'), // Skip
)
```

---

## 4. Cards, Containers & Banners

### M3 Styled Card
```dart
Card(
  elevation: 0,
  color: Theme.of(context).colorScheme.surfaceContainerLow,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
    ),
  ),
  child: Padding(
    padding: const EdgeInsetsDirectional.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'عنوان الكارت',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'وصف محتوى الكارت وفق معايير Material 3',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    ),
  ),
)
```

### M3 Styled Input Field
```dart
TextFormField(
  decoration: InputDecoration(
    labelText: 'اسم المستخدم',
    hintText: 'أدخل الاسم الكامل',
    prefixIcon: const Icon(Icons.person_outline),
    filled: true,
    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
    ),
  ),
)
```

---

## 5. Page Layout Architecture Template

Every new page or screen should follow this standard scaffold layout:

```dart
class StandardM3Page extends StatelessWidget {
  const StandardM3Page({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'عنوان الصفحة',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        scaffoldColorScheme: colorScheme,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Content widgets go here
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 6. Anti-Patterns & Prohibited Code

| Prohibited Practice | Recommended M3 Alternative |
| :--- | :--- |
| `RaisedButton`, `FlatButton`, `OutlineButton` | Use `FilledButton`, `FilledButton.tonal`, `OutlinedButton`, or `TextButton` |
| `Color(0xFF1E88E5)` (Hardcoded primary blue) | `Theme.of(context).colorScheme.primary` |
| `EdgeInsets.only(left: 16, right: 8)` | `EdgeInsetsDirectional.only(start: 16, end: 8)` |
| `BorderRadius.only(topLeft: Radius.circular(12))` | `BorderRadiusDirectional.only(topStart: Radius.circular(12))` |
| `BoxShadow(blurRadius: 20, color: Colors.black)` | Use M3 tonal surface colors (`surfaceContainerLow` / `surfaceContainerHigh`) or minimal elevation `0` to `2` |
| `Container(decoration: ...)` without Theme colors | Wrap containers using `colorScheme.surfaceContainer` and `colorScheme.outlineVariant` |

---

## 7. Checklist for UI Code Verification

Before declaring any widget or page design complete, verify:
- [ ] Is `useMaterial3: true` assumed and supported?
- [ ] Are all colors dereferenced via `Theme.of(context).colorScheme`?
- [ ] Are all text styles dereferenced via `Theme.of(context).textTheme`?
- [ ] Do all buttons use stadium/pill rounded shapes (28dp)?
- [ ] Do all cards, inputs, dialogs, and sheets use standard corner radii (12dp, 16dp, 28dp)?
- [ ] Is all padding and alignment directional (`EdgeInsetsDirectional`) for full RTL Arabic support?
