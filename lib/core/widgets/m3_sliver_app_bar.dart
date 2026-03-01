import 'package:flutter/material.dart';

/// A scalable Material Design 3 (M3) SliverAppBar.
/// Designed for a Clean Architecture approach: pure UI widget, unaware of business logic.
class M3SliverAppBar extends StatelessWidget {
  /// The main title text, e.g., "Admin"
  final String title;

  /// The subtitle text, e.g., "Hello, Admin"
  final String subtitle;

  /// Optional leading widget, such as an avatar or back button
  final Widget? leading;

  /// Optional actions for the app bar
  final List<Widget>? actions;

  const M3SliverAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return SliverAppBar(
      // M3 Standards: No forced elevation, rely on scroll-under color tinting
      pinned: true,
      floating: true,
      backgroundColor: colorScheme.surface,
      // The surfaceTintColor will automatically apply when the user scrolls under,
      // natively handling the elevation indication in M3.
      surfaceTintColor: colorScheme.surfaceTint,

      // Flexible space to give room for the leading element and text
      leading: leading != null
          ? Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 8.0,
              ), // Standard M3 16dp edge padding
              child: leading,
            )
          : null,
      leadingWidth: leading != null
          ? 72.0
          : null, // 16px padding + typical 40px avatar + 16px gap

      actions: actions != null
          ? [
              ...actions!,
              const SizedBox(width: 8.0), // End padding for actions
            ]
          : null,

      // Title mapped strictly to M3 Typography Roles
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(
            height: 2.0,
          ), // Balanced vertical spacing (smaller than 8 to keep titles close, but can be adjusted to 8dp if preferred)
          Text(
            subtitle,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
