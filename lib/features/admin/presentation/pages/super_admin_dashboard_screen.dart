import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/pages/admin_feedbacks_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_marketing_screen.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';
import 'super_admin_payment_receipts_report_screen.dart';
import '../../../photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import '../../../photo_permission/presentation/bloc/photo_permission_bloc.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  final Delegate delegate;
  final VoidCallback? onNavigateToBranches;
  final VoidCallback? onNavigateToAddBranch;
  final VoidCallback? onNavigateToCreateAdmin;

  const SuperAdminDashboardScreen({
    super.key,
    required this.delegate,
    this.onNavigateToBranches,
    this.onNavigateToAddBranch,
    this.onNavigateToCreateAdmin,
  });

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  int _branchesCount = 0;
  int _companiesCount = 0;
  int _delegatesCount = 0;
  int _receiptsCount = 0;

  // Technical Support Suggestions / Feedbacks Stats
  int _totalFeedbacksCount = 0;
  int _pendingFeedbacksCount = 0;
  int _inProgressFeedbacksCount = 0;
  int _resolvedFeedbacksCount = 0;
  List<FeedbackModel> _recentFeedbacks = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final orgUID = widget.delegate.organizationUID;

      int branchesCount = 0;
      int companiesCount = 0;

      // 1. Fetch branches count (branches are always stored at the root collection '/branches')
      final branchesQuery = await firestore.collection('branches').count().get();
      branchesCount = branchesQuery.count ?? 0;

      // 2. Fetch companies count
      if (orgUID.isEmpty) {
        // Query global counts for global super admin
        final companiesQuery = await firestore.collectionGroup('companies').count().get();
        companiesCount = companiesQuery.count ?? 0;
      } else {
        // Query organization-specific counts
        final companiesQuery = await firestore
            .collection('organizations')
            .doc(orgUID)
            .collection('companies')
            .count()
            .get();
        companiesCount = companiesQuery.count ?? 0;
      }

      // 3. Fetch delegates and electronic receipts count using collectionGroup
      final delegatesSnapshot = await firestore.collectionGroup('delegates').get();
      final filteredDelegates = delegatesSnapshot.docs.where((doc) {
        final pathParts = doc.reference.path.split('/');
        final docOrgUid = pathParts.length > 1 ? pathParts[1] : '';
        if (orgUID.isNotEmpty && docOrgUid != orgUID) {
          return false;
        }
        return true;
      }).toList();

      final delegatesCount = filteredDelegates.length;
      int receiptsCount = 0;

      for (var doc in filteredDelegates) {
        final data = doc.data();
        final documentsList = data['documents'] as List? ?? [];

        for (var docItem in documentsList) {
          if (docItem is Map<String, dynamic>) {
            final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
            final url = docItem['documentURL']?.toString() ?? '';

            if ((key == 'electronicpaymentreceipt' ||
                 key == 'electronic_payment_receipt' ||
                 key == 'electronic_receipt' ||
                 key == 'electronicreceipt') &&
                url.isNotEmpty) {
              receiptsCount++;
            }
          }
        }
      }

      // 4. Fetch feedbacks statistics for technical support and admin dashboard
      int totalFeedbacksCount = 0;
      int pendingFeedbacksCount = 0;
      int inProgressFeedbacksCount = 0;
      int resolvedFeedbacksCount = 0;
      List<FeedbackModel> recentFeedbacks = [];

      try {
        final feedbacksSnapshot = await firestore.collection('feedbacks').get();
        final feedbacks = feedbacksSnapshot.docs
            .map((doc) => FeedbackModel.fromJson(doc.data(), doc.id))
            .toList();

        feedbacks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        totalFeedbacksCount = feedbacks.length;
        pendingFeedbacksCount = feedbacks
            .where((f) => f.status == FeedbackStatus.pending)
            .length;
        inProgressFeedbacksCount = feedbacks
            .where((f) =>
                f.status == FeedbackStatus.inProgress ||
                f.status == FeedbackStatus.reviewed)
            .length;
        resolvedFeedbacksCount = feedbacks
            .where((f) => f.status == FeedbackStatus.resolved)
            .length;
        recentFeedbacks = feedbacks.take(4).toList();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _branchesCount = branchesCount;
          _companiesCount = companiesCount;
          _delegatesCount = delegatesCount;
          _receiptsCount = receiptsCount;
          _totalFeedbacksCount = totalFeedbacksCount;
          _pendingFeedbacksCount = pendingFeedbacksCount;
          _inProgressFeedbacksCount = inProgressFeedbacksCount;
          _resolvedFeedbacksCount = resolvedFeedbacksCount;
          _recentFeedbacks = recentFeedbacks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'فشل تحميل الإحصائيات: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openAdminFeedbacks(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<AdminFeedbackBloc>(),
          child: const AdminFeedbacksScreen(),
        ),
      ),
    ).then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.delegate.role == UserRole.technicalSupport) {
      return _buildTechnicalSupportDashboard(context, theme, colorScheme);
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Welcome Header Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'أهلاً بك، ${widget.delegate.firstName}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'إليك إحصائيات النظام العامة اليوم ونظرة سريعة على فروع ومستندات المنظمة.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Statistics Header Title
          Row(
            children: [
              Icon(Icons.query_stats_rounded, color: colorScheme.primary, size: 26),
              const SizedBox(width: 8),
              Text(
                'إحصائيات النظام المتاحة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats Grid Layout
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _buildStatCard(
                title: 'عدد الفروع',
                value: _branchesCount.toString(),
                subtitle: 'فرع مفعل ومسجل',
                icon: Icons.storefront_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
                ),
              ),
              _buildStatCard(
                title: 'إيصالات الدفع',
                value: _receiptsCount.toString(),
                subtitle: 'إيصال دفع إلكتروني',
                icon: Icons.receipt_long_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                ),
              ),
              _buildStatCard(
                title: 'الشركات المسجلة',
                value: _companiesCount.toString(),
                subtitle: 'شركة نشطة بالمنظمة',
                icon: Icons.business_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF009688), Color(0xFF4DB6AC)],
                ),
              ),
              _buildStatCard(
                title: 'إجمالي المناديب',
                value: _delegatesCount.toString(),
                subtitle: 'مندوب مسجل بالنظام',
                icon: Icons.people_alt_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Quick Actions section
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colorScheme.secondary, size: 26),
              const SizedBox(width: 8),
              Text(
                'إجراءات سريعة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid of Quick Action Buttons
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              _buildActionButton(
                label: 'تقرير الإيصالات',
                icon: Icons.receipt_long_rounded,
                color: Colors.orange.shade800,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'تقرير أذونات التصوير',
                icon: Icons.analytics_outlined,
                color: Colors.blue.shade800,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (_) => di.sl<PhotoPermissionBloc>(),
                        child: SuperAdminPermissionsReportScreen(delegate: widget.delegate),
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إضافة فرع',
                icon: Icons.add_location_alt_rounded,
                color: Colors.teal.shade800,
                onTap: widget.onNavigateToAddBranch,
              ),
              _buildActionButton(
                label: 'إنشاء أدمن جديد',
                icon: Icons.admin_panel_settings_rounded,
                color: Colors.purple.shade800,
                onTap: widget.onNavigateToCreateAdmin,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalSupportDashboard(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Welcome Header Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'أهلاً بك، ${widget.delegate.firstName}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.support_agent_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'لوحة متابعة المقترحات والشكاوى وبلاغات مشاكل الفروع والمستخدمين.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Statistics Header Title
          Row(
            children: [
              Icon(Icons.mark_chat_unread_rounded, color: colorScheme.primary, size: 26),
              const SizedBox(width: 8),
              Text(
                'إحصائيات إدارة المقترحات والشكاوى',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats Grid Layout
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _buildStatCard(
                title: 'إجمالي المقترحات',
                value: _totalFeedbacksCount.toString(),
                subtitle: 'مقترح وشكوى مبعوثة',
                icon: Icons.feedback_outlined,
                gradient: const LinearGradient(
                  colors: [Color(0xFF673AB7), Color(0xFF9575CD)],
                ),
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'قيد المراجعة',
                value: _pendingFeedbacksCount.toString(),
                subtitle: 'في انتظار رد الدعم الفني',
                icon: Icons.pending_actions_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                ),
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'قيد المعالجة',
                value: _inProgressFeedbacksCount.toString(),
                subtitle: 'جاري العمل عليها',
                icon: Icons.work_history_outlined,
                gradient: const LinearGradient(
                  colors: [Color(0xFF0288D1), Color(0xFF4FC3F7)],
                ),
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'تم الحل والمكالمة',
                value: _resolvedFeedbacksCount.toString(),
                subtitle: 'مقترح وشكوى مكتملة',
                icon: Icons.check_circle_outline_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                ),
                onTap: () => _openAdminFeedbacks(context),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Quick Actions section
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colorScheme.secondary, size: 26),
              const SizedBox(width: 8),
              Text(
                'إجراءات سريعة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid of Quick Action Buttons
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              _buildActionButton(
                label: 'إدارة المقترحات',
                icon: Icons.feedback_rounded,
                color: Colors.deepPurple.shade700,
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildActionButton(
                label: 'إرسال إشعار جديد',
                icon: Icons.send_time_extension_rounded,
                color: Colors.indigo.shade800,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SendNotificationScreen(senderDelegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إدارة التسويق',
                icon: Icons.campaign_rounded,
                color: Colors.orange.shade800,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManageMarketingScreen(),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إضافة فرع',
                icon: Icons.add_location_alt_rounded,
                color: Colors.teal.shade800,
                onTap: widget.onNavigateToAddBranch,
              ),
              _buildActionButton(
                label: 'إنشاء أدمن جديد',
                icon: Icons.admin_panel_settings_rounded,
                color: Colors.purple.shade800,
                onTap: widget.onNavigateToCreateAdmin,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Recent Feedbacks section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.history_rounded, color: colorScheme.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'أحدث المقترحات والشكاوى الواردة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _openAdminFeedbacks(context),
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_recentFeedbacks.isEmpty)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'لا توجد مقترحات أو شكاوى مسجلة حتى الآن',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            ..._recentFeedbacks.map((f) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: InkWell(
                  onTap: () => _openAdminFeedbacks(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                f.type.labelAr,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getFeedbackStatusColor(f.status).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getFeedbackStatusColor(f.status).withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                f.status.labelAr,
                                style: TextStyle(
                                  color: _getFeedbackStatusColor(f.status),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          f.userName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          f.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dateFormat.format(f.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Color _getFeedbackStatusColor(FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.pending:
        return Colors.orange.shade800;
      case FeedbackStatus.reviewed:
        return Colors.blue.shade700;
      case FeedbackStatus.inProgress:
        return Colors.purple.shade700;
      case FeedbackStatus.resolved:
        return Colors.green.shade700;
      case FeedbackStatus.rejected:
        return Colors.red.shade700;
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(icon, color: Colors.white, size: 24),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
