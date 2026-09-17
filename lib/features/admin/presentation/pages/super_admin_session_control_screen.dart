import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// شاشة السوبر أدمن المخصصة لإدارة جلسات المناديب والخروج الإجباري (فردي وجماعي)
/// متوافقة بالكامل مع معايير Material Design 3 وقاعدة الـ 20 (Infinite Scroll Pagination)
class SuperAdminSessionControlScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const SuperAdminSessionControlScreen({
    super.key,
    required this.adminDelegate,
  });

  @override
  State<SuperAdminSessionControlScreen> createState() =>
      _SuperAdminSessionControlScreenState();
}

class _SuperAdminSessionControlScreenState
    extends State<SuperAdminSessionControlScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Pagination & Individual Search State (قاعدة الـ 20) ───
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'active'; // افتراضياً جلسات نشطة حسب طلب المستخدم
  bool _isLoadingDelegates = false;
  bool _isLoadingMore = false;
  bool _hasReachedMax = false;
  DocumentSnapshot? _lastDocument;
  List<Map<String, dynamic>> _delegatesList = [];

  // ─── Bulk Companies State ───
  bool _isLoadingCompanies = false;
  List<Map<String, dynamic>> _companiesList = [];
  String? _selectedCompanyUID;
  Map<String, dynamic>? _selectedCompanyData;
  int? _selectedCompanyRealDelegateCount;
  bool _isLoadingCompanyCount = false;
  bool _isProcessingBulk = false;

  // ─── Global Reset State ───
  bool _isProcessingGlobal = false;
  Timestamp? _lastGlobalResetAt;

  String get _orgId => widget.adminDelegate.organizationUID.isNotEmpty
      ? widget.adminDelegate.organizationUID
      : SessionManagementService.defaultOrgId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController.addListener(_onScroll);
    _loadInitialDelegates();
    _loadCompanies();
    _loadGlobalSessionConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= (maxScroll * 0.85)) {
      _loadMoreDelegates();
    }
  }

  // ─── Load Delegates (قاعدة الـ 20 الأولى) ───
  Future<void> _loadInitialDelegates() async {
    setState(() {
      _isLoadingDelegates = true;
      _hasReachedMax = false;
      _lastDocument = null;
      _delegatesList.clear();
    });

    try {
      Query query = _firestore.collectionGroup('delegates').limit(_pageSize);
      if (widget.adminDelegate.organizationUID.isNotEmpty) {
        query = query.where('organizationUID',
            isEqualTo: widget.adminDelegate.organizationUID);
      }

      final snap = await query.get();
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['docId'] = doc.id;
        data['docRef'] = doc.reference;
        list.add(data);
      }

      if (mounted) {
        setState(() {
          _delegatesList = list;
          _lastDocument = snap.docs.isNotEmpty ? snap.docs.last : null;
          _hasReachedMax = snap.docs.length < _pageSize;
          _isLoadingDelegates = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDelegates = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب المناديب: $e')),
        );
      }
    }
  }

  // ─── Load More Delegates (الصفحات التالية بقاعدة الـ 20) ───
  Future<void> _loadMoreDelegates() async {
    if (_isLoadingMore ||
        _hasReachedMax ||
        _isLoadingDelegates ||
        _lastDocument == null) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      Query query = _firestore
          .collectionGroup('delegates')
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize);

      if (widget.adminDelegate.organizationUID.isNotEmpty) {
        query = query.where('organizationUID',
            isEqualTo: widget.adminDelegate.organizationUID);
      }

      final snap = await query.get();
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['docId'] = doc.id;
        data['docRef'] = doc.reference;
        list.add(data);
      }

      if (mounted) {
        setState(() {
          _delegatesList.addAll(list);
          _lastDocument =
              snap.docs.isNotEmpty ? snap.docs.last : _lastDocument;
          _hasReachedMax = snap.docs.length < _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // ─── Load Companies ───
  Future<void> _loadCompanies() async {
    setState(() => _isLoadingCompanies = true);
    try {
      final snap = await _firestore
          .collection('organizations')
          .doc(_orgId)
          .collection('companies')
          .get();

      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        list.add(data);
      }

      list.sort((a, b) => (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString()));

      if (mounted) {
        setState(() {
          _companiesList = list;
          _isLoadingCompanies = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCompanies = false);
      }
    }
  }

  // ─── حساب عدد المناديب الفعلي المباشر للشركة من قاعدة البيانات ───
  Future<void> _fetchRealCompanyDelegateCount(String companyId) async {
    setState(() {
      _isLoadingCompanyCount = true;
      _selectedCompanyRealDelegateCount = null;
    });

    int realCount = 0;
    try {
      final countSnap = await _firestore
          .collection('organizations')
          .doc(_orgId)
          .collection('companies')
          .doc(companyId)
          .collection('delegates')
          .count()
          .get();
      realCount = countSnap.count ?? 0;
    } catch (_) {
      try {
        final cgSnap = await _firestore
            .collectionGroup('delegates')
            .where('companyUID', isEqualTo: companyId)
            .count()
            .get();
        realCount = cgSnap.count ?? 0;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _selectedCompanyRealDelegateCount = realCount;
        _isLoadingCompanyCount = false;
      });
    }
  }

  // ─── Load Global Session Config ───
  Future<void> _loadGlobalSessionConfig() async {
    try {
      final doc = await _firestore
          .collection('system_config')
          .doc('session_control')
          .get();
      if (doc.exists && doc.data() != null) {
        if (mounted) {
          setState(() {
            _lastGlobalResetAt =
                doc.data()!['globalForceLogoutBefore'] as Timestamp?;
          });
        }
      }
    } catch (_) {}
  }

  // ─── تصفية المناديب محلياً ───
  List<Map<String, dynamic>> get _filteredDelegates {
    return _delegatesList.where((d) {
      final isReLogin = d['requireReLogin'] == true;
      if (_selectedFilter == 'active' && isReLogin) return false;
      if (_selectedFilter == 'reLoginRequired' && !isReLogin) return false;

      if (_searchQuery.trim().isEmpty) return true;

      final q = _searchQuery.trim().toLowerCase();
      final name = (d['fullName'] ?? d['name'] ?? '').toString().toLowerCase();
      final phone = (d['phoneNumber'] ?? '').toString().toLowerCase();
      final nationalId = (d['nationalityID'] ?? '').toString().toLowerCase();
      final company = (d['companyName'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          phone.contains(q) ||
          nationalId.contains(q) ||
          company.contains(q);
    }).toList();
  }

  // ─── Action: Force Logout Individual Delegate ───
  Future<void> _confirmForceLogoutDelegate(
      Map<String, dynamic> delegate) async {
    final name = delegate['fullName'] ?? delegate['name'] ?? 'المندوب';
    final compName = delegate['companyName'] ?? '';
    final delegateUid = delegate['uid'] ?? delegate['docId'] ?? '';
    final compId = delegate['companyUID'] ?? '';
    final isAlreadyRequired = delegate['requireReLogin'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(
                isAlreadyRequired
                    ? Icons.lock_reset_rounded
                    : Icons.logout_rounded,
                color: isAlreadyRequired
                    ? Colors.amber.shade800
                    : colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isAlreadyRequired
                      ? 'تأكيد إعادة إنهاء الجلسة'
                      : 'تسجيل خروج إجباري للمندوب',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من إنهاء جلسة المندوب:',
                style: GoogleFonts.cairo(fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_rounded,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                    if (compName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.business_rounded,
                              size: 15, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'الشركة: $compName',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.phone_iphone_rounded,
                            size: 15, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'الهاتف: ${delegate['phoneNumber'] ?? '-'}',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: colorScheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم إجبار المندوب على تسجيل الخروج فوراً ومطالبته بإعادة كتابة رقم الهاتف والرقم القومي لاعتماد شركته الحالية.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.error,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('تأكيد الخروج'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final success = await SessionManagementService.forceLogoutDelegate(
      delegateUid: delegateUid,
      organizationUID: _orgId,
      companyUID: compId,
      delegateName: name,
      delegatePhone: delegate['phoneNumber'],
      adminUid: widget.adminDelegate.uid,
    );

    if (mounted) {
      if (success) {
        setState(() {
          delegate['requireReLogin'] = true;
          delegate['forceLogoutAt'] = Timestamp.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم تسجيل خروج المندوب "$name" بنجاح، وسيلزمه إدخال بياناته للدخول'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تعذر إنهاء الجلسة. تأكد من الاتصال بالإنترنت.')),
        );
      }
    }
  }

  // ─── Action: Bulk Force Logout by Company ───
  Future<void> _confirmBulkLogoutCompany() async {
    if (_selectedCompanyUID == null || _selectedCompanyData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار شركة أولاً')),
      );
      return;
    }

    final compName = _selectedCompanyData!['name'] ?? 'الشركة المحددة';
    final count = _selectedCompanyRealDelegateCount ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.domain_disabled_rounded, color: colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'خروج جماعي لمناديب الشركة',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من إنهاء جلسات جميع مناديب:',
                style: GoogleFonts.cairo(fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.business_rounded,
                            color: colorScheme.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            compName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.groups_rounded,
                            size: 16, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'عدد المناديب المسجلين بالشركة: $count مندوب',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'سيتم إرسال أمر خروج إجباري لكافة مناديب هذه الشركة. عند فتح أي مندوب منهم للتطبيق، سيخرج تلقائياً ليُعيد إدخال رقم الهاتف والرقم القومي.',
                        style: TextStyle(fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.domain_disabled_rounded, size: 16),
              label: const Text('تأكيد الخروج الجماعي'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isProcessingBulk = true);
    try {
      final updatedCount = await SessionManagementService.forceLogoutCompany(
        organizationUID: _orgId,
        companyUID: _selectedCompanyUID!,
        companyName: compName,
        adminUid: widget.adminDelegate.uid,
      );

      if (mounted) {
        setState(() => _isProcessingBulk = false);
        if (updatedCount >= 0) {
          // تحديث القائمة محلياً
          for (final d in _delegatesList) {
            if (d['companyUID'] == _selectedCompanyUID) {
              d['requireReLogin'] = true;
              d['forceLogoutAt'] = Timestamp.now();
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تم إرسال أمر تسجيل الخروج لجميع مناديب شركة "$compName" بنجاح'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل تنفيذ العملية. حاول مرة أخرى.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingBulk = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
    }
  }

  // ─── Action: Global Emergency Reset ───
  Future<void> _confirmGlobalReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.emergency_rounded, color: colorScheme.error),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'تحذير أمني: خروج طوارئ شامل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هل أنت متأكد تماماً من رغبتك في تسجيل خروج إجباري لجميع المناديب في النظام بالكامل؟',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'هذا الإجراء سيُسقط جلسات كافة المناديب النشطين في كل الشركات، وسيلزم الجميع بإعادة إدخال رقم الهاتف والرقم القومي للدخول.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.error,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.power_settings_new_rounded, size: 16),
              label: const Text('تأكيد خروج الطوارئ الشامل'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isProcessingGlobal = true);
    try {
      final success = await SessionManagementService.forceLogoutAllDelegates(
        adminUid: widget.adminDelegate.uid,
      );

      if (mounted) {
        setState(() => _isProcessingGlobal = false);
        if (success) {
          _loadGlobalSessionConfig();
          for (final d in _delegatesList) {
            d['requireReLogin'] = true;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تم إرسال أمر خروج الطوارئ الشامل بنجاح لجميع مناديب النظام'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل تنفيذ خروج الطوارئ الشامل')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingGlobal = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة الجلسات والخروج الإجباري',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
              ),
            ),
            Text(
              'تحكم إداري مباشر لإجبار المناديب على إعادة التحقق',
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
            tooltip: 'تحديث البيانات',
            onPressed: () {
              _loadInitialDelegates();
              _loadCompanies();
              _loadGlobalSessionConfig();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle:
              GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
                icon: Icon(Icons.person_outline_rounded, size: 20),
                text: 'تحكم فردي'),
            Tab(
                icon: Icon(Icons.domain_rounded, size: 20),
                text: 'تحكم بالشركات'),
            Tab(
                icon: Icon(Icons.emergency_rounded, size: 20),
                text: 'خروج طوارئ شامل'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: تحكم فردي بالمناديب
          _buildIndividualTab(colorScheme),

          // Tab 2: تحكم جماعي بالشركات
          _buildBulkCompanyTab(colorScheme),

          // Tab 3: خروج طوارئ شامل
          _buildGlobalEmergencyTab(colorScheme),
        ],
      ),
    );
  }

  // ─── TAB 1: INDIVIDUAL CONTROL (مع قاعدة الـ 20 والـ Material Design 3) ───
  Widget _buildIndividualTab(ColorScheme colorScheme) {
    final filtered = _filteredDelegates;

    return Column(
      children: [
        // شريط البحث
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'ابحث باسم المندوب، الهاتف، البطاقة، أو الشركة...',
              hintStyle: GoogleFonts.cairo(
                  fontSize: 13, color: colorScheme.onSurfaceVariant),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
          ),
        ),

        // شرائح الفلترة (Chips) بأيقونات Google الرسمية
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                selected: _selectedFilter == 'active',
                avatar: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: _selectedFilter == 'active'
                      ? colorScheme.onSecondaryContainer
                      : Colors.green.shade700,
                ),
                label: const Text('جلسات نشطة'),
                labelStyle: GoogleFonts.cairo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() => _selectedFilter = 'active'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _selectedFilter == 'all',
                avatar: Icon(
                  Icons.groups_rounded,
                  size: 16,
                  color: _selectedFilter == 'all'
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                label: Text('الكل (${_delegatesList.length})'),
                labelStyle: GoogleFonts.cairo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() => _selectedFilter = 'all'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _selectedFilter == 'reLoginRequired',
                avatar: Icon(
                  Icons.lock_reset_rounded,
                  size: 16,
                  color: _selectedFilter == 'reLoginRequired'
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.error,
                ),
                label: const Text('مطلوب إعادة الدخول'),
                labelStyle: GoogleFonts.cairo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) =>
                    setState(() => _selectedFilter = 'reLoginRequired'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // قائمة المناديب مع قاعدة الـ 20
        Expanded(
          child: _isLoadingDelegates
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: colorScheme.outlineVariant),
                          const SizedBox(height: 8),
                          Text(
                            'لا توجد نتائج مطابقة للبحث',
                            style: GoogleFonts.cairo(
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadInitialDelegates,
                      child: ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                        itemCount: filtered.length + (_hasReachedMax ? 1 : 1),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, index) {
                          if (index < filtered.length) {
                            final d = filtered[index];
                            return _buildDelegateCard(d, colorScheme);
                          }

                          // تذييل القائمة (مؤشر التحميل أو نهاية القائمة لقاعدة الـ 20)
                          if (_isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5),
                                ),
                              ),
                            );
                          }

                          if (_hasReachedMax && filtered.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  'تم عرض جميع المناديب المتاحين',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ),
                            );
                          }

                          return const SizedBox.shrink();
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDelegateCard(
      Map<String, dynamic> delegate, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final name = delegate['fullName'] ?? delegate['name'] ?? 'مندوب';
    final company = delegate['companyName'] ?? 'بدون شركة';
    final phone = delegate['phoneNumber'] ?? '';
    final nationalId = delegate['nationalityID'] ?? '';
    final isReLoginRequired = delegate['requireReLogin'] == true;
    final photoUrl = delegate['personalPhotoURL'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReLoginRequired
              ? colorScheme.error.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isReLoginRequired ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          AppAvatar(
            imageUrl: photoUrl,
            fallbackText: name,
            radius: 22,
            backgroundColor: isReLoginRequired
                ? colorScheme.errorContainer.withValues(alpha: 0.3)
                : colorScheme.primaryContainer,
            foregroundColor: isReLoginRequired
                ? colorScheme.error
                : colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isReLoginRequired
                            ? colorScheme.errorContainer.withValues(alpha: 0.5)
                            : Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isReLoginRequired
                                ? Icons.lock_reset_rounded
                                : Icons.check_circle_rounded,
                            size: 11,
                            color: isReLoginRequired
                                ? colorScheme.error
                                : Colors.green.shade800,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isReLoginRequired
                                ? 'مطلوب تسجيل الدخول'
                                : 'جلسة نشطة',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isReLoginRequired
                                  ? colorScheme.error
                                  : Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.business_rounded,
                        size: 13.5, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        company,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (phone.isNotEmpty) ...[
                      Icon(Icons.phone_iphone_rounded,
                          size: 13, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        phone,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (phone.isNotEmpty && nationalId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text('•',
                            style:
                                TextStyle(color: colorScheme.outlineVariant)),
                      ),
                    if (nationalId.isNotEmpty) ...[
                      Icon(Icons.badge_rounded,
                          size: 13, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          nationalId,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action Button (Material 3 Stadium)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
              backgroundColor: isReLoginRequired
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.errorContainer.withValues(alpha: 0.6),
              foregroundColor: isReLoginRequired
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onErrorContainer,
              shape: const StadiumBorder(),
            ),
            onPressed: () => _confirmForceLogoutDelegate(delegate),
            icon: Icon(
              isReLoginRequired
                  ? Icons.lock_reset_rounded
                  : Icons.logout_rounded,
              size: 15,
            ),
            label: Text(
              isReLoginRequired ? 'تجديد' : 'خروج إجباري',
              style: GoogleFonts.cairo(
                  fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: BULK COMPANY TAB (مع التنسيق الكامل وإصلاح الـ Overflow) ───
  Widget _buildBulkCompanyTab(ColorScheme colorScheme) {
    if (_isLoadingCompanies) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // بطاقة معلومات علوية
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.domain_rounded,
                      color: colorScheme.onPrimary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خروج جماعي لجميع مناديب شركة',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'إنهاء جلسات كافة مناديب الشركة المحددة بنقرة واحدة لإلزامهم بإعادة الدخول',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'اختر الشركة لتسجيل خروج مناديبها:',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 8),

          // قائمة اختيار الشركة مع معالجة الـ Overflow وإلغاء الأرقام الوهمية
          DropdownButtonFormField<String>(
            isExpanded: true,
            isDense: true,
            initialValue: _selectedCompanyUID,
            decoration: InputDecoration(
              filled: true,
              fillColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
              prefixIcon: const Icon(Icons.business_rounded),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              hintText: 'اضغط لاختيار الشركة...',
              hintStyle: GoogleFonts.cairo(
                  fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            items: _companiesList.map((c) {
              final name = c['name'] ?? 'شركة بدون اسم';
              return DropdownMenuItem<String>(
                value: c['id'] as String,
                child: Text(
                  name,
                  style: GoogleFonts.cairo(
                      fontSize: 13.5, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedCompanyUID = val;
                _selectedCompanyData =
                    _companiesList.firstWhere((c) => c['id'] == val);
              });
              if (val != null) {
                _fetchRealCompanyDelegateCount(val);
              }
            },
          ),
          const SizedBox(height: 24),

          // تفاصيل الشركة المختارة
          if (_selectedCompanyData != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.business_rounded,
                                color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedCompanyData!['name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isLoadingCompanyCount
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.groups_rounded,
                                      size: 14, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_selectedCompanyRealDelegateCount ?? 0} مندوب مسجل',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  Text(
                    'عند تنفيذ الخروج الجماعي:',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. سيتم إبطال جلسة كل مندوب يعمل تحت هذه الشركة فورياً.\n2. عند فتح التطبيق، سيتم توجيههم لشاشة تسجيل الدخول.\n3. سيُطلب منهم إدخال رقم الهاتف ورقم البطاقة لتحديث بياناتهم.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // زر التنفيذ الجماعي (M3 Stadium)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: _isProcessingBulk ? null : _confirmBulkLogoutCompany,
              icon: _isProcessingBulk
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.domain_disabled_rounded),
              label: Text(
                _isProcessingBulk
                    ? 'جاري إرسال أمر الخروج...'
                    : 'تسجيل خروج جماعي لمناديب الشركة',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── TAB 3: GLOBAL EMERGENCY TAB ───
  Widget _buildGlobalEmergencyTab(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.emergency_rounded,
                          color: colorScheme.onError, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خروج طوارئ شامل لكافة المناديب',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.5,
                              color: colorScheme.error,
                            ),
                          ),
                          Text(
                            'Global Session Invalidation',
                            style: TextStyle(
                                fontSize: 11, color: colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'هذا الإجراء الطارئ مخصص للسوبر أدمن فقط عند إجراء تحديثات شاملة على النظام أو عند نقل وإعادة توزيع المناديب على نطاق واسع.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'النتيجة:',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '• كل مندوب لديه جلسة مفتوحة حالياً في الهاتف سيتم إخراجه فورياً ومطالبته برقم الهاتف والرقم القومي.\n• لن يتم المساس بحسابات الأدمن أو السوبر أدمن أو المشرفين.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_lastGlobalResetAt != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 16, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'آخر خروج شامل تم تنفيذه: ${_lastGlobalResetAt!.toDate().toString().substring(0, 16)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _isProcessingGlobal ? null : _confirmGlobalReset,
                    icon: _isProcessingGlobal
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.power_settings_new_rounded),
                    label: Text(
                      _isProcessingGlobal
                          ? 'جاري التنفيذ...'
                          : 'تسجيل خروج إجباري لجميع المناديب في النظام',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
