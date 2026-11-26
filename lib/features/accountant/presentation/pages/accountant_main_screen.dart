import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_subscription_financial_report_screen.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'accountant_beneficiary_wallets_tab.dart';

class AccountantMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AccountantMainScreen({super.key, required this.delegate});

  @override
  State<AccountantMainScreen> createState() => _AccountantMainScreenState();
}

class _AccountantMainScreenState extends State<AccountantMainScreen> {
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {0};

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onMenuSelected(String value) {
    final delegate = widget.delegate;

    switch (value) {
      case 'profile':
        context.push('/user-profile', extra: delegate);
        break;
      case 'logout':
        _showLogoutDialog(context);
        break;
      case 'settings':
        // Policy: Settings MUST always be the last item in the menu
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              delegate: delegate,
              showAppBar: true,
            ),
          ),
        );
        break;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    AppLogoutModal.show(context, delegate: widget.delegate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final delegate = widget.delegate;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: UniversalAppHeader(
        delegate: delegate,
        onMenuSelected: _onMenuSelected,
        menuItems: [
          PopupMenuItem(
            value: 'profile',
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, color: colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Text(l10n.profile),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, color: colorScheme.error, size: 20),
                const SizedBox(width: 12),
                Text(l10n.logout, style: TextStyle(color: colorScheme.error)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          // Rule: Settings MUST ALWAYS BE THE LAST ITEM in the menu
          PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 12),
                Text(l10n.settings),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _AccountantOverviewTab(
            delegate: delegate,
            onNavigateToTab: _onTabSelected,
          ),
          _loadedTabs.contains(1)
              ? SuperAdminSubscriptionFinancialReportScreen(adminDelegate: delegate)
              : const SizedBox.shrink(),
          _loadedTabs.contains(2)
              ? AccountantBeneficiaryWalletsTab(accountantDelegate: delegate)
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: const Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: const Icon(Icons.pie_chart_rounded),
            label: l10n.financialReports,
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'المحفظة',
          ),
        ],
      ),
    );
  }
}

/// تاب النظرة العامة والكروت السريعة للعمليات المالية
class _AccountantOverviewTab extends StatefulWidget {
  final Delegate delegate;
  final ValueChanged<int> onNavigateToTab;

  const _AccountantOverviewTab({
    required this.delegate,
    required this.onNavigateToTab,
  });

  @override
  State<_AccountantOverviewTab> createState() => _AccountantOverviewTabState();
}

class _AccountantOverviewTabState extends State<_AccountantOverviewTab> {
  final WalletRemoteDataSource _dataSource = WalletRemoteDataSourceImpl();
  late final Stream<List<UserWalletModel>> _walletsStream;
  late final Stream<CollectionsRemainingMetrics> _collectionsStream;

