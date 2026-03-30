import 'package:flutter/material.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_branch_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_branches_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/create_admin_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_admins_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class AdminMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AdminMainScreen({super.key, required this.delegate});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;

  void _onMenuSelected(String value) {
    switch (value) {
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(delegate: widget.delegate),
          ),
        );
        break;
      case 'manage_admins':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManageAdminsScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final isSuperAdmin = delegate.role == UserRole.superAdmin;

    final screens = isSuperAdmin
        ? [
            const AdminBranchesScreen(),
            const AddBranchScreen(),
            const CreateAdminScreen(),
          ]
        : [
            AdminHomeScreen(adminDelegate: delegate),
            AdminDelegatesScreen(adminDelegate: delegate),
            AdminTasksScreen(adminDelegate: delegate),
          ];

    final subtitle = isSuperAdmin
        ? (_currentIndex == 0
              ? l10n.helloUser(delegate.firstName)
              : _currentIndex == 1
              ? l10n.addBranch
              : l10n.createAdmin)
        : (_currentIndex == 0
              ? l10n.helloUser(delegate.firstName)
              : _currentIndex == 1
              ? l10n.companyDelegates
              : l10n.tasks);

    return Scaffold(
      appBar: AdminHeader(
        subtitle: subtitle,
        menuItems: [
          if (isSuperAdmin)
            PopupMenuItem(
              value: 'manage_admins',
              child: ListTile(
                leading: const Icon(Icons.group_rounded),
                title: Text(l10n.manageAdmins),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: Text(l10n.settings),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
        onMenuSelected: _onMenuSelected,
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: isSuperAdmin
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.storefront_rounded),
                  label: l10n.branches,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: l10n.addBranch,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: l10n.createAdmin,
                ),
              ],
            )
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.people_outline_rounded),
                  selectedIcon: const Icon(Icons.people_rounded),
                  label: l10n.companyDelegates,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.task_alt_outlined),
                  selectedIcon: const Icon(Icons.task_alt_rounded),
                  label: l10n.tasks,
                ),
              ],
            ),
    );
  }
}
