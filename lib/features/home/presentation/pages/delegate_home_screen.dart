import 'package:flutter/material.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/photo_permission/presentation/widgets/sync_status_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class DelegateHomeScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateHomeScreen({super.key, required this.delegate});

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

      // 1. First attempt: Get supervisor info directly from the company document
      final compDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(compId)
          .get();

      if (compDoc.exists) {
        final compData = compDoc.data();
        if (compData != null) {
          final companyPhone =
              compData['phone'] as String? ??
              compData['phoneNumber'] as String? ??
              '';
          final companyEmail =
              compData['email'] as String? ??
              compData['emailAddress'] as String? ??
              '';
          final companySupervisorName =
              compData['supervisorName'] as String? ??
              compData['contactName'] as String? ??
              compData['adminName'] as String? ??
              compData['managerName'] as String? ??
              compData['displayName'] as String? ??
              '';

          if (companyPhone.isNotEmpty ||
              companyEmail.isNotEmpty ||
              companySupervisorName.isNotEmpty) {
            fetchedSupervisors.add({
              'displayName':
                  companySupervisorName.isNotEmpty
                      ? companySupervisorName
                      : 'مشرف الشركة',
              'phoneNumber': companyPhone,
              'email': companyEmail,
              'isCompanyDoc': true,
            });
          }
        }
      }

      // 2. Query the users collection for all company admins
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('organizationUID', isEqualTo: orgId)
          .where('companyUID', isEqualTo: compId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        for (final doc in snapshot.docs) {
          final role = doc.data()['role'] as String? ?? '';
          if (role == 'company-admin' || role == 'Supervisor') {
            final adminData = doc.data();

            // Avoid adding duplicates
            final phone = adminData['phoneNumber'] as String? ?? '';
            final exists = fetchedSupervisors.any(
              (s) => (s['phoneNumber'] as String? ?? '') == phone,
            );

            if (!exists) {
              fetchedSupervisors.add(adminData);
            }
          }
        }
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
          await _fetchSupervisors(forceRefresh: true);
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
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
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
                            isArabic
                                ? 'مندوب ميداني (Delegate)'
                                : 'Field Delegate',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white24,
                child: Icon(
                  Icons.person_pin_rounded,
                  color: Colors.white,
                  size: 28,
                ),
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
    final name = supervisorData['displayName'] as String? ?? 'مشرف الشركة';
    final phone = supervisorData['phoneNumber'] as String? ?? '';

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
                    'مشرف الشركة (الشركة المنتدبة)',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
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
}

