import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';

/// Aggregation model for company-level financial audit
class CompanyFinancialAudit {
  final String companyUID;
  final String companyName;
  final String organizationUID;
  final String organizationName;
  final int totalDelegates;
  final double totalAmount;

  // Breakdown by payment method
  final int companyDeductionCount;
  final double companyDeductionAmount;

  final int instaPayCount;
  final double instaPayAmount;

  final int branchReceiptCount;
  final double branchReceiptAmount;

  final List<DelegateSubscriptionRequest> requests;

  const CompanyFinancialAudit({
    required this.companyUID,
    required this.companyName,
    required this.organizationUID,
    required this.organizationName,
    required this.totalDelegates,
    required this.totalAmount,
    required this.companyDeductionCount,
    required this.companyDeductionAmount,
    required this.instaPayCount,
    required this.instaPayAmount,
    required this.branchReceiptCount,
    required this.branchReceiptAmount,
    required this.requests,
  });
}

class SuperAdminSubscriptionFinancialReportScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const SuperAdminSubscriptionFinancialReportScreen({
    super.key,
    required this.adminDelegate,
  });

  @override
  State<SuperAdminSubscriptionFinancialReportScreen> createState() =>
      _SuperAdminSubscriptionFinancialReportScreenState();
}

class _SuperAdminSubscriptionFinancialReportScreenState
    extends State<SuperAdminSubscriptionFinancialReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Filters
  String? _selectedCycle; // null means 'جميع الدورات'
  SubscriptionRequestStatus? _statusFilter = SubscriptionRequestStatus.approved;
  SubscriptionPaymentMethod? _paymentMethodFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final currencyFormatter = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م',
    decimalDigits: 0,
  );

  final dateFormatter = DateFormat('yyyy/MM/dd HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Strict Role Access Control: Super Admin and Accountant
    if (widget.adminDelegate.role != UserRole.superAdmin &&
        widget.adminDelegate.role != UserRole.accountant) {
      return Scaffold(
        appBar: AppBar(title: const Text('غير مصرح')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_bad_rounded, size: 64, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'عفواً، هذه الصفحة مخصصة لمدير النظام (السوبر أدمن) فقط لمتابعة الجرد المالي.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final repo = sl<DelegateSubscriptionRepository>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'التقرير المالي لاشتراكات المناديب',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تصدير كملف إكسل (CSV)',
            icon: const Icon(Icons.file_download_rounded),
            onPressed: () => _handleExportCSV(),
          ),
          IconButton(
            tooltip: 'مشاركة ملخص الجرد',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _handleShareSummary(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.apartment_rounded, size: 20),
              text: 'جرد الشركات',
            ),
            Tab(
              icon: Icon(Icons.receipt_long_rounded, size: 20),
              text: 'سجل العمليات التفصيلي',
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<DelegateSubscriptionRequest>>(
        stream: repo.getSubscriptionRequestsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('حدث خطأ أثناء تحميل البيانات: ${snapshot.error}'),
              ),
            );
          }

          final allRequests = snapshot.data ?? [];
          return _buildContent(context, theme, colorScheme, allRequests);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    List<DelegateSubscriptionRequest> allRequests,
  ) {
    // 1. Extract distinct available cycles from data plus current cycle
    final availableCycles = <String>{};
    final currentCycleCode = SubscriptionCycleHelper.getCycleCode();
    availableCycles.add(currentCycleCode);
    for (final req in allRequests) {
      if (req.subscriptionCycle.isNotEmpty) {
        availableCycles.add(req.subscriptionCycle);
      }
    }
    final sortedCycles = availableCycles.toList()..sort((a, b) => b.compareTo(a));

    // 2. Filter requests by Cycle, Status, and Search Query
    final filtered = allRequests.where((req) {
      // Cycle filter
      if (_selectedCycle != null && req.subscriptionCycle != _selectedCycle) {
        return false;
      }
      // Status filter
      if (_statusFilter != null && req.status != _statusFilter) {
        return false;
      }
      // Payment Method filter
      if (_paymentMethodFilter != null && req.paymentMethod != _paymentMethodFilter) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatch = req.fullName.toLowerCase().contains(query);
        final companyMatch = req.companyName.toLowerCase().contains(query);
        final phoneMatch = req.phoneNumber.contains(query);
        final nationalIdMatch = req.nationalId.contains(query);
        final codeMatch = (req.receiptCode ?? '').contains(query);
        if (!nameMatch && !companyMatch && !phoneMatch && !nationalIdMatch && !codeMatch) {
          return false;
        }
      }
      return true;
    }).toList();

    // 3. Compute High-Level Financial Metrics
    double totalRevenue = 0;
    int totalDelegates = filtered.length;

    int companyDeductionCount = 0;
    double companyDeductionAmount = 0;

    int instaPayCount = 0;
    double instaPayAmount = 0;

    int branchReceiptCount = 0;
    double branchReceiptAmount = 0;

    // Company-level aggregation
    final Map<String, List<DelegateSubscriptionRequest>> companyGroups = {};

    for (final req in filtered) {
      totalRevenue += req.fee;
      final key = req.companyUID.isNotEmpty ? req.companyUID : req.companyName;
      companyGroups.putIfAbsent(key, () => []).add(req);

      switch (req.paymentMethod) {
        case SubscriptionPaymentMethod.companyDeduction:
          companyDeductionCount++;
          companyDeductionAmount += req.fee;
          break;
        case SubscriptionPaymentMethod.instaPay:
          instaPayCount++;
          instaPayAmount += req.fee;
          break;
        case SubscriptionPaymentMethod.branchReceipt:
          branchReceiptCount++;
          branchReceiptAmount += req.fee;
          break;
        case SubscriptionPaymentMethod.freePromotion:
        case SubscriptionPaymentMethod.paymob:
        case SubscriptionPaymentMethod.notRequired:
          break;
      }
    }

    final List<CompanyFinancialAudit> companyAudits = companyGroups.entries.map((entry) {
      final reqs = entry.value;
      final first = reqs.first;
      double sum = 0;
      int dedCount = 0;
      double dedAmount = 0;
      int instaCount = 0;
      double instaPayAmt = 0;
      int branchCount = 0;
      double branchAmt = 0;

      for (final r in reqs) {
        sum += r.fee;
        switch (r.paymentMethod) {
          case SubscriptionPaymentMethod.companyDeduction:
            dedCount++;
            dedAmount += r.fee;
            break;
          case SubscriptionPaymentMethod.instaPay:
            instaCount++;
            instaPayAmt += r.fee;
            break;
          case SubscriptionPaymentMethod.branchReceipt:
            branchCount++;
            branchAmt += r.fee;
            break;
          case SubscriptionPaymentMethod.freePromotion:
          case SubscriptionPaymentMethod.paymob:
          case SubscriptionPaymentMethod.notRequired:
            break;
        }
      }

      return CompanyFinancialAudit(
        companyUID: first.companyUID,
        companyName: first.companyName,
        organizationUID: first.organizationUID,
        organizationName: first.organizationName,
        totalDelegates: reqs.length,
        totalAmount: sum,
        companyDeductionCount: dedCount,
        companyDeductionAmount: dedAmount,
        instaPayCount: instaCount,
        instaPayAmount: instaPayAmt,
        branchReceiptCount: branchCount,
        branchReceiptAmount: branchAmt,
        requests: reqs,
      );
    }).toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount)); // Highest revenue first

    // Store in state variables for export functions
    _lastFilteredRequests = filtered;
    _lastCompanyAudits = companyAudits;
    _lastTotalRevenue = totalRevenue;
    _lastTotalDelegates = totalDelegates;
    _lastCompanyDeductionAmount = companyDeductionAmount;
    _lastCompanyDeductionCount = companyDeductionCount;
    _lastInstaPayAmount = instaPayAmount;
    _lastInstaPayCount = instaPayCount;
    _lastBranchReceiptAmount = branchReceiptAmount;
    _lastBranchReceiptCount = branchReceiptCount;

    return Column(
      children: [
        // Filter Controls Header
        _buildFiltersHeader(theme, colorScheme, sortedCycles),

        // KPI Summary Dashboard (Horizontal scrollable or compact grid)
        _buildKpiDashboard(
          theme,
          colorScheme,
          totalRevenue: totalRevenue,
          totalDelegates: totalDelegates,
          totalCompanies: companyAudits.length,
          companyDeductionAmount: companyDeductionAmount,
          companyDeductionCount: companyDeductionCount,
          instaPayAmount: instaPayAmount,
          instaPayCount: instaPayCount,
          branchReceiptAmount: branchReceiptAmount,
          branchReceiptCount: branchReceiptCount,
        ),

        const Divider(height: 1),

        // Tabs Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Companies Audit
              _buildCompaniesTab(theme, colorScheme, companyAudits),

              // Tab 2: Detailed Transactions Log
              _buildTransactionsTab(theme, colorScheme, filtered),
            ],
          ),
        ),
      ],
    );
  }

  // Cached values for export
  List<DelegateSubscriptionRequest> _lastFilteredRequests = [];
  List<CompanyFinancialAudit> _lastCompanyAudits = [];
  double _lastTotalRevenue = 0;
  int _lastTotalDelegates = 0;
  double _lastCompanyDeductionAmount = 0;
  int _lastCompanyDeductionCount = 0;
  double _lastInstaPayAmount = 0;
  int _lastInstaPayCount = 0;
  double _lastBranchReceiptAmount = 0;
  int _lastBranchReceiptCount = 0;

  Widget _buildFiltersHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    List<String> sortedCycles,
  ) {
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'البحث باسم الشركة، المندوب، الهاتف، كود الإيصال...',
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
          const SizedBox(height: 6),

          // 2. Cycle & Status Animated Dropdown Row
          Row(
            children: [
              // Cycle Selector Dropdown
              Expanded(
                flex: 5,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _selectedCycle != null
                        ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedCycle != null
                          ? colorScheme.primary.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedCycle,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.public_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text('جميع الدورات', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                        ...sortedCycles.map((c) => DropdownMenuItem<String?>(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(Icons.event_note_rounded, size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text('دورة $c', overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (val) => setState(() => _selectedCycle = val),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Status Selector Dropdown (Animated & M3 Compliant)
              Expanded(
                flex: 6,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _statusFilter != null
                        ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _statusFilter != null
                          ? colorScheme.primary.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SubscriptionRequestStatus?>(
                      value: _statusFilter,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      items: [
                        DropdownMenuItem<SubscriptionRequestStatus?>(
                          value: SubscriptionRequestStatus.approved,
                          child: Row(
                            children: [
                              Icon(Icons.verified_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text('المعتمدة (المحصلة)', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem<SubscriptionRequestStatus?>(
                          value: SubscriptionRequestStatus.pending,
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_top_rounded, size: 16, color: colorScheme.secondary),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text('قيد الانتظار', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem<SubscriptionRequestStatus?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text('جميع الحالات (الكل)', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _statusFilter = val);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiDashboard(
    ThemeData theme,
    ColorScheme colorScheme, {
    required double totalRevenue,
    required int totalDelegates,
    required int totalCompanies,
    required double companyDeductionAmount,
    required int companyDeductionCount,
    required double instaPayAmount,
    required int instaPayCount,
    required double branchReceiptAmount,
    required int branchReceiptCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      child: Column(
        children: [
          // Row 1: Big Total Revenue Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.primaryContainer.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إجمالي المحصل / المطلوب',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                      Text(
                        currencyFormatter.format(totalRevenue),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalDelegates مندوب',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalCompanies شركة',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Row 2: Breakdown Cards for the 3 Payment Methods (M3 Single-Seed Tonal Palette)
          Row(
            children: [
              // 1. Company Deduction
              Expanded(
                child: _buildMethodSummaryCard(
                  title: 'خصم شركة',
                  amount: companyDeductionAmount,
                  count: companyDeductionCount,
                  icon: Icons.account_balance_rounded,
                  accentColor: colorScheme.primary,
                  bgColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  isSelected: _paymentMethodFilter == SubscriptionPaymentMethod.companyDeduction,
                  onTap: () {
                    setState(() {
                      if (_paymentMethodFilter == SubscriptionPaymentMethod.companyDeduction) {
                        _paymentMethodFilter = null;
                      } else {
                        _paymentMethodFilter = SubscriptionPaymentMethod.companyDeduction;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 2. InstaPay
              Expanded(
                child: _buildMethodSummaryCard(
                  title: 'انستاباي',
                  amount: instaPayAmount,
                  count: instaPayCount,
                  icon: Icons.flash_on_rounded,
                  accentColor: colorScheme.secondary,
                  bgColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  isSelected: _paymentMethodFilter == SubscriptionPaymentMethod.instaPay,
                  onTap: () {
                    setState(() {
                      if (_paymentMethodFilter == SubscriptionPaymentMethod.instaPay) {
                        _paymentMethodFilter = null;
                      } else {
                        _paymentMethodFilter = SubscriptionPaymentMethod.instaPay;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 3. Electronic Receipt
              Expanded(
                child: _buildMethodSummaryCard(
                  title: 'إيصال إلكتروني',
                  amount: branchReceiptAmount,
                  count: branchReceiptCount,
                  icon: Icons.receipt_long_rounded,
                  accentColor: colorScheme.tertiary,
                  bgColor: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                  isSelected: _paymentMethodFilter == SubscriptionPaymentMethod.branchReceipt,
                  onTap: () {
                    setState(() {
                      if (_paymentMethodFilter == SubscriptionPaymentMethod.branchReceipt) {
                        _paymentMethodFilter = null;
                      } else {
                        _paymentMethodFilter = SubscriptionPaymentMethod.branchReceipt;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSummaryCard({
    required String title,
    required double amount,
    required int count,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: AppMotionDurations.short4,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : bgColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : accentColor.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (title == 'انستاباي')
                  Container(
                    width: 16,
                    height: 16,
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Image.asset(
                      'assets/images/instapay_logo.png',
                      fit: BoxFit.contain,
                    ),
                  )
                else
                  Icon(icon, size: 14, color: accentColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              currencyFormatter.format(amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
            Text(
              '$count مندوب',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: accentColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= TAB 1: COMPANIES AUDIT =================
  Widget _buildCompaniesTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<CompanyFinancialAudit> companyAudits,
  ) {
    if (companyAudits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'لا توجد بيانات مالية مطابقة للفلاتر المحددة',
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: companyAudits.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final audit = companyAudits[index];
        return _buildCompanyCard(theme, colorScheme, audit, index + 1);
      },
    );
  }

  Widget _buildCompanyCard(
    ThemeData theme,
    ColorScheme colorScheme,
    CompanyFinancialAudit audit,
    int rank,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.primary,
          child: Text(
            '$rank',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(
          audit.companyName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (audit.organizationName.isNotEmpty)
              Text(
                audit.organizationName,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${audit.totalDelegates} مندوب',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currencyFormatter.format(audit.totalAmount),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          const Divider(height: 16),

          // Breakdown Pills Row (M3 Harmonious Tonal Badges)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (audit.companyDeductionCount > 0)
                _buildMiniBadge(
                  label: 'خصم شركة: ${currencyFormatter.format(audit.companyDeductionAmount)} (${audit.companyDeductionCount})',
                  color: colorScheme.primary,
                  bgColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  icon: Icons.account_balance_rounded,
                ),
              if (audit.instaPayCount > 0)
                _buildMiniBadge(
                  label: 'انستاباي: ${currencyFormatter.format(audit.instaPayAmount)} (${audit.instaPayCount})',
                  color: colorScheme.secondary,
                  bgColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  icon: Icons.flash_on_rounded,
                ),
              if (audit.branchReceiptCount > 0)
                _buildMiniBadge(
                  label: 'إيصال إلكتروني: ${currencyFormatter.format(audit.branchReceiptAmount)} (${audit.branchReceiptCount})',
                  color: colorScheme.tertiary,
                  bgColor: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                  icon: Icons.receipt_long_rounded,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Delegates Sub-list
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.people_outline_rounded, size: 15, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'المناديب المسجلين (${audit.requests.length}):',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...audit.requests.map((req) => _buildDelegateItem(theme, colorScheme, req)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge({
    required String label,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildDelegateItem(
    ThemeData theme,
    ColorScheme colorScheme,
    DelegateSubscriptionRequest req,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          // Delegate Name (Clean, single-line, bold)
          Expanded(
            child: Text(
              req.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Fee amount
          Text(
            currencyFormatter.format(req.fee),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),

          // Payment Method Badge (Compact M3)
          _buildPaymentMethodBadge(req.paymentMethod, isMini: true),

          // Receipt Image button if available
          if (req.receiptImageUrl != null && req.receiptImageUrl!.isNotEmpty) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _showReceiptImageDialog(context, req),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.image_search_rounded,
                  size: 15,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ================= TAB 2: DETAILED TRANSACTIONS LOG =================
  Widget _buildTransactionsTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<DelegateSubscriptionRequest> requests,
  ) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 56, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'لا توجد عمليات مسجلة مطابقة للفلاتر',
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = requests[index];
        return _buildTransactionCard(theme, colorScheme, req);
      },
    );
  }

  Widget _buildTransactionCard(
    ThemeData theme,
    ColorScheme colorScheme,
    DelegateSubscriptionRequest req,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Delegate Name + Status + Fee
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${req.companyName} • ${req.organizationName}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormatter.format(req.fee),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _buildStatusBadge(req.status),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),

            // Details Grid
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    label: 'طريقة الدفع',
                    child: _buildPaymentMethodBadge(req.paymentMethod),
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    label: 'الدورة',
                    value: req.subscriptionCycle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    label: 'هاتف المندوب',
                    value: req.phoneNumber,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    label: 'المشرف المسؤول',
                    value: req.supervisorName,
                  ),
                ),
              ],
            ),

            // Receipt Code & Preview (If applicable)
            if (req.receiptCode != null && req.receiptCode!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.confirmation_number_rounded, size: 16, color: colorScheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      'كود الإيصال الخماسي: ',
                      style: TextStyle(fontSize: 11, color: colorScheme.onTertiaryContainer),
                    ),
                    Text(
                      req.receiptCode!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (req.receiptImageUrl != null && req.receiptImageUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_search_rounded, size: 16),
                label: const Text('معاينة صورة الإيصال الإلكتروني', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showReceiptImageDialog(context, req),
              ),
            ],

            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                dateFormatter.format(req.createdAt),
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required String label,
    String? value,
    Widget? child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 2),
        child ??
            Text(
              value ?? '-',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
      ],
    );
  }

  Widget _buildPaymentMethodBadge(SubscriptionPaymentMethod method, {bool isMini = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, icon, color, bg) = switch (method) {
      SubscriptionPaymentMethod.companyDeduction => (
          'خصم شركة',
          Icons.account_balance_rounded,
          colorScheme.primary,
          colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionPaymentMethod.instaPay => (
          'انستاباي',
          Icons.flash_on_rounded,
          colorScheme.secondary,
          colorScheme.secondaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionPaymentMethod.branchReceipt => (
          'إيصال إلكتروني',
          Icons.receipt_long_rounded,
          colorScheme.tertiary,
          colorScheme.tertiaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionPaymentMethod.freePromotion => (
          'عرض مجاني',
          Icons.card_giftcard_rounded,
          const Color(0xFF16A34A),
          const Color(0xFFDCFCE7),
        ),
      SubscriptionPaymentMethod.paymob => (
          'Paymob',
          Icons.credit_card_rounded,
          colorScheme.primary,
          colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionPaymentMethod.notRequired => (
          'بدون رسوم',
          Icons.link_rounded,
          colorScheme.onSurfaceVariant,
          colorScheme.surfaceContainerHigh,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMini ? 6 : 8,
        vertical: isMini ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (method == SubscriptionPaymentMethod.instaPay)
            Image.asset(
              'assets/images/instapay_logo.png',
              width: isMini ? 12 : 14,
              height: isMini ? 12 : 14,
              fit: BoxFit.contain,
            )
          else
            Icon(icon, size: isMini ? 11 : 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isMini ? 10 : 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SubscriptionRequestStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, icon, color, bg) = switch (status) {
      SubscriptionRequestStatus.approved => (
          'معتمد',
          Icons.check_circle_rounded,
          colorScheme.primary,
          colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionRequestStatus.pending => (
          'معلق',
          Icons.hourglass_top_rounded,
          colorScheme.secondary,
          colorScheme.secondaryContainer.withValues(alpha: 0.4),
        ),
      SubscriptionRequestStatus.rejected => (
          'مرفوض',
          Icons.cancel_rounded,
          colorScheme.error,
          colorScheme.errorContainer.withValues(alpha: 0.4),
        ),
      SubscriptionRequestStatus.cancelled => (
          'ملغى',
          Icons.block_rounded,
          Colors.grey.shade700,
          Colors.grey.withValues(alpha: 0.14),
        ),
      SubscriptionRequestStatus.expired => (
          'منتهٍ',
          Icons.timer_off_rounded,
          Colors.orange.shade800,
          Colors.orange.withValues(alpha: 0.14),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // ================= RECEIPT IMAGE DIALOG =================
  void _showReceiptImageDialog(BuildContext context, DelegateSubscriptionRequest req) {
    if (req.receiptImageUrl == null || req.receiptImageUrl!.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text(
                'إيصال: ${req.fullName}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            if (req.receiptCode != null && req.receiptCode!.isNotEmpty)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  'كود الإيصال الخماسي: ${req.receiptCode}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: req.receiptImageUrl!,
                fit: BoxFit.contain,
                height: 380,
                placeholder: (context, url) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator.adaptive(),
                  ),
                ),
                errorWidget: (context, url, error) => const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(
                    child: Text('فشل تحميل صورة الإيصال'),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= EXPORT & SHARING =================
  Future<void> _handleExportCSV() async {
    if (_lastFilteredRequests.isEmpty) {
      AppSnackBar.showError(context, 'لا توجد بيانات متاحة للتصدير');
      return;
    }

    try {
      // 1. Build CSV Header & Rows (with UTF-8 BOM for Excel Arabic support)
      final buffer = StringBuffer();
      buffer.write('\uFEFF'); // UTF-8 BOM

      buffer.writeln('م,اسم الشركة,اسم المنظمة,اسم المندوب,رقم الهاتف,الرقم القومي,الدورة,المبلغ (ج.م),طريقة الدفع,كود الإيصال,حالة الطلب,المشرف,تاريخ الطلب');

      int index = 1;
      for (final req in _lastFilteredRequests) {
        final paymentText = switch (req.paymentMethod) {
          SubscriptionPaymentMethod.companyDeduction => 'خصم من حساب الشركة',
          SubscriptionPaymentMethod.instaPay => 'تحويل انستاباي',
          SubscriptionPaymentMethod.branchReceipt => 'إيصال إلكتروني من تسويق الفرع',
          SubscriptionPaymentMethod.freePromotion => 'عرض ترويجي مجاني',
          SubscriptionPaymentMethod.paymob => 'دفع إلكتروني Paymob',
          SubscriptionPaymentMethod.notRequired => 'بدون رسوم',
        };

        final statusText = switch (req.status) {
          SubscriptionRequestStatus.approved => 'معتمد',
          SubscriptionRequestStatus.pending => 'قيد الانتظار',
          SubscriptionRequestStatus.rejected => 'مرفوض',
          SubscriptionRequestStatus.cancelled => 'ملغى',
          SubscriptionRequestStatus.expired => 'منتهٍ',
        };

        buffer.writeln(
          '$index,'
          '"${req.companyName.replaceAll('"', '""')}",'
          '"${req.organizationName.replaceAll('"', '""')}",'
          '"${req.fullName.replaceAll('"', '""')}",'
          '"${req.phoneNumber}",'
          '"${req.nationalId}",'
          '"${req.subscriptionCycle}",'
          '${req.fee},'
          '"$paymentText",'
          '"${req.receiptCode ?? ''}",'
          '"$statusText",'
          '"${req.supervisorName.replaceAll('"', '""')}",'
          '"${dateFormatter.format(req.createdAt)}"',
        );
        index++;
      }

      // 2. Write to temp file
      final dir = await getTemporaryDirectory();
      final cycleSuffix = _selectedCycle ?? 'all_cycles';
      final file = File('${dir.path}/financial_subscription_report_$cycleSuffix.csv');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'التقرير المالي لاشتراكات المناديب (${_selectedCycle ?? "جميع الدورات"})',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'فشل تصدير التقرير: $e');
      }
    }
  }

  Future<void> _handleShareSummary() async {
    if (_lastFilteredRequests.isEmpty) {
      AppSnackBar.showError(context, 'لا توجد بيانات متاحة للمشاركة');
      return;
    }

    final cycleText = _selectedCycle != null ? 'دورة $_selectedCycle' : 'جميع الدورات';
    final statusText = _statusFilter != null
        ? (_statusFilter == SubscriptionRequestStatus.approved ? 'المعتمدة فقط' : 'قيد الانتظار')
        : 'جميع الحالات';

    final textBuffer = StringBuffer();
    textBuffer.writeln('📊 *تقرير الجرد المالي لاشتراكات المناديب*');
    textBuffer.writeln('🗓️ الفترة: $cycleText ($statusText)');
    textBuffer.writeln('💰 إجمالي المبالغ: ${currencyFormatter.format(_lastTotalRevenue)}');
    textBuffer.writeln('👥 إجمالي المناديب: $_lastTotalDelegates مندوب');
    textBuffer.writeln('🏢 إجمالي الشركات: ${_lastCompanyAudits.length} شركة');
    textBuffer.writeln('----------------------------------');
    textBuffer.writeln('💳 *تفصيل طرق الدفع:*');
    textBuffer.writeln('• خصم من حساب الشركة: ${currencyFormatter.format(_lastCompanyDeductionAmount)} ($_lastCompanyDeductionCount مندوب)');
    textBuffer.writeln('• تحويل انستاباي: ${currencyFormatter.format(_lastInstaPayAmount)} ($_lastInstaPayCount مندوب)');
    textBuffer.writeln('• إيصال إلكتروني: ${currencyFormatter.format(_lastBranchReceiptAmount)} ($_lastBranchReceiptCount مندوب)');
    textBuffer.writeln('----------------------------------');
    textBuffer.writeln('📋 *جرد الشركات الأعلى تحصيلاً:*');

    int rank = 1;
    for (final c in _lastCompanyAudits.take(10)) {
      textBuffer.writeln('$rank. ${c.companyName}: ${c.totalDelegates} مندوب - ${currencyFormatter.format(c.totalAmount)}');
      rank++;
    }
    if (_lastCompanyAudits.length > 10) {
      textBuffer.writeln('... بالإضافة إلى ${_lastCompanyAudits.length - 10} شركة أخرى');
    }

    textBuffer.writeln('----------------------------------');
    textBuffer.writeln('تم إنشاء التقرير آلياً عبر نظام إدارة المناديب.');

    // ignore: deprecated_member_use
    await Share.share(
      textBuffer.toString(),
      subject: 'تقرير الجرد المالي لاشتراكات المناديب',
    );
  }
}
