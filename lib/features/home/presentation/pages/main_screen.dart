import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_bloc.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_event.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_state.dart';
import 'package:delegate_app/features/changelog/presentation/widgets/whats_new_dialog.dart';
import 'package:delegate_app/injection_container.dart' as di;
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
    final colorScheme = Theme.of(context).colorScheme;

    return BlocProvider(
      create: (_) => di.sl<ChangelogBloc>()..add(CheckForNewUpdates()),
      child: BlocListener<ChangelogBloc, ChangelogState>(
        listener: (context, state) {
          if (state is ChangelogHasNewUpdates) {
            // Show the dialog after the frame is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              WhatsNewDialog.show(
                context,
                updates: state.updates,
                onDismiss: () {
                  context.read<ChangelogBloc>().add(DismissNewUpdates());
                },
              );
            });
          }
        },
        child: Scaffold(
          appBar: _currentIndex == 2
              ? null
              : AppBar(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                  surfaceTintColor: colorScheme.surfaceTint,
                  title: Row(
                    children: [
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
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          body: _buildBody(delegate),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
                _initializedTabs.add(index); // Mark tab as visited
              });
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.access_time_filled),
                label: l10n.attendance,
              ),
              NavigationDestination(
                icon: const Icon(Icons.person),
                label: l10n.profile,
              ),
              NavigationDestination(
                icon: const Icon(Icons.menu_rounded),
                label: l10n.settings,
              ),
            ],
          ),
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

