import 'package:flutter/material.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_companies_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class MarketingMainScreen extends StatefulWidget {
  final Delegate delegate;

  const MarketingMainScreen({super.key, required this.delegate});

  @override
  State<MarketingMainScreen> createState() => _MarketingMainScreenState();
}

class _MarketingMainScreenState extends State<MarketingMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

    final screens = [
      MarketingCompaniesScreen(organizationUID: delegate.organizationUID),
      MarketingSearchScreen(organizationUID: delegate.organizationUID),
      SettingsScreen(delegate: delegate),
    ];

    final subtitle = _currentIndex == 0
        ? l10n.companies
        : _currentIndex == 1
        ? l10n.search
        : l10n.settings;

    return Scaffold(
      appBar: AdminHeader(
        subtitle: subtitle,
        userName: delegate.fullName, // ✅ تمرير اسم المستخدم
        // Optional menu items can go here
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront_rounded),
            label: l10n.companies,
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search_rounded),
            label: l10n.search,
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
