import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// شاشة إدارة واعتماد طلبات فك وربط أجهزة المناديب لمسؤولي الموارد البشرية (HR)
class HRDeviceUnbindRequestsScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRDeviceUnbindRequestsScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
  });

  @override
  State<HRDeviceUnbindRequestsScreen> createState() =>
      _HRDeviceUnbindRequestsScreenState();
}

class _HRDeviceUnbindRequestsScreenState
    extends State<HRDeviceUnbindRequestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'pending'; // 'pending', 'approved', 'rejected', 'all'
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

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('device_unbind_requests')
        .where('companyUID', isEqualTo: widget.hrDelegate.companyUID);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'طلبات فك وربط الأجهزة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.hrDelegate.companyName,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'حدث خطأ في تحميل الطلبات: ${snapshot.error}',
                style: TextStyle(color: colorScheme.error),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final allRequests = docs.map((d) {
            final data = d.data();
            return {
              'docId': d.id,
              ...data,
            };
          }).toList();

          // Sort descending by creation date
          allRequests.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          final pendingCount =
              allRequests.where((r) => r['status'] == 'pending').length;
          final approvedCount =
              allRequests.where((r) => r['status'] == 'approved').length;
          final rejectedCount =
              allRequests.where((r) => r['status'] == 'rejected').length;

          // Filter by status and search
          final filteredRequests = allRequests.where((req) {
            final status = (req['status'] ?? 'pending').toString();
            if (_selectedStatusFilter != 'all' &&
                status != _selectedStatusFilter) {
              return false;
            }

            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final name = (req['delegateName'] ?? '').toString().toLowerCase();
              final phone =
                  (req['delegatePhone'] ?? '').toString().toLowerCase();
              final bDev =
                  (req['boundDeviceModel'] ?? '').toString().toLowerCase();
              final rDev =
                  (req['requestedDeviceModel'] ?? '').toString().toLowerCase();
              if (!name.contains(q) &&
                  !phone.contains(q) &&
                  !bDev.contains(q) &&
                  !rDev.contains(q)) {
                return false;
              }
            }

            return true;
          }).toList();

          return Column(
            children: [
              // ── 1. Status Filter Cards (2x2 Grid on Mobile, 4 columns on Desktop) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 768;

                    final pendingCard = _buildFilterCard(
                      statusKey: 'pending',
                      title: 'قيد المراجعة',
                      value: '$pendingCount',
                      subtitle: pendingCount > 0
                          ? 'تحتاج إجراء من الإدارة'
                          : 'لا توجد طلبات معلقة',
                      icon: Icons.hourglass_top_rounded,
                      color: pendingCount > 0
                          ? const Color(0xFFD97706)
                          : colorScheme.outline,
                      colorScheme: colorScheme,
                      theme: theme,
                    );

                    final approvedCard = _buildFilterCard(
                      statusKey: 'approved',
                      title: 'المعتمدة',
                      value: '$approvedCount',
                      subtitle: 'تمت الموافقة وفك الربط',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF2E7D32),
                      colorScheme: colorScheme,
                      theme: theme,
                    );

                    final rejectedCard = _buildFilterCard(
                      statusKey: 'rejected',
                      title: 'المرفوضة',
                      value: '$rejectedCount',
                      subtitle: 'تم رفض طلب الفك',
                      icon: Icons.cancel_outlined,
                      color: rejectedCount > 0
                          ? const Color(0xFFC62828)
                          : colorScheme.outline,
                      colorScheme: colorScheme,
                      theme: theme,
                    );

                    final allCard = _buildFilterCard(
                      statusKey: 'all',
                      title: 'الكل',
                      value: '${allRequests.length}',
                      subtitle: 'إجمالي الطلبات المسجلة',
                      icon: Icons.devices_rounded,
                      color: colorScheme.primary,
                      colorScheme: colorScheme,
                      theme: theme,
                    );

                    if (isWide) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: pendingCard),
                            const SizedBox(width: 8),
                            Expanded(child: approvedCard),
                            const SizedBox(width: 8),
                            Expanded(child: rejectedCard),
                            const SizedBox(width: 8),
                            Expanded(child: allCard),
                          ],
                        ),
                      );
                    }

                    // Mobile: 2x2 Grid (No horizontal scrolling)
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: pendingCard),
                            const SizedBox(width: 8),
                            Expanded(child: approvedCard),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: rejectedCard),
                            const SizedBox(width: 8),
                            Expanded(child: allCard),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── 2. Unified Search Toolbar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم المندوب أو الهاتف أو نوع الجهاز...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: colorScheme.primary,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHigh,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            BorderSide(color: colorScheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1),

              // ── Requests List ──
              Expanded(
                child: filteredRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.phonelink_lock_rounded,
                              size: 56,
                              color: colorScheme.outline.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'لا توجد نتائج مطابقة لبحثك'
                                  : 'لا توجد طلبات في هذا التبويب',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: filteredRequests.length,
                        itemBuilder: (context, index) {
                          final req = filteredRequests[index];
                          return _buildRequestCard(
                            context,
                            req,
                            theme,
                            colorScheme,
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

  Widget _buildRequestCard(
    BuildContext context,
    Map<String, dynamic> req,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final status = (req['status'] ?? 'pending').toString();
    final name = (req['delegateName'] ?? 'مندوب').toString();
    final phone = (req['delegatePhone'] ?? '').toString();
    final boundDevice = (req['boundDeviceModel'] ?? 'غير محدد').toString();
    final reqDevice = (req['requestedDeviceModel'] ?? 'غير محدد').toString();
    final reason = (req['reason'] ?? '').toString();
    final rejectReason = (req['rejectReason'] ?? '').toString();

    DateTime? reqDate;
    if (req['createdAt'] is Timestamp) {
      reqDate = (req['createdAt'] as Timestamp).toDate();
    } else if (req['createdAt'] != null) {
      reqDate = DateTime.tryParse(req['createdAt'].toString());
    }
    final reqDateStr = reqDate != null
        ? DateFormat('yyyy-MM-dd hh:mm a', 'ar').format(reqDate)
        : '';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (status == 'approved') {
      statusColor = const Color(0xFF2E7D32);
      statusLabel = 'معتمد';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      statusColor = colorScheme.error;
      statusLabel = 'مرفوض';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = const Color(0xFFE65100);
      statusLabel = 'قيد المراجعة';
      statusIcon = Icons.hourglass_top_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: status == 'pending'
              ? statusColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: status == 'pending' ? 1.5 : 1.0,
        ),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Avatar, Name, Phone & Status
            Row(
              children: [
                AppAvatar(
                  fallbackText: name,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
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

            // Devices Comparison Container
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الجهاز الحالي المقترن: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          boundDevice,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_android_rounded,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الجهاز الجديد المطلوب: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          reqDevice,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'سبب الطلب: $reason',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],

            if (rejectReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'سبب الرفض: $rejectReason',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            if (reqDateStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  'تاريخ الطلب: $reqDateStr',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ],

            // Action Buttons for Pending Requests
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        side: BorderSide(
                          color: colorScheme.error.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _rejectRequest(req),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'رفض الطلب',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _approveRequest(req),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'اعتماد وفك الارتباط',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approveRequest(Map<String, dynamic> requestData) async {
    final requestId = requestData['docId']?.toString() ?? '';
    final delegateUid = requestData['delegateUid']?.toString() ?? '';
    final delegateName =
        requestData['delegateName']?.toString() ?? 'المندوب';
    final orgId = requestData['organizationUID']?.toString() ??
        widget.hrDelegate.organizationUID;
    final compId = requestData['companyUID']?.toString() ??
        widget.hrDelegate.companyUID;

    final isMobile = MediaQuery.of(context).size.width <= 768;

    Widget buildContent(BuildContext ctx) {
      final theme = Theme.of(ctx);
      final colorScheme = theme.colorScheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF2E7D32),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تأكيد فك الارتباط',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'هل تريد الموافقة على طلب فك ارتباط جهاز "$delegateName"؟\n\n'
            'سيتم إلغاء قفل الجهاز القديم فوراً، وإشعار المندوب ليتمكن من الدخول من جهازه الجديد واعتماده تلقائياً.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          // Connected Action Button Group
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Center(
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                Expanded(
                  flex: 2,
                  child: Material(
                    color: const Color(0xFF2E7D32),
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, true),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'اعتماد وفك الارتباط',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final bool? confirm;
    if (isMobile) {
      confirm = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: buildContent(ctx),
        ),
      );
    } else {
      confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: buildContent(ctx),
            ),
          ),
        ),
      );
    }

    if (confirm != true || !mounted) return;

    try {
      await DeviceBindingService.approveUnbindRequest(
        requestId: requestId,
        delegateUid: delegateUid,
        organizationUID: orgId,
        companyUID: compId,
        adminUid: widget.hrDelegate.uid,
        adminName: widget.hrDelegate.fullName.isNotEmpty
            ? widget.hrDelegate.fullName
            : widget.hrDelegate.firstName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت الموافقة وفك ارتباط جهاز "$delegateName" بنجاح'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء فك الارتباط: $e')),
        );
      }
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> requestData) async {
    final requestId = requestData['docId']?.toString() ?? '';
    final delegateUid = requestData['delegateUid']?.toString() ?? '';
    final delegateName =
        requestData['delegateName']?.toString() ?? 'المندوب';

    final reasonController = TextEditingController();
    final isMobile = MediaQuery.of(context).size.width <= 768;

    Widget buildContent(BuildContext ctx) {
      final theme = Theme.of(ctx);
      final colorScheme = theme.colorScheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cancel_outlined,
                  color: colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'رفض طلب فك الارتباط',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'هل أنت متأكد من رفض طلب المندوب "$delegateName"؟',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            decoration: InputDecoration(
              labelText: 'سبب الرفض (اختياري)',
              hintText: 'مثال: يرجى مراجعة إدارة الفرع أولاً...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          // Connected Action Button Group
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Center(
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                Expanded(
                  child: Material(
                    color: colorScheme.error,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, true),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'تأكيد الرفض',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final bool? confirm;
    if (isMobile) {
      confirm = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: buildContent(ctx),
        ),
      );
    } else {
      confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: buildContent(ctx),
            ),
          ),
        ),
      );
    }

    if (confirm != true || !mounted) return;

    try {
      await DeviceBindingService.rejectUnbindRequest(
        requestId: requestId,
        delegateUid: delegateUid,
        adminUid: widget.hrDelegate.uid,
        adminName: widget.hrDelegate.fullName.isNotEmpty
            ? widget.hrDelegate.fullName
            : widget.hrDelegate.firstName,
        reason: reasonController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض طلب فك ارتباط جهاز "$delegateName"'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء رفض الطلب: $e')),
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  Widget _buildFilterCard({
    required String statusKey,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final isSelected = _selectedStatusFilter == statusKey;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStatusFilter = statusKey;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? color : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSelected ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : icon,
                    size: 15,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected
                    ? color.withValues(alpha: 0.85)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
