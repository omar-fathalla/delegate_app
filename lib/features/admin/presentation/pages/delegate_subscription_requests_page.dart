import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'super_admin_subscription_financial_report_screen.dart';

class DelegateSubscriptionRequestsPage extends StatefulWidget {
  final Delegate currentAdmin;

  const DelegateSubscriptionRequestsPage({
    super.key,
    required this.currentAdmin,
  });

  @override
  State<DelegateSubscriptionRequestsPage> createState() =>
      _DelegateSubscriptionRequestsPageState();
}

class _DelegateSubscriptionRequestsPageState
    extends State<DelegateSubscriptionRequestsPage> {
  SubscriptionRequestStatus? _statusFilter = SubscriptionRequestStatus.pending;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final repo = sl<DelegateSubscriptionRepository>();

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          widget.currentAdmin.role == UserRole.admin
              ? 'متابعة اعتمادات وطلبات المناديب'
              : 'طلبات تسجيل واشتراك المناديب',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (widget.currentAdmin.role == UserRole.superAdmin)
            IconButton(
              icon: const Icon(Icons.analytics_rounded),
              tooltip: 'التقرير المالي والجرد',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SuperAdminSubscriptionFinancialReportScreen(
                      adminDelegate: widget.currentAdmin,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<List<DelegateSubscriptionRequest>>(
        stream: repo.getSubscriptionRequestsStream(
          statusFilter: null,
          companyUID: widget.currentAdmin.role == UserRole.admin
              ? widget.currentAdmin.companyUID
              : null,
          organizationUID: widget.currentAdmin.role == UserRole.organizationAdmin
              ? widget.currentAdmin.organizationUID
              : null,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'حدث خطأ أثناء تحميل الطلبات: ${snapshot.error}',
                      style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          var allRequests = snapshot.data ?? [];

          // Dual-layer company isolation
          if (widget.currentAdmin.role == UserRole.admin &&
              widget.currentAdmin.companyUID.isNotEmpty) {
            allRequests = allRequests
                .where((r) => r.companyUID == widget.currentAdmin.companyUID)
                .toList();
          }

          // Real-time status counts
          final pendingCount = allRequests
              .where((r) => r.status == SubscriptionRequestStatus.pending)
              .length;
          final approvedCount = allRequests
              .where((r) => r.status == SubscriptionRequestStatus.approved)
              .length;
          final rejectedCount = allRequests
              .where((r) => r.status == SubscriptionRequestStatus.rejected)
              .length;
          final totalCount = allRequests.length;

          // Filter by status
          var displayedRequests = allRequests;
          if (_statusFilter != null) {
            displayedRequests = displayedRequests
                .where((r) => r.status == _statusFilter)
                .toList();
          }

          // Filter by search query
          if (_searchQuery.isNotEmpty) {
            displayedRequests = displayedRequests.where((r) {
              return r.fullName.toLowerCase().contains(_searchQuery) ||
                  r.companyName.toLowerCase().contains(_searchQuery) ||
                  r.organizationName.toLowerCase().contains(_searchQuery) ||
                  r.phoneNumber.contains(_searchQuery) ||
                  (r.receiptCode ?? '').toLowerCase().contains(_searchQuery);
            }).toList();
          }

          return Column(
            children: [
              // 1. Search Bar & Status Connected Button Group Toolbar
              _buildToolbar(
                context,
                colorScheme,
                pendingCount,
                approvedCount,
                rejectedCount,
                totalCount,
              ),

              Divider(
                height: 1,
                thickness: 0.8,
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),

              // 2. Request List or Empty State
              Expanded(
                child: displayedRequests.isEmpty
                    ? _buildEmptyState(context, colorScheme)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: displayedRequests.length,
                        itemBuilder: (context, index) {
                          final request = displayedRequests[index];
                          return _SubscriptionRequestCard(
                            request: request,
                            currentAdmin: widget.currentAdmin,
                            onApprove: () => _handleApprove(request),
                            onReject: () => _handleReject(request),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ColorScheme colorScheme,
    int pendingCount,
    int approvedCount,
    int rejectedCount,
    int totalCount,
  ) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    final searchWidget = _buildSearchField(colorScheme);
    final countBadge = _buildSummaryCountBadge(colorScheme, totalCount);

    final statusButtonGroup = TashilConnectedButtonGroup<SubscriptionRequestStatus?>(
      height: 44.0,
      width: isWide ? null : double.infinity,
      isScrollable: false,
      selectedValue: _statusFilter,
      onSelected: (val) => setState(() => _statusFilter = val),
      items: [
        TashilConnectedButtonItem<SubscriptionRequestStatus?>(
          value: null,
          label: 'الكل',
          count: totalCount,
          icon: Icons.filter_list_rounded,
          activeColor: colorScheme.primary,
          activeForegroundColor: colorScheme.onPrimary,
        ),
        TashilConnectedButtonItem<SubscriptionRequestStatus?>(
          value: SubscriptionRequestStatus.pending,
          label: 'قيد الانتظار',
          count: pendingCount,
          icon: Icons.hourglass_top_rounded,
          activeColor: colorScheme.primary,
          activeForegroundColor: colorScheme.onPrimary,
        ),
        TashilConnectedButtonItem<SubscriptionRequestStatus?>(
          value: SubscriptionRequestStatus.approved,
          label: 'المعتمدة',
          count: approvedCount,
          icon: Icons.verified_rounded,
          activeColor: colorScheme.primary,
          activeForegroundColor: colorScheme.onPrimary,
        ),
        TashilConnectedButtonItem<SubscriptionRequestStatus?>(
          value: SubscriptionRequestStatus.rejected,
          label: 'المرفوضة',
          count: rejectedCount,
          icon: Icons.cancel_rounded,
          activeColor: colorScheme.primary,
          activeForegroundColor: colorScheme.onPrimary,
        ),
      ],
    );

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(
          children: [
            Expanded(child: searchWidget),
            const SizedBox(width: 12),
            statusButtonGroup,
            const SizedBox(width: 8),
            countBadge,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: searchWidget),
              const SizedBox(width: 8),
              countBadge,
            ],
          ),
          const SizedBox(height: 10),
          statusButtonGroup,
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme colorScheme) {
    return AnimatedContainer(
      duration: AppMotionDurations.short3,
      curve: AppMotionCurves.standard,
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isSearchFocused
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: _isSearchFocused ? 1.5 : 1.0,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'البحث باسم المندوب، الشركة، أو الهاتف...',
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: _isSearchFocused ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          suffixIcon: AnimatedSwitcher(
            duration: AppMotionDurations.short3,
            switchInCurve: AppMotionCurves.standardDecelerate,
            switchOutCurve: AppMotionCurves.standardAccelerate,
            child: _searchQuery.isNotEmpty
                ? IconButton(
                    key: const ValueKey('clear_search_btn'),
                    icon: Icon(Icons.close_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : const SizedBox.shrink(key: ValueKey('empty_search_suffix')),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
      ),
    );
  }

  Widget _buildSummaryCountBadge(ColorScheme colorScheme, int totalCount) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.how_to_reg_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'الإجمالي: $totalCount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    IconData icon;
    String title;
    String subtitle;

    if (_searchQuery.isNotEmpty) {
      icon = Icons.search_off_rounded;
      title = 'لا توجد نتائج مطابقة للبحث';
      subtitle = 'جرب البحث باسم آخر أو رقم هاتف مختلف';
    } else if (_statusFilter == SubscriptionRequestStatus.pending) {
      icon = Icons.assignment_turned_in_rounded;
      title = 'لا توجد طلبات اشتراك معلقة حالياً';
      subtitle = 'تمت مراجعة واعتماد كافة طلبات المناديب المسجلة بنجاح';
    } else if (_statusFilter == SubscriptionRequestStatus.approved) {
      icon = Icons.verified_user_outlined;
      title = 'لا توجد طلبات معتمدة';
      subtitle = 'لم يتم اعتماد أي طلبات في هذه الدورة حتى الآن';
    } else if (_statusFilter == SubscriptionRequestStatus.rejected) {
      icon = Icons.cancel_outlined;
      title = 'لا توجد طلبات مرفوضة';
      subtitle = 'سجل الطلبات المرفوضة فارغ تماماً';
    } else {
      icon = Icons.inbox_rounded;
      title = 'لا توجد طلبات اشتراك';
      subtitle = 'لم يتم تقديم أي طلبات تسجيل حتى الآن';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                icon,
                size: 38,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isNotEmpty || _statusFilter != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _statusFilter = null;
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('عرض جميع الطلبات', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleApprove(DelegateSubscriptionRequest request) async {
    final isDelete = request.requestType == 'delete_delegate';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isDelete ? Icons.delete_forever_rounded : Icons.check_circle_rounded,
              color: isDelete ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(
              isDelete ? 'تأكيد حذف المندوب نهائياً' : 'تأكيد الاعتماد',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          isDelete
              ? 'هل أنت متأكد من الموافقة على طلب الحذف للمندوب "${request.fullName}" المقدم من المشرف ${request.supervisorName}؟\n\n'
                  '⚠️ تحذير: سيتم حذف المندوب وكافة بياناته وسجلاته نهائياً من قاعدة البيانات والمنظومة، ولا يمكن التراجع عن هذا الإجراء.\n\n'
                  '${request.rejectionReason?.isNotEmpty == true ? "سبب طلب الحذف: ${request.rejectionReason}" : ""}'
              : request.requestType == 'add_organization'
                  ? 'هل أنت متأكد من الموافقة على ربط المندوب "${request.fullName}" بسلسلة "${request.organizationName}" وتفعيل اشتراكه بقيمة ${request.fee.toInt()} ج.م (${request.remainingMonths} أشهر)؟\n\n'
                      'طريقة الدفع: ${request.paymentMethod.displayName}${request.receiptCode != null ? " (كود: ${request.receiptCode})" : ""}'
                  : 'هل أنت متأكد من اعتماد المندوب "${request.fullName}" وتفعيل اشتراكه بقيمة ${request.fee.toInt()} ج.م (${request.remainingMonths} أشهر) حتى نهاية دورة ${request.subscriptionCycle}؟\n\n'
                      'طريقة الدفع: ${request.paymentMethod.displayName}${request.receiptCode != null ? " (كود: ${request.receiptCode})" : ""}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDelete ? Colors.red.shade700 : Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isDelete ? 'تأكيد الحذف النهائي' : 'اعتماد وتفعيل'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.approveSubscriptionRequest(
      request: request,
      reviewerUid: widget.currentAdmin.uid,
      reviewerName: widget.currentAdmin.fullName,
    );

    if (!mounted) return;

    final failure = result.fold((f) => f, (_) => null);
    if (failure is ApprovalFollowUpFailure) {
      await _retryApprovalFollowUps(failure);
      return;
    }
    result.fold(
      (failure) => AppSnackBar.showError(context, failure.message),
      (_) => AppSnackBar.showSuccess(
        context,
        isDelete
            ? 'تم حذف المندوب ${request.fullName} نهائياً من المنظومة بنجاح.'
            : 'تم اعتماد المندوب ${request.fullName} بنجاح وتفعيل حسابه!',
      ),
    );
  }

  /// The approval committed but the delegate's account record did not; keep
  /// offering a retry of the follow-up writes until they succeed or the
  /// reviewer closes the dialog.
  Future<void> _retryApprovalFollowUps(ApprovalFollowUpFailure failure) async {
    var message = failure.message;
    while (mounted) {
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('إكمال اعتماد المندوب'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
      if (retry != true || !mounted) return;
      final r = await failure.retry();
      if (!mounted) return;
      final f = r.fold((f) => f, (_) => null);
      if (f == null) {
        AppSnackBar.showSuccess(context, 'تم إكمال بيانات حساب المندوب بنجاح.');
        return;
      }
      message = f.message;
    }
  }

  Future<void> _handleReject(DelegateSubscriptionRequest request) async {
    final isDelete = request.requestType == 'delete_delegate';
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              isDelete ? 'رفض طلب حذف المندوب' : 'رفض طلب المندوب',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isDelete
                  ? 'يرجى توضيح سبب رفض طلب حذف المندوب "${request.fullName}":'
                  : 'يرجى توضيح سبب رفض طلب المندوب "${request.fullName}":',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب سبب الرفض هنا...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                AppSnackBar.showError(ctx, 'يرجى إدخال سبب الرفض');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.rejectSubscriptionRequest(
      request: request,
      reason: reasonController.text.trim(),
      reviewerUid: widget.currentAdmin.uid,
      reviewerName: widget.currentAdmin.fullName,
    );

    if (!mounted) return;

    result.fold(
      (failure) => AppSnackBar.showError(context, failure.message),
      (_) => AppSnackBar.showSuccess(
        context,
        isDelete
            ? 'تم رفض طلب حذف المندوب ${request.fullName}.'
            : 'تم رفض الطلب وإشعار المشرف بالسبب.',
      ),
    );
  }
}

class _SubscriptionRequestCard extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final Delegate currentAdmin;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SubscriptionRequestCard({
    required this.request,
    required this.currentAdmin,
    required this.onApprove,
    required this.onReject,
  });

  void _showImageDialog(BuildContext context, String title, String imageUrl) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => SizedBox(
                      height: 140,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 44, color: colorScheme.error),
                            const SizedBox(height: 8),
                            Text(
                              'فشل تحميل الصورة',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateStr = DateFormat('yyyy/MM/dd • hh:mm a').format(request.createdAt);

    final Color statusColor;
    if (request.requestType == 'delete_delegate') {
      switch (request.status) {
        case SubscriptionRequestStatus.pending:
          statusColor = Colors.red.shade700;
          break;
        case SubscriptionRequestStatus.approved:
          statusColor = Colors.grey.shade600;
          break;
        case SubscriptionRequestStatus.rejected:
          statusColor = colorScheme.error;
          break;
      }
    } else {
      switch (request.status) {
        case SubscriptionRequestStatus.pending:
          statusColor = colorScheme.primary;
          break;
        case SubscriptionRequestStatus.approved:
          statusColor = const Color(0xFF16A34A);
          break;
        case SubscriptionRequestStatus.rejected:
          statusColor = colorScheme.error;
          break;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 3.5px start border stripe for status indication (Single-Seed Standard)
            Container(
              width: 3.5,
              color: statusColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (request.requestType == 'delete_delegate') ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_forever_rounded,
                              size: 16,
                              color: Colors.red.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'طلب حذف مندوب نهائياً من المنظومة',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (request.requestType == 'add_organization') ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_business_rounded,
                              size: 15,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'طلب ربط بسلسلة إضافية: ${request.currentOrganizationName?.isNotEmpty == true ? request.currentOrganizationName! : "المنظمة الحالية"} ➔ ${request.organizationName}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Row 1: Badges (Org + Company + Status)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.corporate_fare_rounded, size: 13, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                request.organizationName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            request.companyName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _buildStatusBadge(
                          request.status,
                          colorScheme,
                          isDeleteRequest: request.requestType == 'delete_delegate',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Row 2: Avatar + Delegate info
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _showImageDialog(
                            context,
                            'الصورة الشخصية - ${request.fullName}',
                            request.profileImageUrl,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: request.profileImageUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 50,
                                height: 50,
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.person_rounded, color: colorScheme.outlineVariant),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 50,
                                height: 50,
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.person_rounded, color: colorScheme.outlineVariant),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.phone_rounded, size: 12, color: colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    request.phoneNumber,
                                    style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.badge_rounded, size: 12, color: colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    request.nationalId,
                                    style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${request.supervisorName} • $dateStr',
                                style: TextStyle(fontSize: 10, color: colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // Row 3: Payment & Cycle info + Document Icon Buttons or Deletion Details
                    if (request.requestType == 'delete_delegate')
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      request.rejectionReason != null && request.rejectionReason!.trim().isNotEmpty
                                          ? 'سبب طلب الحذف: ${request.rejectionReason}'
                                          : 'طلب حذف مقدم من المشرف بدون سبب إضافي',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (request.nationalIdFrontUrl.isNotEmpty || request.nationalIdBackUrl.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (request.nationalIdFrontUrl.isNotEmpty)
                                  IconButton.outlined(
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'وجه البطاقة',
                                    icon: const Icon(Icons.badge_outlined, size: 16),
                                    onPressed: () => _showImageDialog(
                                      context,
                                      'بطاقة الرقم القومي (الوجه) - ${request.fullName}',
                                      request.nationalIdFrontUrl,
                                    ),
                                  ),
                                if (request.nationalIdBackUrl.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  IconButton.outlined(
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'ظهر البطاقة',
                                    icon: const Icon(Icons.flip_rounded, size: 16),
                                    onPressed: () => _showImageDialog(
                                      context,
                                      'بطاقة الرقم القومي (الظهر) - ${request.fullName}',
                                      request.nationalIdBackUrl,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      )
                    else
                      Row(
                        children: [
                          // Payment Method & Fee
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (request.paymentMethod == SubscriptionPaymentMethod.freePromotion)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF86EFAC)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.card_giftcard_rounded, size: 13, color: Color(0xFF16A34A)),
                                        SizedBox(width: 4),
                                        Text(
                                          'عرض مجاني (0 ج.م)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF15803D),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (request.paymentMethod == SubscriptionPaymentMethod.companyDeduction)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'خصم شركة',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  )
                                else if (request.paymentMethod == SubscriptionPaymentMethod.instaPay) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6B21A8).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/images/instapay_logo.png',
                                          width: 14,
                                          height: 14,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'انستاباي',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF9333EA),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (request.receiptImageUrl != null)
                                    IconButton.filledTonal(
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'عرض إشعار تحويل انستاباي',
                                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                                      onPressed: () => _showImageDialog(
                                        context,
                                        'إشعار تحويل انستاباي - ${request.fullName}',
                                        request.receiptImageUrl!,
                                      ),
                                    ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'إيصال إلكتروني',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'كود: ${request.receiptCode ?? "-"}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (request.receiptImageUrl != null)
                                    IconButton.filledTonal(
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'عرض الإيصال الإلكتروني',
                                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                                      onPressed: () => _showImageDialog(
                                        context,
                                        'إيصال إلكتروني - كود ${request.receiptCode}',
                                        request.receiptImageUrl!,
                                      ),
                                    ),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${request.fee.toInt()} ج.م (${request.remainingMonths} ش)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Documents viewer buttons (Icon-Only with tooltips)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.outlined(
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                tooltip: 'وجه البطاقة',
                                icon: const Icon(Icons.badge_outlined, size: 16),
                                onPressed: () => _showImageDialog(
                                  context,
                                  'بطاقة الرقم القومي (الوجه) - ${request.fullName}',
                                  request.nationalIdFrontUrl,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton.outlined(
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                tooltip: 'ظهر البطاقة',
                                icon: const Icon(Icons.flip_rounded, size: 16),
                                onPressed: () => _showImageDialog(
                                  context,
                                  'بطاقة الرقم القومي (الظهر) - ${request.fullName}',
                                  request.nationalIdBackUrl,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                    // Row 4: Action Buttons or Status Message
                    if (request.status == SubscriptionRequestStatus.pending) ...[
                      const SizedBox(height: 12),
                      if (currentAdmin.role == UserRole.superAdmin ||
                          currentAdmin.role == UserRole.technicalSupport)
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: request.requestType == 'delete_delegate'
                                      ? Colors.red.shade700
                                      : const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: onApprove,
                                icon: Icon(
                                  request.requestType == 'delete_delegate'
                                      ? Icons.delete_forever_rounded
                                      : Icons.verified_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  request.requestType == 'delete_delegate'
                                      ? 'اعتماد الحذف النهائي'
                                      : 'اعتماد وتفعيل',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  side: BorderSide(color: colorScheme.error.withValues(alpha: 0.7)),
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: onReject,
                                icon: const Icon(Icons.cancel_rounded, size: 17),
                                label: Text(
                                  request.requestType == 'delete_delegate'
                                      ? 'رفض طلب الحذف'
                                      : 'رفض الطلب',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_top_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'الطلب قيد الانتظار وبانتظار المراجعة والاعتماد.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else if (request.status == SubscriptionRequestStatus.approved) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: request.requestType == 'delete_delegate'
                              ? Colors.grey.shade100
                              : const Color(0xFF16A34A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: request.requestType == 'delete_delegate'
                                ? Colors.grey.shade300
                                : const Color(0xFF16A34A).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              request.requestType == 'delete_delegate'
                                  ? Icons.delete_outline_rounded
                                  : Icons.check_circle_rounded,
                              size: 16,
                              color: request.requestType == 'delete_delegate'
                                  ? Colors.grey.shade700
                                  : const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                request.requestType == 'delete_delegate'
                                    ? 'تم تنفيذ الحذف النهائي للمندوب بنجاح${request.reviewedBy != null ? " (${request.reviewedBy})" : ""}!'
                                    : 'تم اعتماد وتفعيل المندوب بنجاح${request.reviewedBy != null ? " (${request.reviewedBy})" : ""}!',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: request.requestType == 'delete_delegate'
                                      ? Colors.grey.shade800
                                      : const Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (request.status == SubscriptionRequestStatus.rejected) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.cancel_rounded, size: 16, color: colorScheme.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                request.requestType == 'delete_delegate'
                                    ? 'تم رفض طلب الحذف: ${request.rejectionReason ?? "بدون سبب"}${request.reviewedBy != null ? " (${request.reviewedBy})" : ""}'
                                    : 'تم رفض الطلب: ${request.rejectionReason ?? "بدون سبب"}${request.reviewedBy != null ? " (${request.reviewedBy})" : ""}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    SubscriptionRequestStatus status,
    ColorScheme colorScheme, {
    bool isDeleteRequest = false,
  }) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (isDeleteRequest) {
      switch (status) {
        case SubscriptionRequestStatus.pending:
          bg = Colors.red.withValues(alpha: 0.12);
          fg = Colors.red.shade700;
          label = 'معلق للحذف';
          icon = Icons.delete_sweep_rounded;
          break;
        case SubscriptionRequestStatus.approved:
          bg = Colors.grey.withValues(alpha: 0.14);
          fg = Colors.grey.shade700;
          label = 'تم الحذف';
          icon = Icons.check_circle_rounded;
          break;
        case SubscriptionRequestStatus.rejected:
          bg = colorScheme.error.withValues(alpha: 0.12);
          fg = colorScheme.error;
          label = 'مرفوض';
          icon = Icons.cancel_rounded;
          break;
      }
    } else {
      switch (status) {
        case SubscriptionRequestStatus.pending:
          bg = colorScheme.primary.withValues(alpha: 0.12);
          fg = colorScheme.primary;
          label = 'قيد الانتظار';
          icon = Icons.hourglass_top_rounded;
          break;
        case SubscriptionRequestStatus.approved:
          bg = const Color(0xFF16A34A).withValues(alpha: 0.14);
          fg = const Color(0xFF16A34A);
          label = 'معتمد';
          icon = Icons.verified_rounded;
          break;
        case SubscriptionRequestStatus.rejected:
          bg = colorScheme.error.withValues(alpha: 0.12);
          fg = colorScheme.error;
          label = 'مرفوض';
          icon = Icons.cancel_rounded;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fg.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }
}
