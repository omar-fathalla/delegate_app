import 'dart:async';
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
import 'anti_fraud_audit_screen.dart';
import 'delegate_subscription_requests_page.dart';
import 'super_admin_payment_receipts_report_screen.dart';
import 'super_admin_subscription_financial_report_screen.dart';
import 'super_admin_session_control_screen.dart';
import '../../../photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import '../../../photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_settings_page.dart';
import 'package:delegate_app/features/wallet/presentation/pages/super_admin_wallets_screen.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  final Delegate delegate;
  final VoidCallback? onNavigateToBranches;
  final VoidCallback? onNavigateToAddBranch;
  final VoidCallback? onNavigateToCreateAdmin;
  final VoidCallback? onNavigateToSendNotification;
  final VoidCallback? onNavigateToAntiFraud;

  const SuperAdminDashboardScreen({
    super.key,
    required this.delegate,
    this.onNavigateToBranches,
    this.onNavigateToAddBranch,
    this.onNavigateToCreateAdmin,
    this.onNavigateToSendNotification,
    this.onNavigateToAntiFraud,
  });

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  static Map<String, dynamic>? _cachedSupportStats;
  static DateTime? _cachedSupportStatsTime;

  static Map<String, dynamic>? _cachedAdminStats;
  static DateTime? _cachedAdminStatsTime;

  bool _isLoading = true;
  String? _errorMessage;

  // Electronic Payment Receipt Stats
  int _electronicWithImageCount = 0;
  int _electronicEmptyCount = 0;
  int _electronicApprovedCount = 0;
  int _deductedFromCompanyCount = 0;
  int _totalDelegatesCount = 0;

  StreamSubscription<QuerySnapshot>? _delegatesSubscription;
  StreamSubscription<QuerySnapshot>? _delegateRequestsSubscription;
  int _pendingDelegateRequestsCount = 0;

  // Technical Support Suggestions / Feedbacks Stats
  int _totalFeedbacksCount = 0;
  int _pendingFeedbacksCount = 0;
  int _inProgressFeedbacksCount = 0;
  int _resolvedFeedbacksCount = 0;
  List<FeedbackModel> _recentFeedbacks = [];

  @override
  void initState() {
    super.initState();
    _applyCachedDataIfAvailable();
    _loadStats();
    _startRealtimeDelegatesListener();
    _startRealtimeDelegateRequestsListener();
  }

  @override
  void dispose() {
    _delegatesSubscription?.cancel();
    _delegateRequestsSubscription?.cancel();
    super.dispose();
  }

  void _startRealtimeDelegateRequestsListener() {
    _delegateRequestsSubscription?.cancel();
    _delegateRequestsSubscription = FirebaseFirestore.instance
        .collection('delegate_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _pendingDelegateRequestsCount = snapshot.docs.length;
        });
      }
    }, onError: (e) {
      debugPrint('Error in delegate requests realtime stream: $e');
    });
  }

  void _startRealtimeDelegatesListener() {
    if (widget.delegate.role != UserRole.superAdmin) return;
    _delegatesSubscription?.cancel();

    Query delegatesQuery = FirebaseFirestore.instance.collectionGroup('delegates');
    if (widget.delegate.organizationUID.isNotEmpty) {
      delegatesQuery = delegatesQuery.where('organizationUID', isEqualTo: widget.delegate.organizationUID);
    }

    _delegatesSubscription = delegatesQuery.snapshots().listen((snapshot) {
      _processDelegatesSnapshot(snapshot.docs);
    }, onError: (e) {
      debugPrint('Error in delegates realtime stream: $e');
    });
  }

  void _processDelegatesSnapshot(List<QueryDocumentSnapshot> docs) {
    int withImage = 0;
    int emptyOrMissing = 0;
    int approved = 0;
    int deducted = 0;
    int total = 0;

    for (final doc in docs) {
      final pathParts = doc.reference.path.split('/');
      final orgUid = pathParts.length > 1 ? pathParts[1] : '';
      if (widget.delegate.organizationUID.isNotEmpty && orgUid != widget.delegate.organizationUID) {
        continue;
      }

      total++;
      final data = doc.data() as Map<String, dynamic>? ?? {};
      if (data['isDeductedFromCompany'] == true) {
        deducted++;
      }

      final documentsList = data['documents'] as List? ?? [];
      Map<String, dynamic>? electronicDoc;

      for (final docItem in documentsList) {
        if (docItem is Map<String, dynamic>) {
          final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
          if (key == 'electronicpaymentreceipt' ||
              key == 'electronic_payment_receipt' ||
              key == 'electronicreceipt' ||
              key == 'electronic_receipt') {
            electronicDoc = docItem;
            break;
          }
        }
      }

      if (electronicDoc != null) {
        final url = (electronicDoc['documentURL']?.toString() ??
                     electronicDoc['secondaryURL']?.toString() ?? '').trim();
        final status = electronicDoc['documentStatus']?.toString().toLowerCase() ?? '';

        if (url.isNotEmpty) {
          withImage++;
          if (status == 'approved') {
            approved++;
          }
        } else {
          emptyOrMissing++;
        }
      } else {
        emptyOrMissing++;
      }
    }

    _cachedAdminStats = {
      ...?_cachedAdminStats,
      'electronicWithImageCount': withImage,
      'electronicEmptyCount': emptyOrMissing,
      'electronicApprovedCount': approved,
      'deductedFromCompanyCount': deducted,
      'totalDelegatesCount': total,
      'delegatesCount': total,
    };
    _cachedAdminStatsTime = DateTime.now();

    if (mounted) {
      setState(() {
        _electronicWithImageCount = withImage;
        _electronicEmptyCount = emptyOrMissing;
        _electronicApprovedCount = approved;
        _deductedFromCompanyCount = deducted;
        _totalDelegatesCount = total;
        _isLoading = false;
      });
    }
  }

  void _applyCachedDataIfAvailable() {
    if (widget.delegate.role == UserRole.technicalSupport) {
      if (_cachedSupportStats != null) {
        _totalFeedbacksCount = _cachedSupportStats!['totalFeedbacksCount'] ?? 0;
        _pendingFeedbacksCount = _cachedSupportStats!['pendingFeedbacksCount'] ?? 0;
        _inProgressFeedbacksCount = _cachedSupportStats!['inProgressFeedbacksCount'] ?? 0;
        _resolvedFeedbacksCount = _cachedSupportStats!['resolvedFeedbacksCount'] ?? 0;
        _recentFeedbacks = List<FeedbackModel>.from(_cachedSupportStats!['recentFeedbacks'] ?? []);
        _isLoading = false;
      }
    } else {
      if (_cachedAdminStats != null) {
        _electronicWithImageCount = _cachedAdminStats!['electronicWithImageCount'] ?? 0;
        _electronicEmptyCount = _cachedAdminStats!['electronicEmptyCount'] ?? 0;
        _electronicApprovedCount = _cachedAdminStats!['electronicApprovedCount'] ?? 0;
        _deductedFromCompanyCount = _cachedAdminStats!['deductedFromCompanyCount'] ?? 0;
        _totalDelegatesCount = _cachedAdminStats!['totalDelegatesCount'] ?? 0;
        _totalFeedbacksCount = _cachedAdminStats!['totalFeedbacksCount'] ?? 0;
        _pendingFeedbacksCount = _cachedAdminStats!['pendingFeedbacksCount'] ?? 0;
        _inProgressFeedbacksCount = _cachedAdminStats!['inProgressFeedbacksCount'] ?? 0;
        _resolvedFeedbacksCount = _cachedAdminStats!['resolvedFeedbacksCount'] ?? 0;
        _recentFeedbacks = List<FeedbackModel>.from(_cachedAdminStats!['recentFeedbacks'] ?? []);
        _isLoading = false;
      }
    }
  }

  Future<void> _loadStats({bool isPullToRefresh = false}) async {
    final isSupport = widget.delegate.role == UserRole.technicalSupport;

    // If we already have fresh cached data and it's not a manual pull-to-refresh, don't show loading spinner
    final cacheTime = isSupport ? _cachedSupportStatsTime : _cachedAdminStatsTime;
    final hasCache = isSupport ? (_cachedSupportStats != null) : (_cachedAdminStats != null);
    final isCacheFresh = cacheTime != null && DateTime.now().difference(cacheTime).inMinutes < 5;

    if (hasCache && isCacheFresh && !isPullToRefresh) {
      return;
    }

    if (!hasCache && !isPullToRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;

      if (isSupport) {
        // Fast Technical Support path: Fetch ONLY feedback stats and top 4 recent items
        final totalCountQuery = await firestore.collection('feedbacks').count().get();
        final pendingCountQuery = await firestore
            .collection('feedbacks')
            .where('status', isEqualTo: 'pending')
            .count()
            .get();
        final inProgressCountQuery = await firestore
            .collection('feedbacks')
            .where('status', whereIn: ['inProgress', 'in_progress', 'reviewed'])
            .count()
            .get();
        final resolvedCountQuery = await firestore
            .collection('feedbacks')
            .where('status', isEqualTo: 'resolved')
            .count()
            .get();

        final recentSnap = await firestore
            .collection('feedbacks')
            .orderBy('createdAt', descending: true)
            .limit(4)
            .get();

        final recentFeedbacks = recentSnap.docs
            .map((doc) => FeedbackModel.fromJson(doc.data(), doc.id))
            .toList();

        final totalCount = totalCountQuery.count ?? 0;
        final pendingCount = pendingCountQuery.count ?? 0;
        final inProgressCount = inProgressCountQuery.count ?? 0;
        final resolvedCount = resolvedCountQuery.count ?? 0;

        _cachedSupportStats = {
          'totalFeedbacksCount': totalCount,
          'pendingFeedbacksCount': pendingCount,
          'inProgressFeedbacksCount': inProgressCount,
          'resolvedFeedbacksCount': resolvedCount,
          'recentFeedbacks': recentFeedbacks,
        };
        _cachedSupportStatsTime = DateTime.now();

        if (mounted) {
          setState(() {
            _totalFeedbacksCount = totalCount;
            _pendingFeedbacksCount = pendingCount;
            _inProgressFeedbacksCount = inProgressCount;
            _resolvedFeedbacksCount = resolvedCount;
            _recentFeedbacks = recentFeedbacks;
            _isLoading = false;
          });
        }
        return;
      }

      // Super Admin Path
      final orgUID = widget.delegate.organizationUID;

      // 1. Feedbacks statistics (fast count)
      int totalFeedbacksCount = 0;
      int pendingFeedbacksCount = 0;
      int inProgressFeedbacksCount = 0;
      int resolvedFeedbacksCount = 0;
      List<FeedbackModel> recentFeedbacks = [];

      try {
        final totalCountQuery = await firestore.collection('feedbacks').count().get();
        final pendingCountQuery = await firestore
            .collection('feedbacks')
            .where('status', isEqualTo: 'pending')
            .count()
            .get();
        final inProgressCountQuery = await firestore
            .collection('feedbacks')
            .where('status', whereIn: ['inProgress', 'in_progress', 'reviewed'])
            .count()
            .get();
        final resolvedCountQuery = await firestore
            .collection('feedbacks')
            .where('status', isEqualTo: 'resolved')
            .count()
            .get();

        final recentSnap = await firestore
            .collection('feedbacks')
            .orderBy('createdAt', descending: true)
            .limit(4)
            .get();

        totalFeedbacksCount = totalCountQuery.count ?? 0;
        pendingFeedbacksCount = pendingCountQuery.count ?? 0;
        inProgressFeedbacksCount = inProgressCountQuery.count ?? 0;
        resolvedFeedbacksCount = resolvedCountQuery.count ?? 0;
        recentFeedbacks = recentSnap.docs
            .map((doc) => FeedbackModel.fromJson(doc.data(), doc.id))
            .toList();
      } catch (_) {}

      // 2. If pull to refresh, refresh delegates explicitly
      if (isPullToRefresh) {
        Query delegatesBaseQuery = firestore.collectionGroup('delegates');
        if (orgUID.isNotEmpty) {
          delegatesBaseQuery = delegatesBaseQuery.where('organizationUID', isEqualTo: orgUID);
        }
        final snap = await delegatesBaseQuery.get();
        _processDelegatesSnapshot(snap.docs);
      }

      _cachedAdminStats = {
        ...?_cachedAdminStats,
        'totalFeedbacksCount': totalFeedbacksCount,
        'pendingFeedbacksCount': pendingFeedbacksCount,
        'inProgressFeedbacksCount': inProgressFeedbacksCount,
        'resolvedFeedbacksCount': resolvedFeedbacksCount,
        'recentFeedbacks': recentFeedbacks,
      };
      _cachedAdminStatsTime = DateTime.now();

      if (mounted) {
        setState(() {
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

    final screenWidth = MediaQuery.of(context).size.width;
    final statAspectRatio = screenWidth < 360 ? 1.0 : (screenWidth < 400 ? 1.15 : 1.25);
    final actionAspectRatio = screenWidth < 360 ? 1.9 : (screenWidth < 400 ? 2.1 : 2.35);

    return RefreshIndicator(
      onRefresh: () => _loadStats(isPullToRefresh: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome Header Card (M3 Tonal Container)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'أهلاً بك، ${widget.delegate.firstName}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (context) {
                        final photoUrl = widget.delegate.personalPhotoUrl ??
                            (widget.delegate.documents
                                .where((d) =>
                                    d.documentKey == DocumentKey.personalPhoto &&
                                    d.documentURL.isNotEmpty)
                                .firstOrNull
                                ?.documentURL) ??
                            FirebaseAuth.instance.currentUser?.photoURL;

                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: AppAvatar(
                            imageUrl: photoUrl,
                            fallbackText: widget.delegate.firstName,
                            radius: 22,
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            fallbackIcon: Icons.admin_panel_settings_rounded,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'إحصائيات إيصالات الدفع الإلكتروني والنظام لحظة بلحظة مع التحديث المباشر.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Statistics Header Title & Live Count Chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'إحصائيات إيصالات الدفع',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$_totalDelegatesCount مندوب',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats Grid Layout - Dedicated to electronicPaymentReceipt (Responsive & Single-Seed M3)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: statAspectRatio,
            children: [
              _buildStatCard(
                title: 'مرفوعة بالصورة',
                value: _electronicWithImageCount.toString(),
                subtitle: 'إيصال دفع إلكتروني مخزن',
                icon: Icons.photo_library_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildStatCard(
                title: 'ملفات فارغة / معلقة',
                value: _electronicEmptyCount.toString(),
                subtitle: 'بدون صورة أو لم يتم الرفع',
                icon: Icons.hourglass_empty_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildStatCard(
                title: 'إيصالات معتمدة',
                value: _electronicApprovedCount.toString(),
                subtitle: 'تمت مراجعتها واعتمادها',
                icon: Icons.verified_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildStatCard(
                title: 'خصم من الشركة',
                value: _deductedFromCompanyCount.toString(),
                subtitle: 'مندوب بنظام الخصم',
                icon: Icons.account_balance_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick Actions section
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'إجراءات سريعة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grid of Quick Action Buttons (Responsive & Single-Seed M3)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: actionAspectRatio,
            children: [
              _buildActionButton(
                label: 'طلبات اشتراك المناديب',
                icon: Icons.how_to_reg_rounded,
                badgeCount: _pendingDelegateRequestsCount,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DelegateSubscriptionRequestsPage(
                        currentAdmin: widget.delegate,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'تقرير الإيصالات',
                icon: Icons.receipt_long_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'التقرير المالي للاشتراكات',
                icon: Icons.payments_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminSubscriptionFinancialReportScreen(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'تقرير أذونات التصوير',
                icon: Icons.analytics_rounded,
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
                onTap: widget.onNavigateToAddBranch,
              ),
              _buildActionButton(
                label: 'إنشاء أدمن جديد',
                icon: Icons.admin_panel_settings_rounded,
                onTap: widget.onNavigateToCreateAdmin,
              ),
              _buildActionButton(
                label: 'إعدادات الغرامات',
                icon: Icons.gavel_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PenaltyRulesSettingsPage(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إدارة المحافظ والمستحقات',
                icon: Icons.account_balance_wallet_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminWalletsScreen(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  );
                },
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
      onRefresh: () => _loadStats(isPullToRefresh: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Welcome Header Card (M3 Tonal Container)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'أهلاً بك، ${widget.delegate.firstName}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (context) {
                        final photoUrl = widget.delegate.personalPhotoUrl ??
                            (widget.delegate.documents
                                .where((d) =>
                                    d.documentKey == DocumentKey.personalPhoto &&
                                    d.documentURL.isNotEmpty)
                                .firstOrNull
                                ?.documentURL) ??
                            FirebaseAuth.instance.currentUser?.photoURL;

                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: AppAvatar(
                            imageUrl: photoUrl,
                            fallbackText: widget.delegate.firstName,
                            radius: 24,
                            backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                            foregroundColor: colorScheme.primary,
                            fallbackIcon: Icons.support_agent_rounded,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'لوحة متابعة المقترحات والشكاوى وبلاغات مشاكل الفروع والمستخدمين.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Statistics Header Title
          Row(
            children: [
              Icon(Icons.mark_chat_unread_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'إحصائيات إدارة المقترحات والشكاوى',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats Grid Layout
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: MediaQuery.of(context).size.width < 360 ? 1.0 : (MediaQuery.of(context).size.width < 400 ? 1.15 : 1.25),
            children: [
              _buildStatCard(
                title: 'إجمالي المقترحات',
                value: _totalFeedbacksCount.toString(),
                subtitle: 'مقترح وشكوى مبعوثة',
                icon: Icons.feedback_rounded,
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'قيد المراجعة',
                value: _pendingFeedbacksCount.toString(),
                subtitle: 'في انتظار رد الدعم الفني',
                icon: Icons.pending_actions_rounded,
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'قيد المعالجة',
                value: _inProgressFeedbacksCount.toString(),
                subtitle: 'جاري العمل عليها',
                icon: Icons.work_history_rounded,
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildStatCard(
                title: 'تم الحل والمكالمة',
                value: _resolvedFeedbacksCount.toString(),
                subtitle: 'مقترح وشكوى مكتملة',
                icon: Icons.check_circle_rounded,
                onTap: () => _openAdminFeedbacks(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick Actions section
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'إجراءات سريعة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grid of Quick Action Buttons
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: MediaQuery.of(context).size.width < 360 ? 1.9 : (MediaQuery.of(context).size.width < 400 ? 2.1 : 2.35),
            children: [
              _buildActionButton(
                label: 'طلبات اشتراك المناديب',
                icon: Icons.how_to_reg_rounded,
                badgeCount: _pendingDelegateRequestsCount,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DelegateSubscriptionRequestsPage(
                        currentAdmin: widget.delegate,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إدارة جلسات المناديب',
                icon: Icons.sync_lock_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuperAdminSessionControlScreen(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إدارة المقترحات',
                icon: Icons.feedback_rounded,
                onTap: () => _openAdminFeedbacks(context),
              ),
              _buildActionButton(
                label: 'كشف التزييف والأجهزة',
                icon: Icons.security_rounded,
                onTap: widget.onNavigateToAntiFraud ?? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AntiFraudAuditScreen(
                        delegate: widget.delegate,
                        showAppBar: true,
                      ),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إرسال إشعار جديد',
                icon: Icons.send_time_extension_rounded,
                onTap: widget.onNavigateToSendNotification ?? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SendNotificationScreen(senderDelegate: widget.delegate),
                    ),
                  );
                },
              ),
              _buildActionButton(
                label: 'إنشاء أدمن جديد',
                icon: Icons.admin_panel_settings_rounded,
                onTap: widget.onNavigateToCreateAdmin,
              ),
              _buildActionButton(
                label: 'إدارة التسويق',
                icon: Icons.campaign_rounded,
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
                onTap: widget.onNavigateToAddBranch,
              ),
              _buildActionButton(
                label: 'إعدادات الغرامات',
                icon: Icons.gavel_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PenaltyRulesSettingsPage(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  );
                },
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
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'لا توجد مقترحات أو شكاوى مسجلة حتى الآن',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            ..._recentFeedbacks.map((f) {
              final statusColor = _getFeedbackStatusColor(colorScheme, f.status);
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
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                f.status.labelAr,
                                style: TextStyle(
                                  color: statusColor,
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

  Color _getFeedbackStatusColor(ColorScheme colorScheme, FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.pending:
        return colorScheme.tertiary;
      case FeedbackStatus.reviewed:
        return colorScheme.primary;
      case FeedbackStatus.inProgress:
        return colorScheme.secondary;
      case FeedbackStatus.resolved:
        return colorScheme.primary;
      case FeedbackStatus.rejected:
        return colorScheme.error;
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
    Color? tonalColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconBgColor = tonalColor?.withValues(alpha: 0.12) ?? colorScheme.primaryContainer.withValues(alpha: 0.6);
    final iconColor = tonalColor ?? colorScheme.primary;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: colorScheme.outline.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    int? badgeCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Badge(
                isLabelVisible: (badgeCount != null && badgeCount > 0),
                label: Text('$badgeCount'),
                backgroundColor: colorScheme.error,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
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
