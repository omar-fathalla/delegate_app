import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_home_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_promotion_home_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_home_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
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
import 'dart:async';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/presentation/pages/user_wallet_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingMainScreen extends StatefulWidget {
  final Delegate delegate;

  const MarketingMainScreen({super.key, required this.delegate});

  @override
  State<MarketingMainScreen> createState() => _MarketingMainScreenState();
}

class _MarketingMainScreenState extends State<MarketingMainScreen> {
  int _currentIndex = 0;
  StreamSubscription? _walletSubscription;
  bool _isWalletEnabled = false;

  @override
  void initState() {
    super.initState();
    _walletSubscription = WalletRemoteDataSourceImpl()
        .streamUserWallet(widget.delegate.uid)
        .listen((w) {
      if (mounted) {
        setState(() {
          _isWalletEnabled = w?.isWalletEnabled ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    _walletSubscription?.cancel();
    super.dispose();
  }

  void _onMenuSelected(String value) {
    final delegate = widget.delegate;
    final isPromotionOnly = delegate.role == UserRole.marketingPromotion;

    switch (value) {
      case 'wallet':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserWalletScreen(
              targetUserId: delegate.uid,
              targetUserName: delegate.fullName.isNotEmpty
                  ? delegate.fullName
                  : delegate.firstName,
            ),
          ),
        );
        break;
      case 'profile':
        context.push('/user-profile', extra: delegate);
        break;
      case 'search':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketingSearchScreen(
              organizationUID: delegate.organizationUID,
            ),
          ),
        );
        break;
      case 'photo_report':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: MonthlyPhotoReportScreen(
                delegate: delegate,
                showAppBar: true,
              ),
            ),
          ),
        );
        break;
      case 'tasks':
        if (isPromotionOnly) {
          setState(() => _currentIndex = 2);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider(
                create: (_) => di.sl<DelegateTasksBloc>(),
                child: DelegateTasksScreen(delegate: delegate),
              ),
            ),
          );
        }
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
      case 'logout':
        _showLogoutDialog(context);
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
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: colorScheme.error, size: 24),
            const SizedBox(width: 8),
            Text(l10n.logout),
          ],
        ),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.go('/login');
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final colorScheme = Theme.of(context).colorScheme;

    final isPromotionOnly = delegate.role == UserRole.marketingPromotion;

    final screens = isPromotionOnly
        ? [
            MarketingPromotionHomeScreen(
              delegate: delegate,
              onNavigateTab: (tabIndex) {
                setState(() => _currentIndex = tabIndex);
              },
            ),
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

    PopupMenuItem<String> buildPopupItem({
      required String value,
      required IconData icon,
      required String title,
      Color? color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: UniversalAppHeader(
        delegate: delegate,
        extraActions: [
          // 1. زر الإشعارات
          BlocProvider(
            create: (_) => di.sl<NotificationBloc>()
              ..add(
                SubscribeToUnreadCount(
                  delegateUid: delegate.uid,
                  organizationId: delegate.organizationUID,
                  phoneNumber: delegate.phoneNumber,
                  userRole: delegate.role.name,
                  accountCreatedAt: delegate.createdAt,
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
                    icon: const Icon(Icons.notifications_rounded),
                    tooltip: l10n.notifications,
                    onPressed: () {
                      context.push('/notifications', extra: delegate);
                    },
                  ),
                );
              },
            ),
          ),
        ],
        onMenuSelected: _onMenuSelected,
        menuItems: [
          buildPopupItem(
            value: 'profile',
            icon: Icons.person_rounded,
            title: 'الملف الشخصي',
          ),
          buildPopupItem(
            value: 'search',
            icon: Icons.search_rounded,
            title: l10n.search,
          ),
          if (isPromotionOnly)
            buildPopupItem(
              value: 'photo_report',
              icon: Icons.collections_rounded,
              title: 'تقارير الصور الميدانية',
            ),
          if (!isPromotionOnly)
            buildPopupItem(
              value: 'tasks',
              icon: Icons.task_alt_rounded,
              title: l10n.tasks,
            ),
          if (!isPromotionOnly)
            buildPopupItem(
              value: 'penalties',
              icon: Icons.gavel_rounded,
              title: 'المخالفات والغرامات',
              color: colorScheme.error,
            ),
          if (_isWalletEnabled)
            buildPopupItem(
              value: 'wallet',
              icon: Icons.account_balance_wallet_rounded,
              title: 'المحفظة والمستحقات',
              color: colorScheme.primary,
            ),
          buildPopupItem(
            value: 'logout',
            icon: Icons.logout_rounded,
            title: l10n.logout,
            color: colorScheme.error,
          ),
          const PopupMenuDivider(),
          // الإعدادات دائماً في أسفل القائمة
          buildPopupItem(
            value: 'settings',
            icon: Icons.settings_rounded,
            title: l10n.settings,
          ),
        ],
      ),
      body: M3FadeThroughIndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: colorScheme.surfaceContainer,
          elevation: 0,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: isPromotionOnly
              ? const [
                  NavigationDestination(
                    icon: Icon(Icons.home_rounded),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'الرئيسية',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.photo_library_rounded),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'أذونات التصوير',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.task_alt_rounded),
                    selectedIcon: Icon(Icons.task_alt_rounded),
                    label: 'المهام',
                  ),
                ]
              : const [
                  NavigationDestination(
                    icon: Icon(Icons.home_rounded),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'الرئيسية',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.store_rounded),
                    selectedIcon: Icon(Icons.store_rounded),
                    label: 'الفروع',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.photo_library_rounded),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'أذونات التصوير',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.gavel_rounded),
                    selectedIcon: Icon(Icons.gavel_rounded),
                    label: 'الغرامات',
                  ),
                ],
        ),
      ),
    );
  }
}
