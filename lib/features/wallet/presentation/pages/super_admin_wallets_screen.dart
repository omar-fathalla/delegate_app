import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';
import 'user_wallet_screen.dart';

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

                // 2. Search Box and Filter Chips
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
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('all', 'الكل (${allWallets.length})'),
                              const SizedBox(width: 8),
                              _buildFilterChip('enabled', 'المفعلة 🟢 ($activeWalletsCount)'),
                              const SizedBox(width: 8),
                              _buildFilterChip('positive_balance', 'ذات رصيد مستحق 💰'),
                              const SizedBox(width: 8),
                              _buildFilterChip('disabled', 'المعطلة ⚪'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Wallets Table Header
                if (filteredWallets.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _buildTableHeader(colorScheme),
                    ),
                  ),

                // 4. Wallets List
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final wallet = filteredWallets[index];
                          return _buildWalletRow(
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

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = key);
        }
      },
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'الموقف المالي لمحافظ المستحقات',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
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
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  /// رأس جدول المحافظ (Table Header)
  Widget _buildTableHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Column 1: User
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 15, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  'المستخدم',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Column 2: Due Balance
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payments_rounded,
                    size: 15, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'المستحق',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Column 3: Actions & M3 Switch
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.tune_rounded,
                    size: 15, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'التحكم / صرف',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// صف المحفظة المدمج بنظام الجدول (Compact Table Row)
  Widget _buildWalletRow({
    required UserWalletModel wallet,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final hasBalance = wallet.currentBalance > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: wallet.isWalletEnabled
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: wallet.isWalletEnabled
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: wallet.isWalletEnabled ? 1.2 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // 1. Column 1: User (Avatar + Name + Role Badge) - NO phone number
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            wallet.userName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: wallet.isWalletEnabled
                                  ? null
                                  : colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (wallet.userRole.isNotEmpty ||
                              wallet.companyName.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              wallet.userRole.isNotEmpty
                                  ? wallet.userRole
                                  : wallet.companyName,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Column 2: Due Balance (Google Icons + Amount) - NO long text
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasBalance
                            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasBalance
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasBalance
                                  ? Icons.account_balance_wallet_rounded
                                  : Icons.wallet_rounded,
                              size: 13,
                              color: hasBalance
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _formatAmountOnly(wallet.currentBalance),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: hasBalance
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (wallet.totalPaid > 0) ...[
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded,
                                size: 10, color: colorScheme.outline),
                            const SizedBox(width: 2),
                            Text(
                              _formatAmountOnly(wallet.totalPaid),
                              style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Column 3: Actions (Payout + History + Material 3 Switch)
              Expanded(
                flex: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Payout Google Icon
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        hasBalance
                            ? Icons.price_check_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: hasBalance
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                      ),
                      tooltip:
                          hasBalance ? 'تسجيل صرف / سداد' : 'تمت التسوية بالكامل',
                      onPressed: hasBalance
                          ? () => _showPayoutDialog(context, wallet)
                          : null,
                    ),

                    // History Google Icon
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        Icons.history_rounded,
                        size: 19,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'سجل الحركات',
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
                    ),

                    // Material 3 Switch with check/close Thumb Icons
                    Transform.scale(
                      scale: 0.75,
                      child: Switch(
                        value: wallet.isWalletEnabled,
                        thumbIcon:
                            WidgetStateProperty.resolveWith<Icon?>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Icon(Icons.check_rounded,
                                size: 14, color: colorScheme.onPrimary);
                          }
                          return Icon(Icons.close_rounded,
                              size: 14, color: colorScheme.outline);
                        }),
                        activeTrackColor: colorScheme.primary,
                        activeThumbColor: colorScheme.onPrimary,
                        inactiveThumbColor: colorScheme.outline,
                        inactiveTrackColor:
                            colorScheme.surfaceContainerHighest,
                        trackOutlineColor:
                            WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.transparent;
                          }
                          return colorScheme.outlineVariant;
                        }),
                        onChanged: (val) async {
                          HapticFeedback.mediumImpact();
                          await _dataSource.toggleWalletStatus(
                            userId: wallet.userId,
                            isEnabled: val,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    bool isLoadingUsers = false;
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
            void performSearch(String query) async {
              if (query.trim().isEmpty) {
                setModalState(() => searchResults = []);
                return;
              }
              setModalState(() => isLoadingUsers = true);
              final results = await _dataSource.searchUsers(query);
              setModalState(() {
                searchResults = results;
                isLoadingUsers = false;
              });
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
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
                                  color: colorScheme.primary, size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                'تخصيص رصيد محفظة لمستخدم',
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

                      // Step 1: Select User
                      const Text(
                        '1. اختيار المستخدم المستهدف:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      if (selectedUser == null) ...[
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم، الهاتف، أو الشركة...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onChanged: performSearch,
                        ),
                        if (isLoadingUsers)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                                child: CircularProgressIndicator.adaptive()),
                          )
                        else if (searchResults.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: searchResults.length,
                              separatorBuilder: (context, index) =>
                                   Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                              itemBuilder: (c, i) {
                                final user = searchResults[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    user['name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    '${user['phone']} • ${user['companyName']} (${user['role']})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  onTap: () {
                                    setModalState(() {
                                      selectedUser = user;
                                      searchResults = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                child: Text(
                                  selectedUser!['name']!.isNotEmpty
                                      ? selectedUser!['name']![0]
                                      : 'U',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedUser!['name'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      '${selectedUser!['phone']} • ${selectedUser!['companyName']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setModalState(() => selectedUser = null);
                                },
                                child: const Text('تغيير'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Step 2: Amount
                      const Text(
                        '2. المبلغ المراد تخصيصه (ج.م):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                      const SizedBox(height: 20),

                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () async {
                            if (selectedUser == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('يرجى اختيار المستخدم أولاً')),
                              );
                              return;
                            }

                            final amt =
                                double.tryParse(amountController.text.trim()) ??
                                    0.0;
                            if (amt <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('يرجى إدخال مبلغ صحيح')),
                              );
                              return;
                            }

                            Navigator.pop(ctx);

                            try {
                              await _dataSource.allocateBalance(
                                userId: selectedUser!['id']!,
                                userName: selectedUser!['name']!,
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
                              );

                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تم تخصيص ${_formatCurrency(amt)} لمحفظة ${selectedUser!['name']} بنجاح وتفعيلها في حسابه!',
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text(
                            'تأكيد وتخصيص الرصيد',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final colorScheme = Theme.of(modalContext).colorScheme;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
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

                    // Notes Field
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
                      height: 48,
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
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                const Text('عن نظام المحافظ والمستحقات'),
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
