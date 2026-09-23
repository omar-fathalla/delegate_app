import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_subscription_financial_report_screen.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/presentation/pages/user_wallet_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
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
  StreamSubscription? _walletSubscription;
  bool _isWalletEnabled = false;

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

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

    switch (value) {
      case 'profile':
        context.push('/user-profile', extra: delegate);
        break;
      case 'user_wallet':
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final delegate = widget.delegate;
    final photoUrl = delegate.documents
        .where((d) =>
            d.documentKey == DocumentKey.personalPhoto &&
            d.documentURL.isNotEmpty)
        .firstOrNull
        ?.documentURL;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2.0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        title: Row(
          children: [
            AppAvatar(
              imageUrl: photoUrl,
              fallbackText: delegate.firstName.isNotEmpty ? delegate.firstName : 'ح',
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    delegate.fullName.isNotEmpty ? delegate.fullName : delegate.firstName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n.accountant,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (delegate.organizationName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            delegate.organizationName,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: l10n.logout,
            onPressed: () => _showLogoutDialog(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenuSelected,
            itemBuilder: (ctx) => [
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
              if (_isWalletEnabled)
                PopupMenuItem(
                  value: 'user_wallet',
                  child: Row(
                    children: [
                      Icon(Icons.wallet_rounded, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 12),
                      const Text('محفظتي الشخصية'),
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
class _AccountantOverviewTab extends StatelessWidget {
  final Delegate delegate;
  final ValueChanged<int> onNavigateToTab;

  const _AccountantOverviewTab({
    required this.delegate,
    required this.onNavigateToTab,
  });

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
            // بطاقة الترحيب والملف المالي
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.85),
                  ],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.accountantDashboard,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'مرحباً بك في منظومة الرقابة المالية والحسابات. يمكنك مراجعة وتدقيق كافة اشتراكات المناديب، إيصالات الدفع الإلكتروني، وحركات المحافظ المالية بكل دقة.',
                    style: TextStyle(
                      color: colorScheme.onPrimary.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => context.push('/user-profile', extra: delegate),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.onPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.manage_accounts_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'تعديل بياناتي وكلمة المرور',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
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
                  onTap: () => onNavigateToTab(1),
                ),
                _QuickActionCard(
                  title: 'المحفظة',
                  subtitle: 'كشوف المستحقين والمنصرفات والتدقيق',
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: colorScheme.secondary,
                  backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  onTap: () => onNavigateToTab(2),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // إرشادات أمان الحساب
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
