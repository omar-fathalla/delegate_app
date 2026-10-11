import 'package:flutter/material.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/photo_permission/presentation/widgets/sync_status_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart';

class DelegateHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final VoidCallback? onNavigateToAttendance;
  final VoidCallback? onNavigateToLeaves;

  const DelegateHomeScreen({
    super.key,
    required this.delegate,
    this.onNavigateToAttendance,
    this.onNavigateToLeaves,
  });

  @override
  State<DelegateHomeScreen> createState() => _DelegateHomeScreenState();
}

class _DelegateHomeScreenState extends State<DelegateHomeScreen>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, List<Map<String, dynamic>>> _supervisorsCache = {};
  static final Map<String, DateTime> _supervisorsCacheTime = {};

  List<Map<String, dynamic>> _supervisorsData = [];
  bool _loadingSupervisor = false;
  String? _supervisorError;

  int _attendedDays = 0;
  int _absentDays = 0;
  int _approvedLeavesThisMonth = 0;

  List<Attendance> _recentSessions = [];
  static final Map<String, String> _orgNamesCache = {
    'PiioBFgxaHAeuRdjlDgj': 'fathalla market',
    '5DE6702w6hFwycJfZyqM': 'جملة ماركت',
    'gOaRsmPocj2xV018m0hY': 'جملة ماركت',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cacheKey = '${widget.delegate.organizationUID}_${widget.delegate.companyUID}';
    if (_supervisorsCache.containsKey(cacheKey)) {
      _supervisorsData = List.from(_supervisorsCache[cacheKey]!);
    }
    _fetchSupervisors();
    _loadAttendanceData();
    _loadRecentActivity();
  }

  @override
  void didUpdateWidget(covariant DelegateHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID ||
        oldWidget.delegate.companyUID != widget.delegate.companyUID) {
      final cacheKey = '${widget.delegate.organizationUID}_${widget.delegate.companyUID}';
      if (_supervisorsCache.containsKey(cacheKey)) {
        setState(() {
          _supervisorsData = List.from(_supervisorsCache[cacheKey]!);
        });
      }
      _fetchSupervisors();
      _loadAttendanceData();
      _loadRecentActivity();
    }
  }

  Future<void> _fetchSupervisors({bool forceRefresh = false}) async {
    final orgId = widget.delegate.organizationUID;
    final compId = widget.delegate.companyUID;

    if (orgId.isEmpty || compId.isEmpty) return;

    final cacheKey = '${orgId}_$compId';
    final hasCached = _supervisorsCache.containsKey(cacheKey);

    if (!hasCached && !forceRefresh) {
      setState(() {
        _loadingSupervisor = true;
        _supervisorError = null;
      });
    }

    try {
      final List<Map<String, dynamic>> fetchedSupervisors = [];
      String companyPhone = widget.delegate.supervisorPhone ?? '';
      String companyEmail = '';
      String companySupervisorName = widget.delegate.supervisorName ?? '';
      String companyName = widget.delegate.companyName;

      // 0. Direct lookup by delegate's assigned supervisor UID if present
      final directSupervisorUid = widget.delegate.supervisorUid;
      if (directSupervisorUid != null && directSupervisorUid.isNotEmpty) {
        try {
          final supDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(directSupervisorUid)
              .getResilient(forceServer: forceRefresh);
          if (supDoc.exists) {
            final sData = supDoc.data()!;
            final name = _extractPersonName(sData, companyName);
            final phone = (sData['phoneNumber'] as String?)?.trim() ??
                (widget.delegate.supervisorPhone ?? '');
            fetchedSupervisors.add({
              ...sData,
              'displayName': name.isNotEmpty
                  ? name
                  : (companySupervisorName.isNotEmpty
                      ? companySupervisorName
                      : 'مشرف الشركة'),
              'phoneNumber': phone,
              'email': (sData['email'] as String?)?.trim() ?? '',
              'companyName': companyName,
            });
          }
        } catch (_) {}
      }

      // Also check supervisor from delegate's supervisorPhone if UID lookup didn't yield a supervisor
      if (fetchedSupervisors.isEmpty &&
          widget.delegate.supervisorPhone != null &&
          widget.delegate.supervisorPhone!.trim().isNotEmpty) {
        try {
          final cleanPhone = widget.delegate.supervisorPhone!.replaceAll(RegExp(r'[^\d+]'), '');
          final phoneSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: cleanPhone)
              .getResilient(forceServer: forceRefresh);
          if (phoneSnap.docs.isNotEmpty) {
            final sData = phoneSnap.docs.first.data();
            final name = _extractPersonName(sData, companyName);
            fetchedSupervisors.add({
              ...sData,
              'displayName': name.isNotEmpty
                  ? name
                  : (companySupervisorName.isNotEmpty
                      ? companySupervisorName
                      : 'مشرف الشركة'),
              'phoneNumber': cleanPhone,
              'email': (sData['email'] as String?)?.trim() ?? '',
              'companyName': companyName,
            });
          }
        } catch (_) {}
      }

      // 1. First attempt: Get company info & contact phone
      try {
        final compDoc = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(compId)
            .getResilient(forceServer: forceRefresh);

        if (compDoc.exists) {
          final compData = compDoc.data();
          if (compData != null) {
            companyPhone =
                (compData['phone'] as String?)?.trim() ??
                (compData['phoneNumber'] as String?)?.trim() ??
                companyPhone;
            companyEmail =
                (compData['email'] as String?)?.trim() ??
                (compData['emailAddress'] as String?)?.trim() ??
                '';
            final cName =
                (compData['name'] as String?)?.trim() ??
                (compData['displayName'] as String?)?.trim() ??
                '';
            if (cName.isNotEmpty) {
              companyName = cName;
            }

            // Look for explicit person supervisor name (must not be company name)
            final rawSupervisor =
                (compData['supervisorName'] as String?)?.trim() ??
                (compData['supervisor_name'] as String?)?.trim() ??
                (compData['contactName'] as String?)?.trim() ??
                (compData['contact_name'] as String?)?.trim() ??
                (compData['adminName'] as String?)?.trim() ??
                (compData['managerName'] as String?)?.trim() ??
                '';

            if (rawSupervisor.isNotEmpty &&
                rawSupervisor.toLowerCase() != companyName.toLowerCase()) {
              companySupervisorName = rawSupervisor;
            }
          }
        }
      } catch (_) {}

      // 2. Query the users collection for company admins/supervisors (cross-organization query by companyUID)
      try {
        final userRoles = [
          'company-admin',
          'company_admin',
          'supervisor',
          'company_supervisor',
          'company-supervisor',
          'admin',
        ];

        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('companyUID', isEqualTo: compId)
            .getResilient(forceServer: forceRefresh);

        if (snapshot.docs.isNotEmpty) {
          for (final doc in snapshot.docs) {
            final adminData = doc.data();
            final role = (adminData['role'] as String?)?.trim().toLowerCase() ?? '';
            if (userRoles.any((r) => r.toLowerCase() == role)) {
              final phone = (adminData['phoneNumber'] as String?)?.trim() ?? '';
              final name = _extractPersonName(adminData, companyName);

              final exists = fetchedSupervisors.any(
                (s) =>
                    (s['phoneNumber'] as String? ?? '') == phone &&
                    phone.isNotEmpty,
              );

              if (!exists) {
                fetchedSupervisors.add({
                  ...adminData,
                  'displayName':
                      name.isNotEmpty ? name : companySupervisorName,
                  'phoneNumber': phone.isNotEmpty ? phone : companyPhone,
                  'email':
                      (adminData['email'] as String?)?.trim() ?? companyEmail,
                  'companyName': companyName,
                });
              }
            }
          }
        }
      } catch (_) {}

      // 3. Query delegates subcollection for supervisors
      if (fetchedSupervisors.isEmpty ||
          fetchedSupervisors.every(
            (s) => (s['displayName'] as String? ?? '').isEmpty,
          )) {
        try {
          final delSnapshot = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(orgId)
              .collection('companies')
              .doc(compId)
              .collection('delegates')
              .where('position', whereIn: ['supervisor', 'Supervisor', 'مشرف'])
              .getResilient(forceServer: forceRefresh);

          for (final doc in delSnapshot.docs) {
            final delData = doc.data();
            final phone = (delData['phoneNumber'] as String?)?.trim() ?? '';
            final name = _extractPersonName(delData, companyName);

            final exists = fetchedSupervisors.any(
              (s) =>
                  (s['phoneNumber'] as String? ?? '') == phone &&
                  phone.isNotEmpty,
            );

            if (!exists) {
              fetchedSupervisors.add({
                ...delData,
                'displayName':
                    name.isNotEmpty ? name : companySupervisorName,
                'phoneNumber': phone.isNotEmpty ? phone : companyPhone,
                'email': (delData['email'] as String?)?.trim() ?? companyEmail,
                'companyName': companyName,
              });
            }
          }
        } catch (_) {}
      }

      // 4. If companyPhone exists, also try lookup in users collection by phoneNumber
      if (companyPhone.isNotEmpty &&
          (fetchedSupervisors.isEmpty ||
              fetchedSupervisors.every(
                (s) => (s['displayName'] as String? ?? '').isEmpty,
              ))) {
        try {
          final cleanPhone = companyPhone.replaceAll(RegExp(r'[^\d+]'), '');
          var phoneSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: cleanPhone)
              .getResilient(forceServer: forceRefresh);

          if (phoneSnapshot.docs.isEmpty && cleanPhone.startsWith('0')) {
            final altPhone = cleanPhone.substring(1);
            phoneSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('phoneNumber', isEqualTo: altPhone)
                .getResilient(forceServer: forceRefresh);
          }

          if (phoneSnapshot.docs.isNotEmpty) {
            final uData = phoneSnapshot.docs.first.data();
            final name = _extractPersonName(uData, companyName);
            if (name.isNotEmpty) {
              fetchedSupervisors.removeWhere(
                (s) => (s['phoneNumber'] as String? ?? '') == companyPhone,
              );
              fetchedSupervisors.insert(0, {
                ...uData,
                'displayName': name,
                'phoneNumber': companyPhone,
                'email': (uData['email'] as String?)?.trim() ?? companyEmail,
                'companyName': companyName,
              });
            }
          }
        } catch (_) {}
      }

      // 5. Fallback from company document
      if (fetchedSupervisors.isEmpty &&
          (companyPhone.isNotEmpty || companySupervisorName.isNotEmpty)) {
        fetchedSupervisors.add({
          'displayName':
              companySupervisorName.isNotEmpty
                  ? companySupervisorName
                  : 'مشرف الشركة',
          'phoneNumber': companyPhone,
          'email': companyEmail,
          'companyName': companyName,
          'isCompanyDoc': true,
        });
      }

      _supervisorsCache[cacheKey] = fetchedSupervisors;
      _supervisorsCacheTime[cacheKey] = DateTime.now();

      if (mounted) {
        setState(() {
          _supervisorsData = fetchedSupervisors;
          _loadingSupervisor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _supervisorError = e.toString();
          _loadingSupervisor = false;
        });
      }
    }
  }

  String _extractPersonName(Map<String, dynamic> data, [String companyName = '']) {
    final fullName = (data['fullName'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return fullName;
    }

    final displayName = (data['displayName'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final name = (data['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final first = (data['firstName'] as String?)?.trim() ?? '';
    final last = (data['lastName'] as String?)?.trim() ?? '';
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) {
      return combined;
    }

    final userName = (data['userName'] as String?)?.trim() ??
        (data['username'] as String?)?.trim() ??
        '';
    if (userName.isNotEmpty) {
      return userName;
    }

    return '';
  }

  Future<void> _callNumber(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _fetchSupervisors(forceRefresh: true),
            _loadAttendanceData(forceRefresh: true),
            _loadRecentActivity(forceRefresh: true),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SyncStatusBanner(),
              _buildWelcomeHeroCard(context),
              const SizedBox(height: 16),
              _buildMonthlyAttendanceSummaryCard(context),
              const SizedBox(height: 14),
              _buildRecentActivityBriefCard(context),
              const SizedBox(height: 14),
              _buildLeavesAndRequestsCard(context),
              const SizedBox(height: 16),
              ..._buildSupervisorsList(context),
              const SizedBox(height: 12),
              _buildPhotoCaptureCard(context),
              const SizedBox(height: 80), // Padding for bottom nav
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      padding: const EdgeInsets.all(20),
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
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting & Role Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic
                          ? 'أهلاً بك، ${widget.delegate.firstName}'
                          : 'Welcome, ${widget.delegate.firstName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.delegate.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final userData = snapshot.data?.data();
                        final positionLabel = widget.delegate.position ==
                                    DelegatePosition.promoter ||
                                widget.delegate.role ==
                                    UserRole.marketingPromotion
                            ? (isArabic ? 'مروج ميداني' : 'Field Promoter')
                            : widget.delegate.position ==
                                    DelegatePosition.supervisor
                                ? (isArabic ? 'مشرف ميداني' : 'Field Supervisor')
                                : (isArabic ? 'مندوب ميداني' : 'Field Delegate');

                        final activeOrg = widget.delegate.organizationName.trim();
                        final affiliatedOrgs = <String>{};

                        if (activeOrg.isNotEmpty) {
                          affiliatedOrgs.add(activeOrg);
                        }

                        if (userData != null) {
                          final rawList = userData['organizationNames'] ??
                              userData['organizations'];
                          if (rawList is List) {
                            for (final item in rawList) {
                              if (item is String && item.trim().isNotEmpty) {
                                affiliatedOrgs.add(item.trim());
                              }
                            }
                          }
                        }

                        for (final name in widget.delegate.allOrganizationNames) {
                          if (name.trim().isNotEmpty) {
                            affiliatedOrgs.add(name.trim());
                          }
                        }

                        final orgsList = affiliatedOrgs.toList();

                        if (orgsList.length <= 1) {
                          return Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildPositionChip(positionLabel),
                              if (orgsList.isNotEmpty)
                                _buildWelcomeOrgChip(
                                  orgName: orgsList.first,
                                  isActive: true,
                                  isArabic: isArabic,
                                ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPositionChip(positionLabel),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final org in orgsList)
                                  _buildWelcomeOrgChip(
                                    orgName: org,
                                    isActive: org == activeOrg,
                                    isArabic: isArabic,
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
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
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AppAvatar(
                      imageUrl: photoUrl,
                      fallbackText: widget.delegate.firstName,
                      radius: 26,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      foregroundColor: Colors.white,
                      fallbackIcon: Icons.person_pin_rounded,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),

          // Core Duties Summary
          Text(
            isArabic ? 'المهام الأساسية للمندوب:' : 'Core Delegate Duties:',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          _buildDutyItem(
            icon: Icons.location_on_rounded,
            text:
                isArabic
                    ? 'تسجيل الحضور والانصراف المعتمد جغرافياً عند الوصول إلى الفرع.'
                    : 'Geofenced attendance check-in & check-out at branches.',
          ),
          const SizedBox(height: 6),
          _buildDutyItem(
            icon: Icons.assignment_turned_in_rounded,
            text:
                isArabic
                    ? 'متابعة وتنفيذ المهام اليومية الموكلة بدقة.'
                    : 'Review and complete assigned daily tasks accurately.',
          ),
          const SizedBox(height: 6),
          _buildDutyItem(
            icon: Icons.camera_alt_rounded,
            text:
                isArabic
                    ? 'توثيق وتصوير العروض والبرندات الميدانية داخل الهايبر ماركت والفروع.'
                    : 'Capture & document approved offers and brands in hypermarkets.',
          ),
        ],
      ),
    );
  }

  Widget _buildDutyItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.badge_rounded,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeOrgChip({
    required String orgName,
    required bool isActive,
    required bool isArabic,
  }) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFDE68A).withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.domain_rounded,
              size: 14,
              color: Color(0xFFFEF3C7),
            ),
            const SizedBox(width: 6),
            Text(
              orgName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFEF3C7),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 5.5,
              height: 5.5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 14,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 6),
          Text(
            orgName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSupervisorsList(BuildContext context) {
    if (_loadingSupervisor) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }

    if (_supervisorsData.isEmpty) {
      return [_buildEmptySupervisorCard(context)];
    }

    return _supervisorsData
        .map((supervisor) => _buildSupervisorCard(context, supervisor))
        .toList();
  }

  Widget _buildEmptySupervisorCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.errorContainer.withValues(
                alpha: 0.2,
              ),
              foregroundColor: colorScheme.error,
              child: const Icon(Icons.person_off_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مشرف الشركة (${widget.delegate.companyName})',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _supervisorError != null
                        ? 'خطأ: $_supervisorError'
                        : 'لا يوجد مشرف مسجل لهذه الشركة حالياً\n(Company ID: ${widget.delegate.companyUID})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color:
                          _supervisorError != null
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupervisorCard(
    BuildContext context,
    Map<String, dynamic> supervisorData,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final rawName = (supervisorData['displayName'] as String?)?.trim() ??
        (supervisorData['fullName'] as String?)?.trim() ??
        (supervisorData['name'] as String?)?.trim() ??
        '';
    final companyName =
        supervisorData['companyName'] as String? ?? widget.delegate.companyName;
    final phone = (supervisorData['phoneNumber'] as String?)?.trim() ?? '';

    final displayName = rawName.isNotEmpty
        ? rawName
        : (isArabic ? 'مشرف الشركة' : 'Company Supervisor');

    final subtitleText = companyName.isNotEmpty
        ? (isArabic
            ? 'مشرف شركة $companyName'
            : 'Supervisor - $companyName')
        : (isArabic ? 'مشرف الشركة المنتدبة' : 'Assigned Company Supervisor');

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: const Icon(Icons.person_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
            ),
            if (phone.isNotEmpty) ...[
              IconButton(
                onPressed: () => _callNumber(phone),
                icon: const Icon(Icons.phone_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.tertiaryContainer,
                  foregroundColor: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _openWhatsApp(phone),
                icon: const Icon(Icons.chat_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(
                    0xFF25D366,
                  ).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFF1DA851),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCaptureCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Card(
      elevation: 2,
      shadowColor: colorScheme.primary.withValues(alpha: 0.2),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () {
          context.push('/photo-permissions/delegate', extra: widget.delegate);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                colorScheme.primaryContainer.withValues(alpha: 0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? 'تصوير العروض الميدانية'
                              : 'Field Offer Photos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isArabic
                              ? 'التقاط وإرسال صور العروض والبرندات المعتمدة داخل الهايبر ماركت'
                              : 'Capture & upload approved brand photos inside hypermarket',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isArabic
                          ? 'اضغط هنا لبدء التصوير داخل الهايبر ماركت'
                          : 'Tap here to start photographing inside hypermarket',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isArabic
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                      size: 16,
                      color: colorScheme.primary,
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

  // --- Monthly Attendance Summary Logic & UI ---

  DateTime _getTrustedNow() {
    try {
      if (sl.isRegistered<TrustedTimeService>()) {
        return sl<TrustedTimeService>().now;
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<void> _loadAttendanceData({bool forceRefresh = false}) async {
    // 1. Cache-first: read immediately from local persistent cache (0 ms)
    try {
      if (sl.isRegistered<AttendanceLocalDataSource>()) {
        final localDataSource = sl<AttendanceLocalDataSource>();
        final cached = await localDataSource.getLastAttendanceHistory();
        if (cached.isNotEmpty) {
          _computeStats(cached);
        }
      }
    } catch (_) {}

    // 2. Load approved leaves this month from leave_requests
    int approvedLeaves = _approvedLeavesThisMonth;
    try {
      final leavesSnap = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('delegateUid', isEqualTo: widget.delegate.uid)
          .where('status', isEqualTo: 'approved')
          .getResilient(forceServer: forceRefresh);

      final now = _getTrustedNow();
      int count = 0;
      for (final doc in leavesSnap.docs) {
        final data = doc.data();
        if (data['isHourly'] == true) continue;
        final start = data['startDate'];
        if (start is Timestamp) {
          final date = start.toDate();
          if (date.year == now.year && date.month == now.month) {
            final days = (data['daysCount'] as num?)?.toInt() ?? 1;
            count += days;
          }
        }
      }
      approvedLeaves = count;
    } catch (_) {}

    // 3. Remote fetch cross-organization attendance for unified monthly stats
    try {
      if (sl.isRegistered<GetHistory>()) {
        final getHistory = sl<GetHistory>();
        final result = await getHistory(
          GetHistoryParams(
            userId: widget.delegate.uid,
            organizationId: '', // Empty means all affiliated organizations
            nationalityID: widget.delegate.nationalityID,
            phoneNumber: widget.delegate.phoneNumber,
          ),
        );
        result.fold(
          (_) {},
          (history) {
            _computeStats(history, approvedLeavesCount: approvedLeaves);
          },
        );
      }
    } catch (_) {}
  }

  void _computeStats(List<Attendance> history, {int? approvedLeavesCount}) {
    final trustedNow = _getTrustedNow();
    final currentMonth = trustedNow.month;
    final currentYear = trustedNow.year;
    final currentDay = trustedNow.day;
    final totalDaysInMonth = DateUtils.getDaysInMonth(currentYear, currentMonth);

    // Filter unique days attended in current month across ALL affiliated organizations
    final daySet = <String>{};
    for (final item in history) {
      if (item.checkInTime.month == currentMonth &&
          item.checkInTime.year == currentYear &&
          item.userId == widget.delegate.uid) {
        final dayKey =
            '${item.checkInTime.year}-${item.checkInTime.month}-${item.checkInTime.day}';
        daySet.add(dayKey);
      }
    }
    final attended = daySet.length;

    // Active days for new delegates (using earliest registration date across all chains)
    DateTime earliestCreatedAt = widget.delegate.createdAt;
    try {
      if (sl.isRegistered<AuthLocalDataSource>()) {
        final all = sl<AuthLocalDataSource>().getCachedAllDelegatesData();
        for (final d in all) {
          if (d.createdAt.isBefore(earliestCreatedAt)) {
            earliestCreatedAt = d.createdAt;
          }
        }
      }
    } catch (_) {}

    int activeDays = currentDay;
    if (earliestCreatedAt.year == currentYear &&
        earliestCreatedAt.month == currentMonth &&
        earliestCreatedAt.day > 1) {
      activeDays = (currentDay - earliestCreatedAt.day + 1)
          .clamp(1, totalDaysInMonth);
    }

    final leavesThisMonth = approvedLeavesCount ?? _approvedLeavesThisMonth;
    // 4 off days per month (~1 every 7 days)
    final offSoFar = (activeDays / 7).floor().clamp(0, 4);
    // Working days elapsed excludes regular off days and approved leave days
    final elapsedWorkDays = (activeDays - offSoFar - leavesThisMonth).clamp(0, 26);
    final absent = (elapsedWorkDays - attended).clamp(0, 26);

    if (mounted) {
      setState(() {
        _attendedDays = attended;
        _absentDays = absent;
        _approvedLeavesThisMonth = leavesThisMonth;
      });
    }
  }

  Widget _buildMonthlyAttendanceSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final trustedNow = _getTrustedNow();
    final monthName =
        DateFormat('MMMM yyyy', isArabic ? 'ar' : 'en').format(trustedNow);

    return InkWell(
      onTap: widget.onNavigateToAttendance,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row: Title & Link to Attendance Tab
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isArabic
                          ? 'ملخص الحضور والغياب ($monthName)'
                          : 'Attendance Summary ($monthName)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (widget.onNavigateToAttendance != null)
                  Row(
                    children: [
                      Text(
                        isArabic ? 'التفاصيل' : 'Details',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        isArabic
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // 3 Stat Badges: Attendance, Absence, Off Days
            Row(
              children: [
                // 1. أيام الحضور
                Expanded(
                  child: _buildAttendanceStatPill(
                    context,
                    title: isArabic ? 'أيام الحضور' : 'Attended',
                    value: isArabic ? '$_attendedDays يوم' : '$_attendedDays d',
                    icon: Icons.check_circle_rounded,
                    containerColor: colorScheme.primaryContainer,
                    iconColor: colorScheme.primary,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),

                // 2. أيام الغياب
                Expanded(
                  child: _buildAttendanceStatPill(
                    context,
                    title: isArabic ? 'أيام الغياب' : 'Absent',
                    value: isArabic ? '$_absentDays يوم' : '$_absentDays d',
                    icon: Icons.cancel_rounded,
                    containerColor: colorScheme.errorContainer,
                    iconColor: colorScheme.onErrorContainer,
                    textColor: _absentDays > 0
                        ? colorScheme.error
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),

                // 3. أيام الإجازة
                Expanded(
                  child: _buildAttendanceStatPill(
                    context,
                    title: isArabic ? 'أيام الإجازة' : 'Days Off',
                    value: isArabic
                        ? '$_approvedLeavesThisMonth من 4 أيام'
                        : '$_approvedLeavesThisMonth of 4 days',
                    icon: Icons.event_available_rounded,
                    containerColor: colorScheme.tertiaryContainer,
                    iconColor: colorScheme.onTertiaryContainer,
                    textColor: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Clarification Note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'نظام 26 يوم عمل شهرياً • 4 أيام إجازة مستبعدة من الغياب'
                          : '26 work days/month • 4 off days excluded from absence',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadRecentActivity({bool forceRefresh = false}) async {
    try {
      if (sl.isRegistered<AttendanceRemoteDataSource>()) {
        final remoteDS = sl<AttendanceRemoteDataSource>();
        final sessions = await remoteDS.getRecentSessionsAcrossOrgs(
          widget.delegate.uid,
          nationalityID: widget.delegate.nationalityID,
          phoneNumber: widget.delegate.phoneNumber,
          limit: 4,
        );
        if (mounted) {
          setState(() {
            _recentSessions = sessions;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent activity: $e');
    }
  }

  String _resolveOrgLabel(String orgId) {
    final clean = orgId.trim();
    if (clean.isEmpty) return widget.delegate.organizationName;
    if (_orgNamesCache.containsKey(clean)) {
      return _orgNamesCache[clean]!;
    }
    if (clean == widget.delegate.organizationUID) {
      _orgNamesCache[clean] = widget.delegate.organizationName;
      return widget.delegate.organizationName;
    }
    return widget.delegate.organizationName;
  }

  Widget _buildRecentActivityBriefCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    if (_recentSessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isArabic
                        ? 'آخر الفروع والنشاط الميداني'
                        : 'Recent Branch Activity',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              if (widget.onNavigateToAttendance != null)
                InkWell(
                  onTap: widget.onNavigateToAttendance,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isArabic ? 'عرض السجل' : 'View Log',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          isArabic
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Session Items (latest 2-3 sessions)
          ..._recentSessions.take(3).map((session) {
            final branchName = session.branchName ??
                (isArabic ? 'فرع غير محدد' : 'Unknown Branch');
            final orgName = _resolveOrgLabel(session.organizationId);
            final checkInStr =
                DateFormat('hh:mm a', isArabic ? 'ar' : 'en').format(session.checkInTime);
            final checkOutStr = session.checkOutTime != null
                ? DateFormat('hh:mm a', isArabic ? 'ar' : 'en').format(session.checkOutTime!)
                : (isArabic ? 'قيد العمل' : 'Active');

            // Format date relative (اليوم، أمس، أو التاريخ)
            final now = _getTrustedNow();
            final isToday = session.checkInTime.year == now.year &&
                session.checkInTime.month == now.month &&
                session.checkInTime.day == now.day;
            final isYesterday = session.checkInTime.year == now.year &&
                session.checkInTime.month == now.month &&
                session.checkInTime.day == now.day - 1;

            final dateLabel = isToday
                ? (isArabic ? 'اليوم' : 'Today')
                : isYesterday
                    ? (isArabic ? 'أمس' : 'Yesterday')
                    : DateFormat('EEE، d MMM', isArabic ? 'ar' : 'en').format(session.checkInTime);

            // Compute Duration
            String durationLabel = '';
            if (session.checkOutTime != null) {
              final diff = session.checkOutTime!.difference(session.checkInTime);
              final hours = diff.inHours;
              final minutes = diff.inMinutes % 60;
              durationLabel = isArabic
                  ? '$hours س $minutes د'
                  : '${hours}h ${minutes}m';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Branch Name + Org Chip
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          branchName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Organization Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.storefront_rounded,
                              size: 11,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              orgName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Row 2: Date + In/Out Times + Duration
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Date pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // Check-in
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.login_rounded,
                            size: 12,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            checkInStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      // Check-out
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 12,
                            color: session.checkOutTime != null
                                ? colorScheme.error
                                : const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            checkOutStr,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: session.checkOutTime == null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: session.checkOutTime != null
                                  ? colorScheme.onSurfaceVariant
                                  : const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      // Duration
                      if (durationLabel.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timelapse_rounded,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              durationLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttendanceStatPill(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color containerColor,
    required Color iconColor,
    required Color textColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: containerColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLeavesAndRequestsCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('leave_requests')
          .where('companyUID', isEqualTo: widget.delegate.companyUID)
          .where('delegateUid', isEqualTo: widget.delegate.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        int pendingCount = 0;
        for (final doc in docs) {
          final data = doc.data();
          if (data['status'] == 'pending') {
            pendingCount++;
          }
        }

        return Card(
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: pendingCount > 0
                  ? Colors.amber.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: pendingCount > 0 ? 1.5 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (widget.onNavigateToLeaves != null) {
                widget.onNavigateToLeaves!();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DelegateLeavesAndRequestsScreen(
                      delegate: widget.delegate,
                    ),
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.event_note_rounded,
                      size: 26,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isArabic
                                  ? 'طلباتي (الإجازات والأعذار)'
                                  : 'My Requests & Leaves',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade800,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$pendingCount معلق',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isArabic
                              ? 'تقديم ومتابعة طلبات الإجازة والأعذار ورصيدك السنوي'
                              : 'Submit & track your leave and excuse requests',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isArabic
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

