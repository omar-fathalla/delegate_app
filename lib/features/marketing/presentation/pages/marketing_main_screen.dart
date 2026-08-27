import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_home_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_home_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

// Photo Permission Imports
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/delegate_tasks_screen.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
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
    final delegate = widget.delegate;
    final isPromotionOnly = delegate.role == UserRole.marketingPromotion;

    switch (value) {
      case 'search':
        if (isPromotionOnly) break;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketingSearchScreen(
              organizationUID: delegate.organizationUID,
            ),
          ),
        );
        break;
      case 'tasks':
        if (isPromotionOnly) break;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => isPromotionOnly
                ? AdminTasksScreen(adminDelegate: delegate)
                : BlocProvider(
                    create: (_) => di.sl<DelegateTasksBloc>(),
                    child: DelegateTasksScreen(delegate: delegate),
                  ),
          ),
        );
        break;
      case 'penalties':
        if (isPromotionOnly) break;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PenaltyBloc>()
                ..add(LoadCompanyPenaltiesEvent(widget.delegate.companyUID)),
              child: CompanyPenaltiesSettingsPage(
                delegate: widget.delegate,
                showAppBar: true,
              ),
            ),
          ),
        );
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              delegate: widget.delegate,
              showAppBar: true,
            ),
          ),
        );
        break;
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
            AdminTasksScreen(adminDelegate: delegate),
          ]
        : [
            MarketingHomeScreen(
              delegate: delegate,
              onNavigateTab: (tabIndex) {
                setState(() => _currentIndex = tabIndex);
              },
            ),
            BranchHomeScreen(marketingUser: delegate),
            BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: MarketingPermissionsScreen(marketingDelegate: delegate),
            ),
            BlocProvider(
              create: (_) => di.sl<PenaltyBloc>(),
              child: CompanyPenaltiesSettingsPage(
                delegate: delegate,
                showAppBar: false,
              ),
            ),
          ];

    final String subtitle;
    if (isPromotionOnly) {
      subtitle = _currentIndex == 0 ? 'أذونات التصوير' : 'المهام';
    } else {
      switch (_currentIndex) {
        case 0:
          subtitle = 'الرئيسية';
          break;
        case 1:
          subtitle = 'الفروع ومتابعة الحضور';
          break;
        case 2:
          subtitle = 'أذونات التصوير';
          break;
        case 3:
          subtitle = 'قسم الغرامات والمخالفات';
          break;
        default:
          subtitle = 'تسويق الفروع';
      }
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
          // 1. زر الإشعارات
          BlocProvider(
            create: (_) => di.sl<NotificationBloc>()
              ..add(
                SubscribeToUnreadCount(
                  delegateUid: delegate.uid,
                  organizationId: delegate.organizationUID,
                  phoneNumber: delegate.phoneNumber,
                ),
              ),
            child: BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                final unreadCount = state is NotificationLoaded
                    ? state.unreadCount
                    : 0;

                return Badge(
                  label: Text('$unreadCount'),
                  isLabelVisible: unreadCount > 0,
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: l10n.notifications,
                    onPressed: () {
                      context.push('/notifications', extra: delegate);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),

          // 2. المنيو العلوي (البحث، المهام، الإعدادات، الملف الشخصي)
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              if (!isPromotionOnly)
                PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                    leading: const Icon(Icons.search_rounded),
                    title: Text(l10n.search),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!isPromotionOnly)
                PopupMenuItem(
                  value: 'tasks',
                  child: ListTile(
                    leading: const Icon(Icons.task_alt_rounded),
                    title: Text(l10n.tasks),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!isPromotionOnly)
                PopupMenuItem(
                  value: 'penalties',
                  child: ListTile(
                    leading: Icon(Icons.gavel_rounded, color: colorScheme.error),
                    title: const Text('المخالفات والغرامات'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l10n.settings),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                NavigationDestination(
                  icon: Icon(Icons.task_alt_outlined),
                  selectedIcon: Icon(Icons.task_alt_rounded),
                  label: 'المهام',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'الرئيسية',
                ),
                NavigationDestination(
                  icon: Icon(Icons.store_outlined),
                  selectedIcon: Icon(Icons.store_rounded),
                  label: 'الفروع',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                NavigationDestination(
                  icon: Icon(Icons.gavel_outlined),
                  selectedIcon: Icon(Icons.gavel_rounded),
                  label: 'الغرامات',
                ),
              ],
      ),
    );
  }
}
