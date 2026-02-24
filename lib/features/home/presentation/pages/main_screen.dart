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

  /// Tracks which tabs have been visited so we only build them once.
  final Set<int> _initializedTabs = {0}; // Tab 0 (Attendance) loads first

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

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
      body: _buildBody(delegate),
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
              _initializedTabs.add(index); // Mark tab as visited
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

  /// Lazy-builds tabs: only creates a tab widget when it's first visited,
  /// then keeps it alive via IndexedStack so it isn't destroyed on tab switch.
  Widget _buildBody(Delegate delegate) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        // Tab 0: Attendance (always initialized)
        AttendanceScreen(delegate: delegate),

        // Tab 1: Profile — only build if visited
        if (_initializedTabs.contains(1))
          ProfileScreen(delegate: delegate)
        else
          const SizedBox.shrink(),

        // Tab 2: Settings — only build if visited
        if (_initializedTabs.contains(2))
          SettingsScreen(delegate: delegate)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
