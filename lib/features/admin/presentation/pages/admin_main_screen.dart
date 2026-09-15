import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_payment_receipts_report_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_collections_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_branch_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_branches_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/create_admin_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_dashboard_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_admins_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_marketing_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
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

class AdminMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AdminMainScreen({super.key, required this.delegate});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
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
              ? l10n.supervisorUser(delegate.firstName)
              : _currentIndex == 1
              ? l10n.companyDelegates
              : _currentIndex == 2
              ? l10n.tasks
              : l10n.photoPermissions);

    return Scaffold(
      appBar: AdminHeader(
        title: headerTitle,
        subtitle: subtitle,
        actions: [
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
        ],
        menuItems: [
          const PopupMenuItem(
            value: 'profile',
            child: ListTile(
              leading: Icon(Icons.person_outline_rounded),
              title: Text('الملف الشخصي'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (isSuperAdmin ||
              isTechnicalSupport ||
              widget.delegate.role == UserRole.admin ||
              isOrganizationAdmin) ...[
            const PopupMenuItem(
              value: 'delegate_subscriptions',
              child: ListTile(
                leading: Icon(Icons.how_to_reg_rounded),
                title: Text('طلبات اشتراك واعتماد المناديب'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          if (isSuperAdmin || isTechnicalSupport) ...[
            const PopupMenuItem(
              value: 'anti_fraud',
              child: ListTile(
                leading: Icon(Icons.security_rounded),
                title: Text('كشف التزييف وربط الأجهزة'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'branches',
              child: ListTile(
                leading: Icon(Icons.storefront_rounded),
                title: Text('الفروع'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'add_branch',
              child: ListTile(
                leading: Icon(Icons.add_location_alt_rounded),
                title: Text('إضافة فرع'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (isSuperAdmin) ...[
              PopupMenuItem(
                value: 'create_admin',
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text(l10n.createAdmin),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            if (isTechnicalSupport) ...[
              const PopupMenuItem(
                value: 'photo_permissions',
                child: ListTile(
                  leading: Icon(Icons.photo_library_rounded),
                  title: Text('أذونات التصوير'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
              value: 'manage_marketing',
              child: ListTile(
                leading: const Icon(Icons.campaign_rounded),
                title: Text(l10n.manageMarketing),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'manage_feedbacks',
              child: ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('إدارة المقترحات'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (isTechnicalSupport) ...[
              PopupMenuItem(
                value: 'send_notification',
                child: ListTile(
                  leading: const Icon(Icons.send_rounded),
                  title: const Text('إرسال إشعار جديد'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            if (delegate.role != UserRole.technicalSupport) ...[
              PopupMenuItem(
                value: 'permissions_report',
                child: ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('تقرير أذونات التصوير'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'receipts_report',
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: Text(l10n.receiptsReport),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'collections',
                child: ListTile(
                  leading: Icon(Icons.request_quote_rounded),
                  title: Text('التحصيلات والفواتير'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],

          if (isBranchesMarketingManager) ...[
            PopupMenuItem(
              value: 'tasks',
              child: ListTile(
                leading: const Icon(Icons.task_alt_rounded),
                title: Text(isArabic ? 'إدارة المهام' : 'Tasks Management'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'search',
              child: ListTile(
                leading: const Icon(Icons.person_search_rounded),
                title: Text(isArabic ? 'الاستعلامات والبحث' : 'Search'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],

          // نظام الغرامات في القائمة للأدوار التي لا تملكه كتبويب سفلي مباشر
          if (!isOrganizationAdmin && !isSuperAdmin && !isBranchesMarketingManager) ...[
            const PopupMenuItem(
              value: 'penalties_management',
              child: ListTile(
                leading: Icon(Icons.gavel_rounded),
                title: Text('نظام الغرامات والمخالفات'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],

          // الإعدادات دائماً في أسفل القائمة
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
      body: IndexedStack(index: _currentIndex, children: _screens),
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
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.security_outlined),
                  selectedIcon: const Icon(Icons.security_rounded),
                  label: isArabic ? 'كشف التزييف' : 'Anti-Fraud',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.campaign_outlined),
                  selectedIcon: const Icon(Icons.campaign_rounded),
                  label: isArabic ? 'إرسال إشعار' : 'Notification',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.gavel_outlined),
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
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.security_outlined),
                  selectedIcon: const Icon(Icons.security_rounded),
                  label: isArabic ? 'كشف التزييف' : 'Anti-Fraud',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.campaign_outlined),
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
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.task_alt_outlined),
                  selectedIcon: const Icon(Icons.task_alt_rounded),
                  label: l10n.tasks,
                ),
                const NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.gavel_outlined),
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
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: isArabic ? 'الرئيسية' : 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.store_outlined),
                  selectedIcon: const Icon(Icons.store_rounded),
                  label: isArabic ? 'الفروع' : 'Branches',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.gavel_outlined),
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
                NavigationDestination(
                  icon: const Icon(Icons.collections_outlined),
                  selectedIcon: const Icon(Icons.collections_rounded),
                  label: l10n.photoPermissions,
                ),
              ],
            ),
    );
  }
}
