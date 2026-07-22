import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_home_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

// Photo Permission Imports
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingMainScreen extends StatefulWidget {
  final Delegate delegate;

  const MarketingMainScreen({super.key, required this.delegate});

  @override
  State<MarketingMainScreen> createState() => _MarketingMainScreenState();
}

class _MarketingMainScreenState extends State<MarketingMainScreen> {
  int _currentIndex = 0;

  void _onMenuSelected(String value) {
    switch (value) {
      case 'profile':
        context.push('/user-profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final colorScheme = Theme.of(context).colorScheme;

    final isPromotionOnly = delegate.role == UserRole.marketingPromotion;

    final screens = isPromotionOnly
        ? [
            BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: MarketingPermissionsScreen(marketingDelegate: delegate),
            ),
            SettingsScreen(delegate: delegate),
          ]
        : [
            BranchHomeScreen(marketingUser: delegate),
            MarketingSearchScreen(organizationUID: delegate.organizationUID),
            BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: MarketingPermissionsScreen(marketingDelegate: delegate),
            ),
            SettingsScreen(delegate: delegate),
          ];

    final String subtitle;
    if (isPromotionOnly) {
      subtitle = _currentIndex == 0 ? 'أذونات التصوير' : l10n.settings;
    } else {
      subtitle = _currentIndex == 0
          ? 'الفروع'
          : _currentIndex == 1
          ? l10n.search
          : _currentIndex == 2
          ? 'أذونات التصوير'
          : l10n.settings;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        scrolledUnderElevation: 3.0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              delegate.fullName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline_rounded),
                  title: Text('الملف الشخصي'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: isPromotionOnly
            ? [
                const NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: l10n.settings,
                ),
              ]
            : [
                const NavigationDestination(
                  icon: Icon(Icons.store_outlined),
                  selectedIcon: Icon(Icons.store_rounded),
                  label: 'الفروع',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.search_outlined),
                  selectedIcon: const Icon(Icons.search_rounded),
                  label: l10n.search,
                ),
                const NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: l10n.settings,
                ),
              ],
      ),
    );
  }
}
