import 'package:flutter/material.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class MainScreen extends StatefulWidget {
  final Delegate delegate;

  const MainScreen({super.key, required this.delegate});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

    final screens = [
      AttendanceScreen(delegate: delegate),
      ProfileScreen(delegate: delegate),
      SettingsScreen(delegate: delegate),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(
                delegate.firstName.isNotEmpty
                    ? delegate.firstName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.helloUser(delegate.firstName),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.delegateRole,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
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
              icon: const Icon(Icons.access_time_filled),
              label: l10n.attendance,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person),
              label: l10n.profile,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.menu_rounded),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }
}
