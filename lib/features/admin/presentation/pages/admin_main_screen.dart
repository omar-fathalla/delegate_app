import 'package:flutter/material.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_branch_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_branches_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class AdminMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AdminMainScreen({super.key, required this.delegate});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

    final screens = [
      const AdminBranchesScreen(),
      const AddBranchScreen(),
      SettingsScreen(delegate: delegate), // Reusing existing Settings Screen
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(
                    Icons.admin_panel_settings,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.admin,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.helloUser(delegate.firstName),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white.withValues(alpha: 0.6),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.storefront_rounded),
              label: l10n.branches,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.add_location_alt_rounded),
              label: l10n.addBranch,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_rounded),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }
}
