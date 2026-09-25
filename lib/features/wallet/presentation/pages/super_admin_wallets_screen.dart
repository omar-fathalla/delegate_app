import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';
import 'user_wallet_screen.dart';
import 'package:delegate_app/config/theme/app_motion.dart';

class SuperAdminWalletsScreen extends StatefulWidget {
  final Delegate adminDelegate;
  final double? initialRemainingBalance;
  final String? initialPeriodKey;

  const SuperAdminWalletsScreen({
    super.key,
    required this.adminDelegate,
    this.initialRemainingBalance,
    this.initialPeriodKey,
  });

  @override
  State<SuperAdminWalletsScreen> createState() => _SuperAdminWalletsScreenState();
}

class _SuperAdminWalletsScreenState extends State<SuperAdminWalletsScreen> {
  final WalletRemoteDataSource _dataSource = WalletRemoteDataSourceImpl();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, enabled, disabled, positive_balance
  late String _currentPeriodKey;
  late double _remainingCollectionsBalance;
  List<UserWalletModel> _lastLoadedWallets = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentPeriodKey = widget.initialPeriodKey ??
        '${now.year}_${now.month.toString().padLeft(2, '0')}';
    _remainingCollectionsBalance = widget.initialRemainingBalance ?? 42000.0;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(amount)} ج.م';
  }

  String _formatAmountOnly(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة المحافظ والمستحقات',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'تصدير تقرير المحافظ CSV',
              onPressed: () => _exportWalletsCsv(_lastLoadedWallets),
            ),
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'دليل استخدام المحفظة',
              onPressed: _showInfoDialog,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAllocateBalanceDialog(context),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          icon: const Icon(Icons.add_card_rounded),
          label: const Text(
            'تخصيص رصيد جديد',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<List<UserWalletModel>>(
          stream: _dataSource.streamAllWallets(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: colorScheme.error),
                      const SizedBox(height: 12),
                      Text(
                        'حدث خطأ في جلب بيانات المحافظ:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allWallets = snapshot.data ?? [];
            final totalAllocated = allWallets.fold<double>(
              0.0,
              (sum, w) => sum + w.currentBalance,
            );
            final activeWalletsCount =
                allWallets.where((w) => w.isWalletEnabled).length;
            final positiveBalanceCount =
                allWallets.where((w) => w.currentBalance > 0).length;
            final disabledWalletsCount =
                allWallets.where((w) => !w.isWalletEnabled).length;
            final netFreeRemaining = (_remainingCollectionsBalance - totalAllocated)
                .clamp(0.0, double.infinity);

            // Filtering
            final filteredWallets = allWallets.where((w) {
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                final matchName = w.userName.toLowerCase().contains(q);
                final matchPhone = w.userPhone.contains(q);
                final matchCompany = w.companyName.toLowerCase().contains(q);
                final matchRole = w.userRole.toLowerCase().contains(q);
                if (!matchName && !matchPhone && !matchCompany && !matchRole) {
                  return false;
                }
              }

              switch (_selectedFilter) {
                case 'enabled':
                  if (!w.isWalletEnabled) return false;
                  break;
                case 'disabled':
                  if (w.isWalletEnabled) return false;
                  break;
                case 'positive_balance':
                  if (w.currentBalance <= 0) return false;
                  break;
              }
              return true;
            }).toList();

            _lastLoadedWallets = filteredWallets;

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. Financial Metrics Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _buildFinancialOverviewCard(
                      remainingCollections: _remainingCollectionsBalance,
                      totalAllocated: totalAllocated,
                      netFreeRemaining: netFreeRemaining,
                      activeCount: activeWalletsCount,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),

                // 2. Search Box and Filter Dropdown
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'ابحث باسم المستخدم، الهاتف، الشركة، أو الدور...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() => _searchQuery = val.trim());
                          },
                        ),
                        const SizedBox(height: 10),
                        // Dropdown Filter Menu with ONLY Google Icons (No emojis)
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedFilter,
                              isExpanded: true,
                              dropdownColor: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(14),
                              icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary, size: 26),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.format_list_bulleted_rounded, size: 18, color: colorScheme.primary),
                                      const SizedBox(width: 10),
                                      Text('جميع المحافظ (${allWallets.length})'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'enabled',
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 18, color: colorScheme.primary),
                                      const SizedBox(width: 10),
                                      Text('المحافظ المفعلة ($activeWalletsCount)'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'positive_balance',
                                  child: Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: colorScheme.tertiary),
                                      const SizedBox(width: 10),
                                      Text('محافظ ذات رصيد مستحق ($positiveBalanceCount)'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'disabled',
                                  child: Row(
                                    children: [
                                      Icon(Icons.pause_circle_outline_rounded, size: 18, color: colorScheme.outline),
                                      const SizedBox(width: 10),
                                      Text('المحافظ المعطلة ($disabledWalletsCount)'),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedFilter = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Wallets Cards List
                if (filteredWallets.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                size: 54, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            Text(
                              allWallets.isEmpty
                                  ? 'لا توجد محافظ منشأة بعد.\nاضغط على "تخصيص رصيد جديد" لإنشاء محفظة لأي مستخدم.'
                                  : 'لم يتم العثور على محافظ تطابق نتائج البحث.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final wallet = filteredWallets[index];
                          return _buildWalletCard(
                            wallet: wallet,
                            theme: theme,
                            colorScheme: colorScheme,
                          );
                        },
                        childCount: filteredWallets.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFinancialOverviewCard({
    required double remainingCollections,
    required double totalAllocated,
    required double netFreeRemaining,
    required int activeCount,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الموقف المالي لمحافظ المستحقات',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activeCount محفظة نشطة',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Column 1: Total Remaining from collections
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.savings_rounded,
                  title: 'المتبقي',
                  value: _formatCurrency(remainingCollections),
                  color: colorScheme.tertiary,
                  colorScheme: colorScheme,
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                margin: const EdgeInsets.symmetric(horizontal: 6),
              ),
              // Column 2: Total Allocated
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'المخصص',
                  value: _formatCurrency(totalAllocated),
                  color: colorScheme.primary,
                  colorScheme: colorScheme,
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                margin: const EdgeInsets.symmetric(horizontal: 6),
              ),
              // Column 3: Net Free Remaining
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'المتبقي الحر',
                  value: _formatCurrency(netFreeRemaining),
                  color: colorScheme.onSurface,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  /// كارت المحفظة المتطور والمريح بصرياً (Material Design 3 Card)
  Widget _buildWalletCard({
    required UserWalletModel wallet,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final hasBalance = wallet.currentBalance > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: wallet.isWalletEnabled
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: wallet.isWalletEnabled
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: wallet.isWalletEnabled ? 1.2 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Avatar + User Info + Internal Badge + Switch + More Options
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: wallet.isWalletEnabled
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: wallet.isWalletEnabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  child: Text(
                    wallet.userName.isNotEmpty
                        ? wallet.userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              wallet.userName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: wallet.isWalletEnabled ? null : colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (wallet.isInternalOnly) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'حسابات داخلية',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (wallet.userRole.isNotEmpty) wallet.userRole,
                          if (wallet.companyName.isNotEmpty) wallet.companyName,
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Switch for instant enable/disable
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: wallet.isWalletEnabled,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Icon(Icons.check_rounded,
                            size: 14, color: colorScheme.onPrimary);
                      }
                      return Icon(Icons.close_rounded,
                          size: 14, color: colorScheme.outline);
                    }),
                    activeTrackColor: colorScheme.primary,
                    activeThumbColor: colorScheme.onPrimary,
                    onChanged: (val) async {
                      HapticFeedback.mediumImpact();
                      await _dataSource.toggleWalletStatus(
                        userId: wallet.userId,
                        isEnabled: val,
                      );
                    },
                  ),
                ),
                // More Popup Menu
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'خيارات المحفظة',
                  onSelected: (val) {
                    if (val == 'adjust') {
                      _showAdjustBalanceDialog(context, wallet);
                    } else if (val == 'delete') {
                      _showDeleteWalletDialog(context, wallet);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'adjust',
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('تعديل الرصيد (+ / -)'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, size: 18, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Text('حذف المحفظة نهائياً', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // 2. Financial Metrics: Due Balance + Monthly Allocation + Total Paid
            Row(
              children: [
                // الرصيد المستحق
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasBalance
                          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الرصيد المستحق',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(wallet.currentBalance),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: hasBalance
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // إجمالي المستحق
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي المستحق',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(wallet.totalAllocated),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // إجمالي المنصرف
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي المنصرف',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(wallet.totalPaid),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (wallet.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'بيان: ${wallet.notes}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 12),

            // 3. Action Buttons (Wrap - Overflow Free)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. زر إرسال دفعة
                FilledButton.icon(
                  onPressed: hasBalance
                      ? () => _showPayoutDialog(context, wallet)
                      : null,
                  icon: const Icon(Icons.price_check_rounded, size: 16),
                  label: const Text(
                    'إرسال دفعة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // 2. زر تحصيل / خصم
                OutlinedButton.icon(
                  onPressed: () => _showAdjustBalanceDialog(context, wallet),
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text(
                    'تحصيل / خصم',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),


                // 4. زر السجل
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserWalletScreen(
                          targetUserId: wallet.userId,
                          targetUserName: wallet.userName,
                          isReadOnlyView: false,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_rounded, size: 15),
                  label: const Text(
                    'السجل',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Dialog 1: Allocate Balance to User ---
  void _showAllocateBalanceDialog(BuildContext context) {
    final amountController = TextEditingController();
    final noteController = TextEditingController(
      text: 'تخصيص مستحقات شهر ${_currentPeriodKey.replaceAll('_', '/')}',
    );

    Map<String, String>? selectedUser;
    final userSearchController = TextEditingController();
    bool isLoadingUsers = false;
    bool isInternalOnly = false;
    bool isSubmitting = false;
    bool hasSearched = false;
    List<Map<String, String>> searchResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final colorScheme = Theme.of(modalContext).colorScheme;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.add_card_rounded,
                                    color: colorScheme.primary, size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'تخصيص رصيد مستحق لمستخدم',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Divider(height: 16),

                        // Step 1: User Picker
                        const Text(
                          '1. اختر المستخدم المستحق:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: userSearchController,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم، رقم الهاتف، أو المسمى...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: isLoadingUsers
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Center(
                                      child: CircularProgressIndicator.adaptive(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : (userSearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          setModalState(() {
                                            userSearchController.clear();
                                            searchResults = [];
                                            selectedUser = null;
                                            hasSearched = false;
                                          });
                                        },
                                      )
                                    : null),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onChanged: (query) async {
                            if (query.trim().length < 2) {
                              setModalState(() {
                                searchResults = [];
                                hasSearched = false;
                              });
                              return;
                            }
                            setModalState(() {
                              isLoadingUsers = true;
                              hasSearched = true;
                            });
                            try {
                              final users = await _dataSource.searchUsers(query);
                              setModalState(() {
                                searchResults = users;
                                isLoadingUsers = false;
                              });
                            } catch (_) {
                              setModalState(() => isLoadingUsers = false);
                            }
                          },
                        ),
                        if (hasSearched &&
                            searchResults.isEmpty &&
                            !isLoadingUsers &&
                            userSearchController.text.trim().length >= 2 &&
                            selectedUser == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'لم يتم العثور على مستخدم مطابق لهذا الرقم أو الاسم',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        if (searchResults.isNotEmpty && selectedUser == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Material(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 180),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: searchResults.length,
                                  itemBuilder: (c, i) {
                                    final u = searchResults[i];
                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: colorScheme.primaryContainer,
                                        child: Text(
                                          u['name']!.isNotEmpty
                                              ? u['name']![0].toUpperCase()
                                              : 'U',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        u['name']!,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        '${u['role']} • ${u['companyName']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      onTap: () {
                                        setModalState(() {
                                          selectedUser = u;
                                          userSearchController.text = u['name'] ?? '';
                                          searchResults = [];
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                        if (selectedUser != null) ...[
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final existingWallet = _lastLoadedWallets
                                  .where((w) => w.userId == selectedUser!['uid'])
                                  .firstOrNull;

                              if (existingWallet == null) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          color: colorScheme.primary, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'المستخدم المحدد: ${selectedUser!['name']} (${selectedUser!['role']})',
                                          style: TextStyle(
                                            color: colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => setModalState(
                                            () => selectedUser = null),
                                        child: const Text('تغيير',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.tertiary,
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: colorScheme.tertiary, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'هذا المستخدم يمتلك محفظة قائمة بالفعل:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                              color: colorScheme.onTertiaryContainer,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => setModalState(
                                              () => selectedUser = null),
                                          child: const Text('تغيير'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '• الرصيد القائم حالياً: ${_formatCurrency(existingWallet.currentBalance)}\n'
                                      '• إجمالي المستحق: ${_formatCurrency(existingWallet.totalAllocated)}\n'
                                      '• إجمالي المسدد: ${_formatCurrency(existingWallet.totalPaid)}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colorScheme.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _showDeleteWalletDialog(
                                              context, existingWallet);
                                        },
                                        icon: Icon(
                                            Icons.delete_forever_rounded,
                                            size: 15,
                                            color: colorScheme.error),
                                        label: Text('حذف المحفظة',
                                            style: TextStyle(
                                                fontSize: 11, color: colorScheme.error)),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: colorScheme.error),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Step 2: Amount
                        Builder(
                          builder: (context) {
                            final existing = selectedUser != null
                                ? _lastLoadedWallets
                                    .where((w) => w.userId == selectedUser!['uid'])
                                    .firstOrNull
                                : null;
                            return Text(
                              existing != null
                                  ? '2. إضافة مبلغ للرصيد القائم بالمحفظة (ج.م):'
                                  : '2. المبلغ المراد تخصيصه كرصيد أولي (ج.م):',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            hintText: 'مثال: 15000',
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Step 3: Notes / Purpose
                        const Text(
                          '3. بيان وملاحظات التخصيص:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: noteController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'اكتب سبب أو بيان التخصيص للمستخدم...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Step 5: Internal Secrecy Toggle
                        Material(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: SwitchListTile(
                            value: isInternalOnly,
                            onChanged: (v) => setModalState(() => isInternalOnly = v),
                            title: const Text(
                              'محفظة حسابات داخلية وسرية',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: const Text(
                              'لن تظهر المحفظة للمستخدم في تطبيقه ولن تصله أي إشعارات (تظهر للإدارة والمحاسب فقط).',
                              style: TextStyle(fontSize: 11),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    if (selectedUser == null) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                            content: Text('يرجى اختيار المستخدم أولاً')),
                                      );
                                      return;
                                    }

                                    final amt = double.tryParse(amountController.text.trim()) ?? 0.0;

                                    if (amt <= 0) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                            content: Text('يرجى إدخال مبلغ صحيح أكبر من صفر')),
                                      );
                                      return;
                                    }

                                    final targetUid = selectedUser!['uid'] ?? selectedUser!['id'];
                                    if (targetUid == null || targetUid.isEmpty) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(content: Text('معرف المستخدم غير صالح')),
                                      );
                                      return;
                                    }

                                    setModalState(() => isSubmitting = true);

                                    try {
                                      await _dataSource.allocateBalance(
                                        userId: targetUid,
                                        userName: selectedUser!['name'] ?? '',
                                        userPhone: selectedUser!['phone'] ?? '',
                                        userRole: selectedUser!['role'] ?? '',
                                        companyName: selectedUser!['companyName'] ?? '',
                                        companyUID: selectedUser!['companyUID'] ?? '',
                                        amount: amt,
                                        periodKey: _currentPeriodKey,
                                        note: noteController.text.trim(),
                                        adminUid: widget.adminDelegate.uid,
                                        adminName: widget.adminDelegate.fullName.isNotEmpty
                                            ? widget.adminDelegate.fullName
                                            : widget.adminDelegate.firstName,
                                        isInternalOnly: isInternalOnly,
                                      );

                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);

                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم تخصيص ${_formatCurrency(amt)} لمحفظة ${selectedUser!['name']} بنجاح!',
                                            style: TextStyle(
                                              color: colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                          backgroundColor: colorScheme.primaryContainer,
                                        ),
                                      );
                                    } catch (e) {
                                      setModalState(() => isSubmitting = false);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('حدث خطأ: $e')),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            child: AnimatedSwitcher(
                              duration: AppMotionDurations.short3,
                              switchInCurve: AppMotionCurves.standardDecelerate,
                              switchOutCurve: AppMotionCurves.standardAccelerate,
                              child: isSubmitting
                                  ? SizedBox(
                                      key: const ValueKey('alloc_submitting_spinner'),
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Row(
                                      key: ValueKey('alloc_confirm_btn_content'),
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'تأكيد',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Dialog 2: Settle Payout / Mark as Collected ---
  void _showPayoutDialog(BuildContext context, UserWalletModel wallet) {
    final payoutAmountController = TextEditingController(
      text: wallet.currentBalance.toStringAsFixed(2),
    );
    final noteController = TextEditingController(
      text: 'تسوية وصرف مستحقات نقدية (تم التحصيل بالكامل)',
    );
    bool isFullSettlement = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final colorScheme = Theme.of(modalContext).colorScheme;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.payments_rounded,
                                    color: colorScheme.primary, size: 22),
                                const SizedBox(width: 8),
                                const Text(
                                  'تسجيل صرف / تسوية مستحقات',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Divider(height: 16),

                        // User Info
                        Text(
                          'المستفيد: ${wallet.userName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الرصيد المستحق الحالي: ${_formatCurrency(wallet.currentBalance)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Quick Toggle: Full or Partial
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text('سداد كامل (تصفير)')),
                                selected: isFullSettlement,
                                selectedColor: colorScheme.primaryContainer,
                                onSelected: (val) {
                                  setModalState(() {
                                    isFullSettlement = true;
                                    payoutAmountController.text =
                                        wallet.currentBalance.toStringAsFixed(2);
                                    noteController.text =
                                        'تسوية وصرف مستحقات نقدية (تم التحصيل بالكامل)';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text('سداد جزئي')),
                                selected: !isFullSettlement,
                                selectedColor: colorScheme.primaryContainer,
                                onSelected: (val) {
                                  setModalState(() {
                                    isFullSettlement = false;
                                    payoutAmountController.text = '';
                                    noteController.text =
                                        'تسوية وصرف جزئي من المستحقات';
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Payout Amount Field
                        TextField(
                          controller: payoutAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          enabled: !isFullSettlement,
                          decoration: InputDecoration(
                            labelText: 'المبلغ المسدد المنصرف',
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Note Field
                        TextField(
                          controller: noteController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'بيان وسند الصرف',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Confirm Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final amt = double.tryParse(
                                      payoutAmountController.text.trim()) ??
                                  0.0;
                              if (amt <= 0 || amt > wallet.currentBalance) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'المبلغ يجب أن يكون بين 1 و ${_formatAmountOnly(wallet.currentBalance)} ج.م',
                                    ),
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(ctx);

                              try {
                                await _dataSource.recordPayout(
                                  userId: wallet.userId,
                                  amount: amt,
                                  note: noteController.text.trim(),
                                  adminUid: widget.adminDelegate.uid,
                                  adminName: widget.adminDelegate.fullName.isNotEmpty
                                      ? widget.adminDelegate.fullName
                                      : widget.adminDelegate.firstName,
                                );

                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم تسجيل صرف ${_formatCurrency(amt)} وتحديث رصيد المحفظة بنجاح!',
                                      style: TextStyle(
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    backgroundColor: colorScheme.primaryContainer,
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('حدث خطأ: $e')),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.check_circle_outline_rounded),
                            label: const Text(
                              'تأكيد السداد والخصم',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Dialog 3: Adjust Balance (Add / Deduct) with Theme Derived Colors ---
  void _showAdjustBalanceDialog(BuildContext context, UserWalletModel wallet) {
    bool isAddition = true;
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final colorScheme = Theme.of(modalCtx).colorScheme;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'تعديل رصيد - ${wallet.userName}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('الرصيد الحالي بالمحفظة:', style: TextStyle(fontSize: 12)),
                              Text(
                                _formatCurrency(wallet.currentBalance),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('نوع التعديل:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                avatar: Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 18,
                                  color: isAddition ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                                ),
                                label: Center(
                                  child: Text(
                                    'إضافة للرصيد (+)',
                                    style: TextStyle(
                                      fontWeight: isAddition ? FontWeight.bold : FontWeight.normal,
                                      color: isAddition ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                selected: isAddition,
                                selectedColor: colorScheme.primaryContainer,
                                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                side: BorderSide(
                                  color: isAddition
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                onSelected: (v) => setModalState(() => isAddition = true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                avatar: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  size: 18,
                                  color: !isAddition ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
                                ),
                                label: Center(
                                  child: Text(
                                    'خصم / إنقاص (-)',
                                    style: TextStyle(
                                      fontWeight: !isAddition ? FontWeight.bold : FontWeight.normal,
                                      color: !isAddition ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                selected: !isAddition,
                                selectedColor: colorScheme.errorContainer,
                                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                side: BorderSide(
                                  color: !isAddition
                                      ? colorScheme.error
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                onSelected: (v) => setModalState(() => isAddition = false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text('المبلغ (ج.م):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: 'مثال: 1000',
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('سبب وبيان التعديل (إلزامي):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: reasonController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'اكتب سبب التعديل ليتم توثيقه في السجل المالي...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
                              final reason = reasonController.text.trim();
                              if (amt <= 0) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
                                );
                                return;
                              }
                              if (reason.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('يرجى كتابة سبب التعديل')),
                                );
                                return;
                              }
                              if (!isAddition && amt > wallet.currentBalance) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('مبلغ الخصم أكبر من الرصيد الحالي للمحفظة')),
                                );
                                return;
                              }

                              Navigator.pop(ctx);
                              final delta = isAddition ? amt : -amt;
                              try {
                                await _dataSource.adjustBalance(
                                  userId: wallet.userId,
                                  deltaAmount: delta,
                                  reason: reason,
                                  adminUid: widget.adminDelegate.uid,
                                  adminName: widget.adminDelegate.fullName.isNotEmpty
                                      ? widget.adminDelegate.fullName
                                      : widget.adminDelegate.firstName,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تم تعديل رصيد ${wallet.userName} بمقدار ${_formatCurrency(amt)} بنجاح!'),
                                    backgroundColor: colorScheme.primaryContainer,
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('حدث خطأ: $e')),
                                );
                              }
                            },
                            icon: Icon(
                              isAddition ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                              size: 20,
                            ),
                            label: Text(
                              isAddition ? 'تأكيد إضافة الرصيد' : 'تأكيد خصم الرصيد',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: isAddition ? colorScheme.primary : colorScheme.error,
                              foregroundColor: isAddition ? colorScheme.onPrimary : colorScheme.onError,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Dialog 4: Delete Wallet Permanently ---
  void _showDeleteWalletDialog(BuildContext context, UserWalletModel wallet) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: colorScheme.error, size: 26),
              const SizedBox(width: 8),
              const Text('تأكيد حذف المحفظة نهائياً'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من حذف محفظة المستفيد "${wallet.userName}" نهائياً؟',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '• الرصيد المتبقي الحالي: ${_formatCurrency(wallet.currentBalance)}\n'
                '• إجمالي المستحق: ${_formatCurrency(wallet.totalAllocated)}\n'
                '• سيتم مسح كافة سجلات الحركات المرتبطة بهذه المحفظة نهائياً من النظام ولا يمكن التراجع عن هذا الإجراء.',
                style: TextStyle(fontSize: 12, color: colorScheme.error, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _dataSource.deleteWallet(userId: wallet.userId);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حذف محفظة ${wallet.userName} بنجاح'),
                      backgroundColor: colorScheme.error,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('حدث خطأ أثناء الحذف: $e')),
                  );
                }
              },
              icon: Icon(Icons.delete_forever_rounded),
              label: Text('حذف نهائي'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Export Wallets CSV ---
  Future<void> _exportWalletsCsv(List<UserWalletModel> wallets) async {
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات محافظ للتصدير')),
      );
      return;
    }

    try {
      final csvHeader = '\uFEFFاسم المستفيد,المسمى الوظيفي,الشركة,رقم الهاتف,الرصيد الحالي,إجمالي المستحق,إجمالي المنصرف,حالة المحفظة,ملاحظات\n';
      final csvRows = wallets.map((w) {
        final name = w.userName.replaceAll(',', ' ');
        final role = w.userRole.replaceAll(',', ' ');
        final company = w.companyName.replaceAll(',', ' ');
        final phone = w.userPhone;
        final currentBal = w.currentBalance.toStringAsFixed(2);
        final totalAlloc = w.totalAllocated.toStringAsFixed(2);
        final totalPaid = w.totalPaid.toStringAsFixed(2);
        final status = w.isWalletEnabled ? 'مفعلة' : 'معطلة';
        final notes = w.notes.replaceAll(',', ' ').replaceAll('\n', ' ');
        return '$name,$role,$company,$phone,$currentBal,$totalAlloc,$totalPaid,$status,$notes';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final directory = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyy_MM_dd_HHmm').format(DateTime.now());
      final file = File('${directory.path}/wallets_report_$nowStr.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير كشف حسابات ومحافظ المستحقات المالية',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تصدير الملف: $e')),
        );
      }
    }
  }

  void _showInfoDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'عن نظام المحافظ والمستحقات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '1. التخصيص من الرصيد المتبقي:\n'
                    'يمكنك تخصيص مبالغ مستحقة لأي مستخدم (مندوب أو مشرف أو تسويق) مقتطعة من إجمالي الرصيد المتبقي للتحصيل في شاشة التحصيلات والفواتير.\n\n'
                    '2. سويتش التفعيل الفوري:\n'
                    'عند تشغيل السويتش لأي مستخدم، تظهر له صفحة "المحفظة" فوراً في قائمته الرئيسية ليشاهد رصيده المستحق.\n\n'
                    '3. تسجيل الصرف والتسوية:\n'
                    'عند تسليم المبلغ للمستخدم، اضغط "تسجيل صرف / سداد" لتسوية الرصيد جزئياً أو كلياً وتصفيره مع توثيق الحركة تاريخياً.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      },
    );
  }
}