  @override
  void initState() {
    super.initState();
    _walletsStream = _dataSource.streamAllWallets();
    _collectionsStream = _dataSource.streamCollectionsRemainingMetrics();
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(amount)} ج.م';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final formattedDate = DateFormat.yMMMMd('ar').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 300));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ترويسة الترحيب المالي السريعة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مرحباً بك، ${widget.delegate.fullName.isNotEmpty ? widget.delegate.fullName : "فايز عاطر"}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'إدارة الرقابة المالية والحسابات',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    formattedDate,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // كارت المحفظة والمستحقات المالي المباشر (بنفس تصميم محفظة المستحقات المعتمد)
            StreamBuilder<List<UserWalletModel>>(
              stream: _walletsStream,
              builder: (context, walletSnapshot) {
                return StreamBuilder<CollectionsRemainingMetrics>(
                  stream: _collectionsStream,
                  builder: (context, collectionsSnapshot) {
                    final allWallets = walletSnapshot.data ?? [];
                    final collectionsMetrics = collectionsSnapshot.data ??
                        const CollectionsRemainingMetrics();

                    final accountantWallet = allWallets.cast<UserWalletModel?>().firstWhere(
                      (w) => w != null && (
                             w.userPhone == '01001989360' ||
                             w.userId == 'oO6aifjJKXcAtNYj8EZV7BX7Sav1' ||
                             w.userId == widget.delegate.uid ||
                             w.userRole.toLowerCase().contains('accountant') ||
                             w.userName.toLowerCase().contains('fayez')),
                      orElse: () => null,
                    );

                    final dedicatedWalletBalance = accountantWallet != null
                        ? accountantWallet.currentBalance
                        : (allWallets.isNotEmpty
                            ? allWallets.fold<double>(0.0, (sum, w) => sum + w.currentBalance)
                            : 0.0);

                    final dedicatedWalletPaid = accountantWallet != null
                        ? accountantWallet.totalPaid
                        : 0.0;

                    final collectionsShare = collectionsMetrics.accountantRemainingShare;
                    final grandTotalDue = dedicatedWalletBalance + collectionsShare;
                    final remainingDue = (grandTotalDue - dedicatedWalletPaid).clamp(0.0, double.infinity);

                    final companyName = accountantWallet?.companyName.isNotEmpty == true
                        ? accountantWallet!.companyName
                        : (widget.delegate.companyName.isNotEmpty
                            ? widget.delegate.companyName
                            : 'fathalla market');

                    final hasBalance = grandTotalDue > 0;

                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withValues(alpha: 0.85),
                            colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onNavigateToTab(2),
                          borderRadius: BorderRadius.circular(22),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Row: Company & Status Badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: colorScheme.onPrimary.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.account_balance_wallet_rounded,
                                            color: colorScheme.onPrimary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          companyName,
                                          style: TextStyle(
                                            color: colorScheme.onPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: hasBalance
                                            ? colorScheme.onPrimary.withValues(alpha: 0.22)
                                            : colorScheme.onPrimary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: hasBalance
                                              ? colorScheme.onPrimary.withValues(alpha: 0.5)
                                              : colorScheme.onPrimary.withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            hasBalance
                                                ? Icons.check_circle_rounded
                                                : Icons.done_all_rounded,
                                            size: 13,
                                            color: colorScheme.onPrimary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            hasBalance ? 'متاح ومستحق' : 'تمت التسوية',
                                            style: TextStyle(
                                              color: colorScheme.onPrimary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // Main Hero: إجمالي المستحق
                                Text(
                                  'إجمالي المستحق',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatCurrency(grandTotalDue),
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'المحفظة (${_formatCurrency(dedicatedWalletBalance)}) + نسبة التحصيلات 20% (${_formatCurrency(collectionsShare)})',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary.withValues(alpha: 0.72),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 16),
                                Divider(
                                  color: colorScheme.onPrimary.withValues(alpha: 0.25),
                                  height: 1,
                                ),
                                const SizedBox(height: 14),

                                // Bottom Row: إجمالي المتبقي & المصروف
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'المتبقي',
                                            style: TextStyle(
                                              color: colorScheme.onPrimary.withValues(alpha: 0.75),
                                              fontSize: 10.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatCurrency(remainingDue),
                                            style: TextStyle(
                                              color: colorScheme.onPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 28,
                                      width: 1,
                                      color: colorScheme.onPrimary.withValues(alpha: 0.25),
                                      margin: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'المصروف',
                                            style: TextStyle(
                                              color: colorScheme.onPrimary.withValues(alpha: 0.75),
                                              fontSize: 10.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatCurrency(dedicatedWalletPaid),
                                            style: TextStyle(
                                              color: colorScheme.onPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // عنوان كروت الإجراءات السريعة
            Text(
              'الخدمات المالية الرئيسية',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),

            // شبكة كروت التنقل السريع
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.18,
              children: [
                _QuickActionCard(
                  title: l10n.financialReports,
                  subtitle: 'تحليل دخل الاشتراكات والشركات',
                  icon: Icons.pie_chart_rounded,
                  iconColor: colorScheme.primary,
                  backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  onTap: () => widget.onNavigateToTab(1),
                ),
                _QuickActionCard(
                  title: 'المحفظة',
                  subtitle: 'كشوف المستحقين والمنصرفات والتدقيق',
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: colorScheme.secondary,
                  backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  onTap: () => widget.onNavigateToTab(2),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // إرشادات أمان الحساب والملف الشخصي
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أمان الحساب والسرية المالية',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'يمكنك في أي وقت تحديث بريدك الإلكتروني وكلمة المرور من صفحة ملفك الشخصي لضمان أعلى مستويات الأمان.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => context.push('/user-profile', extra: widget.delegate),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.manage_accounts_rounded, size: 15, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'تعديل بياناتي وكلمة المرور',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
