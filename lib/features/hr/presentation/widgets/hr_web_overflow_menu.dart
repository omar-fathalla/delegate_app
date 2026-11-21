import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// Narrow web overflow menu for the HR shell.
///
/// Material elevation draws a hard edge on this renderer, so the panel is a
/// transparent menu with a soft level-2 blur, the same approach as the web
/// header account popover. Corner radius is the M3 menu token (4).
class HrWebOverflowMenu extends StatelessWidget {
  final Delegate delegate;
  final int currentIndex;
  final ValueChanged<String> onSelected;

  /// Wraps an icon when the item has a live count. Null leaves the icon as is.
  final Widget Function(HrShellItem item, Widget icon)? wrapIcon;

  /// Trailing widget beside the label, such as a pending count (M3 menu
  /// badge, TAS-154). Null shows nothing.
  final Widget? Function(HrShellItem item)? trailingFor;

  const HrWebOverflowMenu({
    super.key,
    required this.delegate,
    required this.currentIndex,
    required this.onSelected,
    this.wrapIcon,
    this.trailingFor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final sections = _sections();
    final available = MediaQuery.sizeOf(context).width - 32;
    final menuWidth = available < 280 ? available : 280.0;

    return MenuAnchor(
      // The overlay clamps flush to the window. The shell stays transparent
      // and the visible surface sits inside it, so the blur is not clipped.
      clipBehavior: Clip.none,
      reservedPadding: const EdgeInsets.all(8),
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide.none),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(side: BorderSide.none),
        ),
      ),
      builder: (context, controller, child) {
        return IconButton(
          tooltip: l10n?.mainMenu ?? 'القائمة الرئيسية',
          icon: const Icon(Symbols.menu_rounded),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            key: const ValueKey('hr_web_overflow_panel'),
            width: menuWidth,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(4),
              // M3 level 2. Painted as a blur, not Material elevation, because
              // elevation leaves a hard edge on this renderer.
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.30),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 6,
                  spreadRadius: 2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    // The divider under «الرئيسية» repeats the first item.
                    if (i > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          6,
                          8,
                          6,
                        ),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                    for (final item in sections[i])
                      _item(context, colorScheme, item),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Drawer group order: a section is created the first time it appears, and
  /// later items of that section join it. Profile and settings stay, each in
  /// their own group.
  List<List<HrShellItem>> _sections() {
    final order = <String>[];
    final grouped = <String, List<HrShellItem>>{};
    for (final item in hrShellItems(
      delegate: delegate,
      isWeb: true,
      placement: HrShellPlacement.compactMenu,
    )) {
      final bucket = grouped.putIfAbsent(item.section, () {
        order.add(item.section);
        return [];
      });
      bucket.add(item);
    }
    return [for (final name in order) grouped[name]!];
  }

  Widget _item(
    BuildContext context,
    ColorScheme colorScheme,
    HrShellItem item,
  ) {
    final selected = item.tabIndex != null && item.tabIndex == currentIndex;
    final labelColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final iconColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final icon = Icon(
      selected ? item.selectedIcon : item.icon,
      size: 20,
      color: iconColor,
    );
    return MenuItemButton(
      key: ValueKey('hr_web_overflow_${item.id}'),
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          selected ? colorScheme.secondaryContainer : Colors.transparent,
        ),
        foregroundColor: WidgetStatePropertyAll(labelColor),
        iconColor: WidgetStatePropertyAll(iconColor),
        overlayColor: WidgetStatePropertyAll(
          colorScheme.onSurface.withValues(alpha: 0.06),
        ),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      leadingIcon: wrapIcon?.call(item, icon) ?? icon,
      trailingIcon: trailingFor?.call(item),
      onPressed: () => onSelected(item.id),
      child: Text(
        item.menuLabel(isWeb: true),
        style: TextStyle(
          fontSize: HrFont.body,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: labelColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
