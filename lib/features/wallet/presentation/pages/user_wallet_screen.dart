import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/wallet/data/datasources/wallet_remote_data_source.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';
import 'package:delegate_app/features/wallet/domain/entities/user_wallet_entity.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/injection_container.dart' as di;

class UserWalletScreen extends StatelessWidget {
  final String targetUserId;
  final String? targetUserName;
  final bool isReadOnlyView;

  const UserWalletScreen({
    super.key,
    required this.targetUserId,
    this.targetUserName,
    this.isReadOnlyView = false,
  });

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(amount)} ج.م';
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy/MM/dd • hh:mm a', 'ar').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dataSource = WalletRemoteDataSourceImpl();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          titleSpacing: 0,
          title: Text(
            targetUserName != null && targetUserName!.isNotEmpty
                ? 'محفظة مستحقات: $targetUserName'
                : 'محفظتي والمستحقات',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'عن المحفظة',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('محفظة المستحقات المالية'),
                    content: const Text(
                      'تعرض هذه المحفظة المبالغ المستحقة لك والمعتمدة من قبل الإدارة، بالإضافة إلى سجل عمليات الصرف والتسويات النقدية أولاً بأول.',
                      style: TextStyle(fontSize: 13, height: 1.5),
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
            ),
          ],
        ),
        body: FutureBuilder(
          future: di.sl<AuthRepository>().getCachedDelegate(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            final viewer = authSnapshot.data?.fold((l) => null, (r) => r);
            final isSuperAdmin = viewer?.role == UserRole.superAdmin;
            final isAccountant = viewer?.role == UserRole.accountant;
            final isFayez = viewer?.phoneNumber == '01001989360' ||
                (viewer?.fullName.toLowerCase().contains('fayez') ?? false);
            final isAuthorized = isSuperAdmin || isAccountant || isFayez;

            if (!isAuthorized) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        'غير مصرح بعرض المحفظة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'بيانات المحافظ والمستحقات سرية ومخصصة للإدارة العامة والمحاسب فقط.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return StreamBuilder<UserWalletModel?>(
              stream: dataSource.streamUserWallet(targetUserId),
              builder: (context, walletSnapshot) {
                if (walletSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator.adaptive());
                }

                final wallet = walletSnapshot.data;
                final currentBalance = wallet?.currentBalance ?? 0.0;
                final totalPaid = wallet?.totalPaid ?? 0.0;
                final isEnabled = wallet?.isWalletEnabled ?? false;

                if (wallet == null || (!isEnabled && !isReadOnlyView)) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 64, color: colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'المحفظة غير مفعلة حالياً',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'لم يتم تفعيل رصيد محفظة لحسابك من قبل الإدارة بعد.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1. Hero Balance Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: _buildHeroBalanceCard(
                          currentBalance: currentBalance,
                          totalPaid: totalPaid,
                          companyName: wallet.companyName,
                          theme: theme,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ),

                // 2. Transactions Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'سجل حركات المحفظة والتسويات',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Transactions Stream List
                StreamBuilder<List<WalletTransactionModel>>(
                  stream: dataSource.streamUserTransactions(targetUserId),
                  builder: (context, transSnapshot) {
                    if (transSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                              child: CircularProgressIndicator.adaptive()),
                        ),
                      );
                    }

                    final transactions = transSnapshot.data ?? [];

                    if (transactions.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(24),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_rounded,
                                  size: 42, color: colorScheme.outline),
                              const SizedBox(height: 10),
                              Text(
                                'لا توجد حركات مسجلة حتى الآن',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = transactions[index];
                            return _buildTransactionTile(
                              tx: tx,
                              theme: theme,
                              colorScheme: colorScheme,
                            );
                          },
                          childCount: transactions.length,
                        ),
                      ),
                    );
                  },
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

  Widget _buildHeroBalanceCard({
    required double currentBalance,
    required double totalPaid,
    required String companyName,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final hasBalance = currentBalance > 0;

    return Container(
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Company & Status
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
                    companyName.isNotEmpty ? companyName : 'رصيد المستحقات',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          // Main Balance Value
          Text(
            'الرصيد المستحق',
            style: TextStyle(
              color: colorScheme.onPrimary.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCurrency(currentBalance),
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: colorScheme.onPrimary.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 14),

          // Bottom Metric: إجمالي المنصرف فقط
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  size: 16, color: colorScheme.onPrimary.withValues(alpha: 0.85)),
              const SizedBox(width: 8),
              Text(
                'إجمالي المنصرف:',
                style: TextStyle(
                  color: colorScheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                _formatCurrency(totalPaid),
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile({
    required WalletTransactionModel tx,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final isAllocation = tx.type == WalletTransactionType.allocation;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAllocation
                    ? colorScheme.primaryContainer
                    : colorScheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAllocation
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: isAllocation
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onTertiaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAllocation ? 'تخصيص مستحقات' : 'صرف وتسوية نقدية',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        '${isAllocation ? '+' : '-'}${_formatCurrency(tx.amount)}',
                        style: TextStyle(
                          color: isAllocation
                              ? colorScheme.primary
                              : colorScheme.tertiary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (tx.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tx.notes,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDateTime(tx.createdAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.outline,
                        ),
                      ),
                      Text(
                        'الرصيد بعدها: ${_formatCurrency(tx.balanceAfter)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
