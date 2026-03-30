import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class AdminHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<PopupMenuEntry<String>>? menuItems;
  final ValueChanged<String>? onMenuSelected;

  const AdminHeader({
    super.key,
    this.subtitle,
    this.showBackButton = false,
    this.onBackPressed,
    this.menuItems,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      scrolledUnderElevation: 3.0,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.admin,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: [
        if (menuItems != null && menuItems!.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: onMenuSelected,
            itemBuilder: (_) => menuItems!,
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
