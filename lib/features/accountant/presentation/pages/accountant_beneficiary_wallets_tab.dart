import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';
import 'package:delegate_app/features/wallet/domain/entities/user_wallet_entity.dart';

/// تاب محافظ المستحقات والحسابات الداخلية الخاصة بإدارة الحسابات
class AccountantBeneficiaryWalletsTab extends StatefulWidget {
  final Delegate accountantDelegate;

  const AccountantBeneficiaryWalletsTab({
    super.key,
    required this.accountantDelegate,
  });

  @override
  State<AccountantBeneficiaryWalletsTab> createState() =>
      _AccountantBeneficiaryWalletsTabState();
}

class _AccountantBeneficiaryWalletsTabState
    extends State<AccountantBeneficiaryWalletsTab> {
  final WalletRemoteDataSource _dataSource = WalletRemoteDataSourceImpl();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, has_balance, settled
  List<UserWalletModel> _currentFilteredWallets = [];

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
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text(
            'المحفظة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: -0.2),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'تصدير كشف المحافظ CSV',
              onPressed: () => _exportAllWalletsCsv(_currentFilteredWallets),
            ),
          ],
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
                        'حدث خطأ في تحميل بيانات المحافظ:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allWallets = snapshot.data ?? [];

            // Identify the accountant's personal wallet (Fayez Atter)
            final accountantWallet = allWallets.cast<UserWalletModel?>().firstWhere(
              (w) => w != null && (
                     w.userPhone == '01001989360' ||
                     w.userId == 'oO6aifjJKXcAtNYj8EZV7BX7Sav1' ||
                     w.userId == widget.accountantDelegate.uid ||
                     w.userRole.toLowerCase().contains('accountant') ||
                     w.userName.toLowerCase().contains('fayez')),
              orElse: () => null,
            );

            // Beneficiary wallets: Exclude the accountant (Fayez Atter) from the list below
            // to eliminate duplication with the top financial position card
            final beneficiaryWallets = allWallets.where((w) {
              final isFayezAtter = w.userPhone == '01001989360' ||
                  w.userId == 'oO6aifjJKXcAtNYj8EZV7BX7Sav1' ||
                  w.userId == widget.accountantDelegate.uid ||
                  w.userRole.toLowerCase().contains('accountant') ||
                  w.userName.toLowerCase().contains('fayez');
              return !isFayezAtter;
            }).toList();

            // The 4 Core Metrics for Accountant Financial Position:
            // 1. المحفظة المخصصة:
            final dedicatedWalletBalance = accountantWallet != null
                ? accountantWallet.currentBalance
                : allWallets.fold<double>(0.0, (sum, w) => sum + w.currentBalance);

            // 4. إجمالي المصروف:
            final dedicatedWalletPaid = accountantWallet != null
                ? accountantWallet.totalPaid
                : allWallets.fold<double>(0.0, (sum, w) => sum + w.totalPaid);

            // Filtering for remaining beneficiary wallets
            final filteredWallets = beneficiaryWallets.where((w) {
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
                case 'has_balance':
                  if (w.currentBalance <= 0) return false;
                  break;
                case 'settled':
                  if (w.currentBalance > 0) return false;
                  break;
              }
              return true;
            }).toList();

            _currentFilteredWallets = filteredWallets;

            return StreamBuilder<CollectionsRemainingMetrics>(
              stream: _dataSource.streamCollectionsRemainingMetrics(),
              builder: (context, collectionsSnapshot) {
                final collectionsMetrics = collectionsSnapshot.data ??
                    const CollectionsRemainingMetrics();

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1. Overview Financial Metrics Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: _buildFinancialSummaryCard(
                          dedicatedWalletBalance: dedicatedWalletBalance,
                          dedicatedWalletPaid: dedicatedWalletPaid,
                          collectionsMetrics: collectionsMetrics,
                          accountantWallet: accountantWallet,
                          theme: theme,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ),

                // 2. Search & Filter Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'بحث باسم المستفيد، الشركة، أو الهاتف...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onChanged: (val) {
                            setState(() => _searchQuery = val.trim());
                          },
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.format_list_bulleted_rounded, size: 18, color: colorScheme.primary),
                                      const SizedBox(width: 10),
                                      Text('جميع المحافظ (${beneficiaryWallets.length})'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'has_balance',
                                  child: Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: colorScheme.tertiary),
                                      const SizedBox(width: 10),
                                      Text('مستحق للصرف (${beneficiaryWallets.where((w) => w.currentBalance > 0).length})'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'settled',
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 18, color: colorScheme.outline),
                                      const SizedBox(width: 10),
                                      Text('مسدد بالكامل (${beneficiaryWallets.where((w) => w.currentBalance <= 0).length})'),
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

                // 3. Beneficiary Cards List
                if (filteredWallets.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 56,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              allWallets.isEmpty
                                  ? 'لا توجد محافظ مستحقات منشأة حتى الآن.'
                                  : 'لم يتم العثور على محافظ تطابق معايير البحث.',
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
                          return _buildBeneficiaryCard(
                            wallet: wallet,
                            collectionsMetrics: collectionsMetrics,
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
            );
          },
        ),
      ),
    );
  }



  /// كرت الموقف المالي للمحفظة الخاص بالمحاسب (4 مؤشرات واضحة وبسيطة)
  Widget _buildFinancialSummaryCard({
    required double dedicatedWalletBalance,
    required double dedicatedWalletPaid,
    required CollectionsRemainingMetrics collectionsMetrics,
    required UserWalletModel? accountantWallet,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final collectionsShare = collectionsMetrics.accountantRemainingShare;
    final grandTotalCombined = dedicatedWalletBalance + collectionsShare;
    final percentageText = '${collectionsMetrics.accountantPercentage.toStringAsFixed(0)}%';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. الرأس والعنوان مع الأزرار السريعة ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'الموقف المالي للمحفظة',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // أزرار سريعة ومبسطة (أيقونات) لسجل الحركات وكشف الحساب
              if (accountantWallet != null && accountantWallet.userId.isNotEmpty) ...[
                IconButton.filledTonal(
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  tooltip: 'سجل الحركات والتدقيق',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showTransactionsHistorySheet(
                    context,
                    accountantWallet,
                    collectionsMetrics,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  tooltip: 'تصدير كشف الحساب',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _exportSingleWalletTransactionsCsv(accountantWallet),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          // السطر الثاني للعنوان: الاسم والصفة ونسبة التحصيلات (في سطر مستقل لمنع أي Overflow نهائياً)
          Row(
            children: [
              Text(
                'فايز عاطر • إدارة الحسابات',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percentageText من متبقي التحصيلات',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── 2. المؤشرات المالية الأربعة في شبكة 2x2 رحبة وواضحة ──
          Row(
            children: [
              // 1. المحفظة المخصصة
              _buildSummaryMetricBox(
                title: 'المحفظة المخصصة',
                subtitle: 'الرصيد المخصص',
                value: _formatCurrency(dedicatedWalletBalance),
                icon: Icons.wallet_rounded,
                iconColor: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 10),
              // 2. نسبة التحصيلات
              _buildSummaryMetricBox(
                title: 'نسبة التحصيلات',
                subtitle: '$percentageText من المتبقي',
                value: _formatCurrency(collectionsShare),
                icon: Icons.pie_chart_rounded,
                iconColor: colorScheme.secondary,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
                colorScheme: colorScheme,
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              // 3. الإجمالي المستحق (Total)
              _buildSummaryMetricBox(
                title: 'الإجمالي المستحق',
                subtitle: 'المحفظة + التحصيلات',
                value: _formatCurrency(grandTotalCombined),
                icon: Icons.account_balance_wallet_rounded,
                iconColor: colorScheme.primary,
                valueColor: colorScheme.primary,
                backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.38),
                borderColor: colorScheme.primary.withValues(alpha: 0.45),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 10),
              // 4. إجمالي المصروف
              _buildSummaryMetricBox(
                title: 'إجمالي المصروف',
                subtitle: 'المنصرف حتى الآن',
                value: _formatCurrency(dedicatedWalletPaid),
                icon: Icons.check_circle_outline_rounded,
                iconColor: colorScheme.tertiary,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetricBox({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    required ColorScheme colorScheme,
    Color? valueColor,
    String? subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(4.5),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? colorScheme.onSurface,
                ),
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// كرت محفظة المستفيد الخاص بالمحاسب (Card-Based Layout)
  Widget _buildBeneficiaryCard({
    required UserWalletModel wallet,
    required CollectionsRemainingMetrics collectionsMetrics,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final isFayezAtter = wallet.userPhone == '01001989360' ||
        wallet.userId == 'oO6aifjJKXcAtNYj8EZV7BX7Sav1' ||
        wallet.userRole.toLowerCase().contains('accountant') ||
        wallet.userName.toLowerCase().contains('fayez');

    final collectionsShare = isFayezAtter ? collectionsMetrics.accountantRemainingShare : 0.0;
    final totalDueCombined = wallet.currentBalance + collectionsShare;
    final hasBalance = totalDueCombined > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasBalance
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: hasBalance ? 1.3 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Avatar + Name/Role + Secret Badge
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Text(
                    wallet.userName.isNotEmpty
                        ? wallet.userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (wallet.userRole.isNotEmpty) ...[
                            Text(
                              wallet.userRole,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Text(' • ', style: TextStyle(fontSize: 11)),
                          ],
                          if (wallet.companyName.isNotEmpty)
                            Flexible(
                              child: Text(
                                wallet.companyName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.shade900.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 11, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        'حسابات داخلية',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            if (isFayezAtter) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.35),
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ],
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alt_route_rounded, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'تغذية مالية مزدوجة (المحفظة + التحصيلات)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${collectionsMetrics.accountantPercentage.toStringAsFixed(0)}% من المتبقي',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // رصيد المحفظة
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'رصيد المحفظة',
                                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _formatCurrency(wallet.currentBalance),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text('+', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        const SizedBox(width: 6),
                        // حصة التحصيلات
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'نسبة التحصيلات (${collectionsMetrics.accountantPercentage.toStringAsFixed(0)}%)',
                                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _formatCurrency(collectionsMetrics.accountantRemainingShare),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text('=', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        const SizedBox(width: 6),
                        // الإجمالي المستحق
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الإجمالي المستحق',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _formatCurrency(totalDueCombined),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
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
            ],

            // Financial Metrics in Card
            Row(
              children: [
                // 1. الرصيد القائم للصرف
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: hasBalance
                          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isFayezAtter ? 'الرصيد المتبقي (الإجمالي)' : 'الرصيد المستحق للصرف',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(isFayezAtter ? totalDueCombined : wallet.currentBalance),
                            style: TextStyle(
                              fontSize: 16,
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
                const SizedBox(width: 10),

                // 2. المنصرف
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي المنصرف',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(wallet.totalPaid),
                            style: TextStyle(
                              fontSize: 16,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'بيان: ${wallet.notes}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action Buttons Row: View History & Export (Read-only for Accountant)
            Row(
              children: [
                // زر سجل الحركات والتدقيق
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransactionsHistorySheet(context, wallet, collectionsMetrics),
                    icon: const Icon(Icons.receipt_long_rounded, size: 17),
                    label: const Text(
                      'سجل الحركات والتدقيق',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // زر تصدير كشف حساب المستفيد CSV
                OutlinedButton.icon(
                  onPressed: () => _exportSingleWalletTransactionsCsv(wallet),
                  icon: const Icon(Icons.download_rounded, size: 17),
                  label: const Text(
                    'تصدير كشف',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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


  // --- Modal: Transactions History for Single Wallet ---
  void _showTransactionsHistorySheet(
    BuildContext context,
    UserWalletModel wallet,
    CollectionsRemainingMetrics collectionsMetrics,
  ) {
    final isFayezAtter = wallet.userPhone == '01001989360' ||
        wallet.userId == 'oO6aifjJKXcAtNYj8EZV7BX7Sav1' ||
        wallet.userRole.toLowerCase().contains('accountant') ||
        wallet.userName.toLowerCase().contains('fayez');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_rounded, color: colorScheme.primary, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'سجل حركات - ${wallet.userName}',
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
                if (isFayezAtter && collectionsMetrics.accountantRemainingShare > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            const Text(
                              'تفصيل المستحقات الحالية (المحفظة + التحصيلات):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '• رصيد المحفظة المخصص: ${_formatCurrency(wallet.currentBalance)}\n'
                          '• حصة متبقي التحصيلات (${collectionsMetrics.accountantPercentage.toStringAsFixed(0)}%): ${_formatCurrency(collectionsMetrics.accountantRemainingShare)}\n'
                          '• الإجمالي المستحق للصرف: ${_formatCurrency(wallet.currentBalance + collectionsMetrics.accountantRemainingShare)}',
                          style: const TextStyle(fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 12),
                Expanded(
                  child: StreamBuilder<List<WalletTransactionModel>>(
                    stream: _dataSource.streamUserTransactions(wallet.userId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator.adaptive());
                      }

                      final transList = snapshot.data ?? [];
                      if (transList.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 40, color: colorScheme.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text(
                                'لا توجد حركات مسجلة لهذه المحفظة بعد.',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: transList.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        itemBuilder: (context, index) {
                          final item = transList[index];
                          final isCredit = item.type.isAllocation ||
                              item.type.isMonthlyRenewal ||
                              (item.type.isAdjustment && item.amount >= 0);
                          final amountColor = isCredit ? colorScheme.primary : colorScheme.error;
                          final dateStr = DateFormat('yyyy/MM/dd - hh:mm a').format(item.createdAt);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: amountColor.withValues(alpha: 0.12),
                                  child: Icon(
                                    isCredit ? Icons.add_rounded : Icons.remove_rounded,
                                    size: 16,
                                    color: amountColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.type.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      if (item.notes.isNotEmpty)
                                        Text(
                                          item.notes,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      Text(
                                        '$dateStr • بواسطة: ${item.createdByName}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isCredit ? '+' : '-'}${_formatAmountOnly(item.amount.abs())} ج.م',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: amountColor,
                                      ),
                                    ),
                                    Text(
                                      'الرصيد: ${_formatAmountOnly(item.balanceAfter)}',
                                      style: TextStyle(fontSize: 10, color: colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Export All Beneficiary Wallets to CSV ---
  Future<void> _exportAllWalletsCsv(List<UserWalletModel> wallets) async {
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات محافظ للتصدير')),
      );
      return;
    }

    try {
      final csvHeader =
          '\uFEFFاسم المستفيد,المسمى الوظيفي,الشركة,رقم الهاتف,الرصيد المتبقي للصرف,إجمالي المستحق,إجمالي المنصرف,حالة المحفظة,ملاحظات\n';
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
      final file = File('${directory.path}/accountant_beneficiary_wallets_$nowStr.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'كشف حسابات ومحافظ المستحقات المالية الداخلية',
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

  // --- Export Single Beneficiary Transactions to CSV ---
  Future<void> _exportSingleWalletTransactionsCsv(UserWalletModel wallet) async {
    try {
      final transSnap = await _dataSource.streamUserTransactions(wallet.userId).first;
      if (transSnap.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('لا توجد حركات مسجلة لمحفظة ${wallet.userName}')),
          );
        }
        return;
      }

      final csvHeader =
          '\uFEFFنوع الحركة,المبلغ,الرصيد قبل,الرصيد بعد,البيان,التاريخ والوقت,المسؤول\n';
      final csvRows = transSnap.map((t) {
        final type = t.type.displayName;
        final amt = t.amount.toStringAsFixed(2);
        final before = t.balanceBefore.toStringAsFixed(2);
        final after = t.balanceAfter.toStringAsFixed(2);
        final note = t.notes.replaceAll(',', ' ').replaceAll('\n', ' ');
        final date = DateFormat('yyyy-MM-dd HH:mm').format(t.createdAt);
        final by = t.createdByName.replaceAll(',', ' ');
        return '$type,$amt,$before,$after,$note,$date,$by';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/ledger_${wallet.userId}.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'كشف حركات محفظة المستفيد: ${wallet.userName}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التصدير: $e')),
        );
      }
    }
  }
}