import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_payment_receipts_report_screen.dart';
import 'dart:async';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_collections_screen.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/presentation/pages/super_admin_wallets_screen.dart';
import 'package:delegate_app/features/wallet/presentation/pages/user_wallet_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_branch_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_branches_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/create_admin_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_dashboard_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_admins_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_marketing_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/pages/admin_feedbacks_screen.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branches_marketing_home_screen.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_session_control_screen.dart';

class AdminMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AdminMainScreen({super.key, required this.delegate});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  StreamSubscription? _walletSubscription;
  bool _isWalletEnabled = false;

  @override
  void initState() {
    super.initState();
    _walletSubscription = WalletRemoteDataSourceImpl()
        .streamUserWallet(widget.delegate.uid)
        .listen(
      (w) {
        if (mounted) {
          setState(() {
            _isWalletEnabled = w?.isWalletEnabled ?? false;
          });
        }
      },
      onError: (e) {
        debugPrint('Wallet stream error: $e');
      },
    );
    final delegate = widget.delegate;
    if (isSuperAdmin) {
      _screens = [
        SuperAdminDashboardScreen(
          delegate: delegate,
          onNavigateToBranches: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminBranchesScreen(showAppBar: true)),
          ),
          onNavigateToAddBranch: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddBranchScreen(showAppBar: true)),
          ),
          onNavigateToCreateAdmin: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateAdminScreen(
                organizationUID: delegate.organizationUID,
                currentDelegate: delegate,
                currentUserRole: delegate.role,
              ),
            ),
          ),
          onNavigateToSendNotification: () => setState(() => _currentIndex = 2),
        ),
        // 2. كشف التزييف وسجل الأمان
        AntiFraudAuditScreen(delegate: delegate),
        // 3. إرسال إشعار
        SendNotificationScreen(senderDelegate: delegate, showAppBar: false),
        // 4. منظومة الغرامات والمخالفات
        BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: AdminPenaltiesListPage(adminDelegate: delegate, showAppBar: false),
        ),
      ];
    } else if (isTechnicalSupport) {
      _screens = [
        SuperAdminDashboardScreen(
          delegate: delegate,
          onNavigateToBranches: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminBranchesScreen(showAppBar: true)),
          ),
          onNavigateToAddBranch: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddBranchScreen(showAppBar: true)),
          ),
          onNavigateToCreateAdmin: () => setState(() => _currentIndex = 3),
          onNavigateToSendNotification: () => setState(() => _currentIndex = 2),
          onNavigateToAntiFraud: () => setState(() => _currentIndex = 1),
        ),
        // 1. كشف التزييف وسجل الأمان وربط الأجهزة
        AntiFraudAuditScreen(delegate: delegate),
        // 2. إرسال إشعار
        SendNotificationScreen(senderDelegate: delegate, showAppBar: false),
        // 3. إنشاء أدمن
        CreateAdminScreen(
          organizationUID: delegate.organizationUID,
          currentDelegate: delegate,
          currentUserRole: delegate.role,
          showAppBar: false,
          onBack: () => setState(() => _currentIndex = 0),
        ),
      ];
    } else if (isBranchesMarketingManager) {
      _screens = [
        BranchesMarketingHomeScreen(
          delegate: delegate,
          onNavigateTab: (tabIndex) => setState(() => _currentIndex = tabIndex),
        ),
        BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>()
            ..add(const LoadPermissionsRequested(
              organizationUID: '',
              companyUID: '',
            )),
          child: MarketingPermissionsScreen(marketingDelegate: delegate),
        ),
        BranchHomeScreen(marketingUser: delegate),
        BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: CompanyPenaltiesSettingsPage(delegate: delegate),
        ),
      ];
    } else if (isOrganizationAdmin) {
      _screens = [
        AdminHomeScreen(adminDelegate: delegate),
        AdminTasksScreen(adminDelegate: delegate),
        // تبويب أذونات التصوير
        BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>()
            ..add(const LoadPermissionsRequested(
              organizationUID: '',
              companyUID: '',
            )),
          child: MarketingPermissionsScreen(marketingDelegate: delegate),
        ),
        // تبويب المخالفات والغرامات (قراءة + إضافة لمشرف الشركات)
        BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: CompanyPenaltiesSettingsPage(delegate: delegate),
        ),
      ];
    } else {
      _screens = [
        AdminHomeScreen(adminDelegate: delegate),
        AdminDelegatesScreen(adminDelegate: delegate),
        AdminTasksScreen(adminDelegate: delegate),
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => di.sl<PhotoPermissionBloc>()),
            BlocProvider(create: (_) => di.sl<BranchBloc>()),
          ],
          child: SupervisorPermissionsScreen(
            supervisorDelegate: delegate,
            showAppBar: false,
          ),
        ),
      ];
    }
  }

  @override
  void dispose() {
    _walletSubscription?.cancel();
    super.dispose();
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'anti_fraud':
        if (isSuperAdmin || isTechnicalSupport) {
          setState(() => _currentIndex = 1);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AntiFraudAuditScreen(
                delegate: widget.delegate,
                showAppBar: true,
              ),
            ),
          );
        }
        break;
      case 'branches':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminBranchesScreen(showAppBar: true)),
        );
        break;
      case 'add_branch':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddBranchScreen(showAppBar: true)),
        );
        break;
      case 'branch_attendance':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BranchHomeScreen(
              marketingUser: widget.delegate,
              showAppBar: true,
            ),
          ),
        );
        break;
      case 'create_admin':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateAdminScreen(
              organizationUID: widget.delegate.organizationUID,
              currentDelegate: widget.delegate,
              currentUserRole: widget.delegate.role,
            ),
          ),
        );
        break;
      case 'delegate_subscriptions':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DelegateSubscriptionRequestsPage(
              currentAdmin: widget.delegate,
            ),
          ),
        );
        break;
      case 'photo_permissions':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>()
                ..add(const LoadPermissionsRequested(
                  organizationUID: '',
                  companyUID: '',
                )),
              child: MarketingPermissionsScreen(marketingDelegate: widget.delegate),
            ),
          ),
        );
        break;
      case 'session_control':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SuperAdminSessionControlScreen(
              adminDelegate: widget.delegate,
            ),
          ),
        );
        break;
      case 'manage_admins':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManageAdminsScreen()));
        break;
      case 'manage_marketing':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManageMarketingScreen()));
        break;
      case 'manage_feedbacks':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<AdminFeedbackBloc>(),
              child: const AdminFeedbacksScreen(),
            ),
          ),
        );
        break;
      case 'send_notification':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SendNotificationScreen(senderDelegate: widget.delegate),
          ),
        );
        break;
      case 'permissions_report':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: SuperAdminPermissionsReportScreen(delegate: widget.delegate),
            ),
          ),
        );
        break;
      case 'receipts_report':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
          ),
        );
        break;
      case 'collections':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SuperAdminCollectionsScreen(delegate: widget.delegate),
          ),
        );
        break;
      case 'wallets_management':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SuperAdminWalletsScreen(adminDelegate: widget.delegate),
          ),
        );
        break;
      case 'user_wallet':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserWalletScreen(
              targetUserId: widget.delegate.uid,
              targetUserName: widget.delegate.fullName.isNotEmpty
                  ? widget.delegate.fullName
                  : widget.delegate.firstName,
            ),
          ),
        );
        break;
      case 'penalties_management':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PenaltyBloc>(),
              child: AdminPenaltiesListPage(adminDelegate: widget.delegate),
            ),
          ),
        );
        break;
      case 'penalty_rules_catalog':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PenaltyRulesCatalogPage(currentDelegate: widget.delegate),
          ),
        );
        break;
      case 'tasks':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminTasksScreen(adminDelegate: widget.delegate),
          ),
        );
        break;
      case 'search':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarketingSearchScreen(
              organizationUID: widget.delegate.organizationUID,
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
      case 'profile':
        context.push('/user-profile', extra: widget.delegate);
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
              'إلغاء',
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

  bool get isSuperAdmin => widget.delegate.role == UserRole.superAdmin;
  bool get isTechnicalSupport => widget.delegate.role == UserRole.technicalSupport;
  bool get isOrganizationAdmin =>
      widget.delegate.role == UserRole.organizationAdmin;
  bool get isBranchesMarketingManager =>
      widget.delegate.role == UserRole.branchesMarketingManager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final headerTitle = delegate.role == UserRole.technicalSupport
        ? (isArabic ? 'الدعم الفني' : 'Technical Support')
        : isBranchesMarketingManager
        ? (isArabic ? 'مدير تسويق الفروع' : 'Branches Marketing Manager')
        : (isSuperAdmin ? null : delegate.companyName);

    final subtitle = isSuperAdmin
        ? (_currentIndex == 0
              ? l10n.home
              : _currentIndex == 1
              ? (isArabic ? 'كشف التزييف وسجل الأمان' : 'Anti-Fraud & Security Audit')
              : _currentIndex == 2
              ? (isArabic ? 'إرسال إشعار' : 'Send Notification')
              : (isArabic ? 'سجل المخالفات والغرامات' : 'Penalties Management'))
        : isTechnicalSupport
        ? (_currentIndex == 0
              ? l10n.home
              : _currentIndex == 1
              ? (isArabic ? 'كشف التزييف وسجل الأمان' : 'Anti-Fraud & Security Audit')
              : _currentIndex == 2
              ? (isArabic ? 'إرسال إشعار' : 'Send Notification')
              : l10n.createAdmin)
        : isOrganizationAdmin
        ? (_currentIndex == 0
              ? delegate.firstName
              : _currentIndex == 1
              ? l10n.tasks
              : _currentIndex == 2
              ? 'أذونات التصوير'
              : 'المخالفات والغرامات')
        : isBranchesMarketingManager
        ? (_currentIndex == 0
              ? (isArabic ? 'الرئيسية' : 'Home')
              : _currentIndex == 1
              ? (isArabic ? 'أذونات التصوير' : 'Photo Permissions')
              : _currentIndex == 2
              ? (isArabic ? 'متابعة الفروع' : 'Branch Marketing')
              : (isArabic ? 'المخالفات والغرامات' : 'Penalties'))
        : (_currentIndex == 0
              ? (delegate.fullName.isNotEmpty ? delegate.fullName : delegate.firstName)
              : _currentIndex == 1
              ? l10n.companyDelegates
              : _currentIndex == 2
              ? l10n.tasks
              : l10n.photoPermissions);

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: UniversalAppHeader(
        delegate: delegate,
        customTitle: _currentIndex == 0 ? null : subtitle,
        customSubtitle: _currentIndex == 0
            ? null
            : (headerTitle != null && headerTitle != subtitle
                ? headerTitle
                : null),
        showBackButton: _currentIndex != 0,
        onBackPressed: () => setState(() => _currentIndex = 0),
        extraActions: [
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
          const SizedBox(width: 4),
        ],
        menuItems: [
          buildPopupItem(
            value: 'profile',
            icon: Icons.person_rounded,
            title: 'الملف الشخصي',
          ),
          if (isSuperAdmin ||
              isTechnicalSupport ||
              widget.delegate.role == UserRole.admin ||
              isOrganizationAdmin) ...[
            buildPopupItem(
              value: 'delegate_subscriptions',
              icon: Icons.how_to_reg_rounded,
              title: 'طلبات اشتراك واعتماد المناديب',
            ),
          ],
          if (isSuperAdmin || isTechnicalSupport) ...[
            buildPopupItem(
              value: 'anti_fraud',
              icon: Icons.security_rounded,
              title: 'كشف التزييف وربط الأجهزة',
            ),
            buildPopupItem(
              value: 'branches',
              icon: Icons.storefront_rounded,
              title: 'الفروع',
            ),
            buildPopupItem(
              value: 'branch_attendance',
              icon: Icons.co_present_rounded,
              title: 'متابعة حضور الفروع',
            ),
            if (isSuperAdmin) ...[
              buildPopupItem(
                value: 'session_control',
                icon: Icons.sync_lock_rounded,
                title: 'إدارة جلسات المناديب والخروج الإجباري',
              ),
              buildPopupItem(
                value: 'create_admin',
                icon: Icons.person_add_alt_1_rounded,
                title: l10n.createAdmin,
              ),
            ],
            if (isTechnicalSupport) ...[
              buildPopupItem(
                value: 'photo_permissions',
                icon: Icons.photo_library_rounded,
                title: 'أذونات التصوير',
              ),
            ],
            buildPopupItem(
              value: 'manage_admins',
              icon: Icons.group_rounded,
              title: l10n.manageAdmins,
            ),
            buildPopupItem(
              value: 'manage_marketing',
              icon: Icons.campaign_rounded,
              title: l10n.manageMarketing,
            ),
            buildPopupItem(
              value: 'manage_feedbacks',
              icon: Icons.feedback_rounded,
              title: 'إدارة المقترحات',
            ),
            if (isTechnicalSupport) ...[
              buildPopupItem(
                value: 'send_notification',
                icon: Icons.send_rounded,
                title: 'إرسال إشعار جديد',
              ),
            ],
            if (delegate.role != UserRole.technicalSupport) ...[
              buildPopupItem(
                value: 'permissions_report',
                icon: Icons.analytics_rounded,
                title: 'تقرير أذونات التصوير',
              ),
              buildPopupItem(
                value: 'receipts_report',
                icon: Icons.receipt_long_rounded,
                title: l10n.receiptsReport,
              ),
              buildPopupItem(
                value: 'collections',
                icon: Icons.request_quote_rounded,
                title: 'التحصيلات والفواتير',
              ),
              buildPopupItem(
                value: 'wallets_management',
                icon: Icons.account_balance_wallet_rounded,
                title: 'إدارة المحافظ والمستحقات',
              ),
            ],
          ],

          if (isBranchesMarketingManager) ...[
            buildPopupItem(
              value: 'tasks',
              icon: Icons.task_alt_rounded,
              title: isArabic ? 'إدارة المهام' : 'Tasks Management',
            ),
            buildPopupItem(
              value: 'search',
              icon: Icons.person_search_rounded,
              title: isArabic ? 'الاستعلامات والبحث' : 'Search',
            ),
          ],

          // نظام الغرامات في القائمة للأدوار التي لا تملكه كتبويب سفلي مباشر
          if (!isOrganizationAdmin && !isSuperAdmin && !isBranchesMarketingManager) ...[
            buildPopupItem(
              value: 'penalties_management',
              icon: Icons.gavel_rounded,
              title: 'نظام الغرامات والمخالفات',
            ),
          ],

          // لائحة الغرامات والجزاءات الرسمية
          buildPopupItem(
            value: 'penalty_rules_catalog',
            icon: Icons.menu_book_rounded,
            title: isArabic ? 'لائحة الغرامات والجزاءات' : 'Penalty Rules Catalog',
          ),

          if (_isWalletEnabled) ...[
            buildPopupItem(
              value: 'user_wallet',
              icon: Icons.account_balance_wallet_rounded,
              title: 'المحفظة والمستحقات',
            ),
          ],

          buildPopupItem(
            value: 'logout',
            icon: Icons.logout_rounded,
            title: l10n.logout,
            color: Theme.of(context).colorScheme.error,
          ),
          const PopupMenuDivider(),
          // الإعدادات دائماً في أسفل القائمة
          buildPopupItem(
            value: 'settings',
            icon: Icons.settings_rounded,
            title: l10n.settings,
          ),
        ],
        onMenuSelected: _onMenuSelected,
      ),
      body: M3FadeThroughIndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
        ),
        child: isSuperAdmin
            ? NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_rounded),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: l10n.home,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.security_rounded),
                    selectedIcon: const Icon(Icons.security_rounded),
                    label: isArabic ? 'كشف التزييف' : 'Anti-Fraud',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.campaign_rounded),
                    selectedIcon: const Icon(Icons.campaign_rounded),
                    label: isArabic ? 'إرسال إشعار' : 'Notification',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.gavel_rounded),
                    selectedIcon: const Icon(Icons.gavel_rounded),
                    label: isArabic ? 'الغرامات' : 'Penalties',
                  ),
                ],
              )
            : isTechnicalSupport
            ? NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_rounded),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: l10n.home,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.security_rounded),
                    selectedIcon: const Icon(Icons.security_rounded),
                    label: isArabic ? 'كشف التزييف' : 'Anti-Fraud',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.campaign_rounded),
                    selectedIcon: const Icon(Icons.campaign_rounded),
                    label: isArabic ? 'إرسال إشعار' : 'Notification',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                    selectedIcon: const Icon(Icons.admin_panel_settings_rounded),
                    label: l10n.createAdmin,
                  ),
                ],
              )
            : isOrganizationAdmin
            ? NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_rounded),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: l10n.home,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.task_alt_rounded),
                    selectedIcon: const Icon(Icons.task_alt_rounded),
                    label: l10n.tasks,
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.photo_library_rounded),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'أذونات التصوير',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.gavel_rounded),
                    selectedIcon: Icon(Icons.gavel_rounded),
                    label: 'الغرامات',
                  ),
                ],
              )
            : isBranchesMarketingManager
            ? NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_rounded),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: isArabic ? 'الرئيسية' : 'Home',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.photo_library_rounded),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'أذونات التصوير',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.store_rounded),
                    selectedIcon: const Icon(Icons.store_rounded),
                    label: isArabic ? 'الفروع' : 'Branches',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.gavel_rounded),
                    selectedIcon: Icon(Icons.gavel_rounded),
                    label: 'الغرامات',
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
                    icon: const Icon(Icons.home_rounded),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: l10n.home,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.people_rounded),
                    selectedIcon: const Icon(Icons.people_rounded),
                    label: l10n.companyDelegates,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.task_alt_rounded),
                    selectedIcon: const Icon(Icons.task_alt_rounded),
                    label: l10n.tasks,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.collections_rounded),
                    selectedIcon: const Icon(Icons.collections_rounded),
                    label: l10n.photoPermissions,
                  ),
                ],
              ),
      ),
    );
  }
}
