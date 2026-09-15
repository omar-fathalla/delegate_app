import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';

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
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final repo = sl<DelegateSubscriptionRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.currentAdmin.role == UserRole.admin
              ? 'متابعة اعتمادات وطلبات المناديب'
              : 'طلبات تسجيل واشتراك المناديب',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'البحث باسم المندوب، الشركة، أو الهاتف...',
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
          ),

          // 2. Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildFilterChip('قيد الانتظار (لم يتم الاعتماد)', SubscriptionRequestStatus.pending, colorScheme),
                const SizedBox(width: 8),
                _buildFilterChip('تم الاعتماد', SubscriptionRequestStatus.approved, colorScheme),
                const SizedBox(width: 8),
                _buildFilterChip('المرفوضة', SubscriptionRequestStatus.rejected, colorScheme),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('الكل', style: TextStyle(fontSize: 12.5)),
                  selected: _statusFilter == null,
                  onSelected: (selected) {
                    if (selected) setState(() => _statusFilter = null);
                  },
                ),
              ],
            ),
          ),

          // 3. Requests Stream List
          Expanded(
            child: StreamBuilder<List<DelegateSubscriptionRequest>>(
              stream: repo.getSubscriptionRequestsStream(
                statusFilter: _statusFilter,
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
                    child: Text(
                      'حدث خطأ أثناء تحميل الطلبات: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                var requests = snapshot.data ?? [];

                if (_searchQuery.isNotEmpty) {
                  requests = requests.where((r) {
                    return r.fullName.toLowerCase().contains(_searchQuery) ||
                        r.companyName.toLowerCase().contains(_searchQuery) ||
                        r.organizationName.toLowerCase().contains(_searchQuery) ||
                        r.phoneNumber.contains(_searchQuery) ||
                        (r.receiptCode ?? '').contains(_searchQuery);
                  }).toList();
                }

                if (requests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_rounded,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusFilter == SubscriptionRequestStatus.pending
                              ? 'لا توجد طلبات اشتراك معلقة حالياً'
                              : 'لا توجد طلبات مطابقة للبحث',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return _SubscriptionRequestCard(
                      request: request,
                      currentAdmin: widget.currentAdmin,
                      onApprove: () => _handleApprove(request),
                      onReject: () => _handleReject(request),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    SubscriptionRequestStatus status,
    ColorScheme colorScheme,
  ) {
    final isSelected = _statusFilter == status;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _statusFilter = status);
      },
    );
  }

  Future<void> _handleApprove(DelegateSubscriptionRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text('تأكيد الاعتماد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من اعتماد المندوب "${request.fullName}" وتفعيل اشتراكه بقيمة ${request.fee.toInt()} ج.م (${request.remainingMonths} أشهر) حتى نهاية دورة ${request.subscriptionCycle}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اعتماد وتفعيل'),
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

    result.fold(
      (failure) => AppSnackBar.showError(context, failure.message),
      (_) => AppSnackBar.showSuccess(
        context,
        'تم اعتماد المندوب ${request.fullName} بنجاح وتفعيل حسابه!',
      ),
    );
  }

  Future<void> _handleReject(DelegateSubscriptionRequest request) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('رفض طلب المندوب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يرجى توضيح سبب رفض طلب المندوب "${request.fullName}":'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب سبب الرفض هنا (مثلاً: صورة البطاقة غير واضحة)...',
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
      (_) => AppSnackBar.showSuccess(context, 'تم رفض الطلب وإشعار المشرف بالسبب.'),
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 15)),
              centerTitle: true,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const SizedBox(
                      height: 120,
                      child: Center(child: Icon(Icons.broken_image, size: 48)),
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

    return Card(
      elevation: 0.8,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: request.status == SubscriptionRequestStatus.pending
              ? Colors.amber.shade300
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Badges (Org + Company + Status)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.corporate_fare_rounded, size: 12, color: colorScheme.primary),
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
                _buildStatusBadge(request.status),
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
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 52,
                        height: 52,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 52,
                        height: 52,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.phone_rounded, size: 12, color: colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            request.phoneNumber,
                            style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.credit_card_rounded, size: 12, color: colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            request.nationalId,
                            style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'المشرف: ${request.supervisorName} • $dateStr',
                        style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 18),

            // Row 3: Payment & Cycle info
            Row(
              children: [
                // Payment Method
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'طريقة الدفع:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (request.paymentMethod == SubscriptionPaymentMethod.companyDeduction)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'خصم من حساب الشركة',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            )
                          else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.shade400),
                              ),
                              child: Text(
                                'كود: ${request.receiptCode ?? "بدون"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                            if (request.receiptImageUrl != null)
                              InkWell(
                                onTap: () => _showImageDialog(
                                  context,
                                  'إيصال الدفع - كود ${request.receiptCode}',
                                  request.receiptImageUrl!,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.receipt_long_rounded, size: 12),
                                      SizedBox(width: 3),
                                      Text('عرض الإيصال', style: TextStyle(fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Text(
                              '${request.fee.toInt()} ج.م (${request.remainingMonths} أشهر)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Documents viewer buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showImageDialog(
                        context,
                        'بطاقة الرقم القومي (الوجه) - ${request.fullName}',
                        request.nationalIdFrontUrl,
                      ),
                      icon: const Icon(Icons.credit_card_rounded, size: 14),
                      label: const Text('وجه البطاقة', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showImageDialog(
                        context,
                        'بطاقة الرقم القومي (الظهر) - ${request.fullName}',
                        request.nationalIdBackUrl,
                      ),
                      icon: const Icon(Icons.flip_rounded, size: 14),
                      label: const Text('ظهر البطاقة', style: TextStyle(fontSize: 11)),
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
                          backgroundColor: const Color(0xFF6B4B00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: onApprove,
                        icon: const Icon(Icons.verified_rounded, size: 17),
                        label: const Text(
                          'اعتماد',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.onErrorContainer,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: onReject,
                        icon: const Icon(Icons.cancel_rounded, size: 17),
                        label: const Text(
                          'رفض',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, size: 18, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الطلب قيد الانتظار وبانتظار المراجعة والاعتماد من قبل الإدارة والدعم الفني.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (request.status == SubscriptionRequestStatus.approved) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم اعتماد وتفعيل المندوب بنجاح${request.reviewedBy != null ? " بواسطة ${request.reviewedBy}" : ""}!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cancel_rounded, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم رفض الطلب: ${request.rejectionReason ?? "لا يوجد سبب محدد"}${request.reviewedBy != null ? " (بواسطة ${request.reviewedBy})" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
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
    );
  }

  Widget _buildStatusBadge(SubscriptionRequestStatus status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case SubscriptionRequestStatus.pending:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        label = 'قيد الانتظار';
        icon = Icons.hourglass_empty_rounded;
        break;
      case SubscriptionRequestStatus.approved:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = 'معتمد';
        icon = Icons.check_circle_rounded;
        break;
      case SubscriptionRequestStatus.rejected:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        label = 'مرفوض';
        icon = Icons.cancel_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }
}
