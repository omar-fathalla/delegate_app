import 'package:material_ui/material_ui.dart';

/// One status filter on the «طلبات الاشتراك» web page.
@immutable
class SubscriptionFilterOption<T> {
  const SubscriptionFilterOption({
    required this.label,
    required this.count,
    required this.value,
    this.key,
  });

  final String label;
  final int count;

  /// Null means «الكل».
  final T? value;
  final Key? key;
}

/// Status filter chips on a single line (TAS-142). The row scrolls sideways
/// when the pane is too narrow instead of wrapping one chip onto a second
/// line. Shared by «اشتراكات المناديب» and «طلبات السلاسل» so both tabs
/// look the same.
class SubscriptionFilterChipRow<T> extends StatelessWidget {
  const SubscriptionFilterChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.countStyle,
  });

  final List<SubscriptionFilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;

  /// Style for the count after the label (the page uses its number face).
  final TextStyle? Function(TextStyle? base)? countStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelLarge;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _chip(cs, base, options[i]),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    ColorScheme cs,
    TextStyle? base,
    SubscriptionFilterOption<T> option,
  ) {
    final isSelected = selected == option.value;
    return FilterChip(
      key: option.key,
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: option.label),
            TextSpan(
              text: ' ${option.count}',
              style: countStyle?.call(base) ?? base,
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      ),
      selected: isSelected,
      showCheckmark: true,
      checkmarkColor: cs.onSecondaryContainer,
      selectedColor: cs.secondaryContainer,
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide(color: cs.outlineVariant),
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: base?.copyWith(
        color: isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onSelected(option.value),
    );
  }
}
