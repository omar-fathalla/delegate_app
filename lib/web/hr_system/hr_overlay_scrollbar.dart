import 'package:flutter/material.dart';

/// Thin overlay scrollbar for the web HR shell.
///
/// The thumb is hidden until the pointer hovers it or the view scrolls, and
/// there is no track. The child scrollable does not get a second desktop bar.
class HrOverlayScrollbar extends StatelessWidget {
  final ScrollController? controller;
  final Widget child;

  const HrOverlayScrollbar({super.key, this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.dragged)) return 8.0;
            if (states.contains(WidgetState.hovered)) return 6.0;
            return 4.0;
          }),
          radius: const Radius.circular(8),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final alpha = states.contains(WidgetState.dragged)
                ? 0.55
                : states.contains(WidgetState.hovered)
                ? 0.45
                : 0.32;
            return cs.onSurfaceVariant.withValues(alpha: alpha);
          }),
          trackVisibility: const WidgetStatePropertyAll(false),
          trackColor: const WidgetStatePropertyAll(Colors.transparent),
          trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
          crossAxisMargin: 2,
          mainAxisMargin: 4,
        ),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: false,
        trackVisibility: false,
        interactive: true,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: child,
        ),
      ),
    );
  }
}
