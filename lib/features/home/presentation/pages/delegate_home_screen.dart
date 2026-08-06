import 'package:flutter/material.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';


class DelegateHomeScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateHomeScreen({super.key, required this.delegate});

  @override
  State<DelegateHomeScreen> createState() => _DelegateHomeScreenState();
}

class _DelegateHomeScreenState extends State<DelegateHomeScreen> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _supervisorsData = [];
  bool _loadingSupervisor = false;
  String? _supervisorError;

  int _photosToday = 0;
  int _pendingTasks = 0;
  bool _isCheckedIn = false;
  bool _loadingStats = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchSupervisors();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    final uid = widget.delegate.uid;
    final orgId = widget.delegate.organizationUID;
    
    if (uid.isEmpty || orgId.isEmpty) return;

    if (mounted) {
      setState(() {
        _loadingStats = true;
      });
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    
    int photosToday = 0;
    int pendingTasks = 0;
    bool checkedIn = false;

    try {
      // Fetch today's check-in status
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('delegateId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
          
      if (attendanceSnapshot.docs.isNotEmpty) {
        final data = attendanceSnapshot.docs.first.data();
        final ts = data['timestamp'] as Timestamp?;
        if (ts != null) {
          final date = ts.toDate();
          if (date.isAfter(startOfDay)) {
            checkedIn = data['type'] == 'check_in';
          }
        }
      }

      // Fetch pending tasks
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .collection('tasks')
          .where('assignedTo', isEqualTo: uid)
          .where('status', isNotEqualTo: 'completed')
          .get();
      pendingTasks = tasksSnapshot.docs.length;

      // Fetch photos today (we pull all and filter locally to avoid needing index)
      final photosSnapshot = await FirebaseFirestore.instance
          .collectionGroup('captured_photos')
          .where('delegateUID', isEqualTo: uid)
          .get();
          
      for (final doc in photosSnapshot.docs) {
        final ts = doc.data()['capturedAt'] as Timestamp?;
        if (ts != null && ts.toDate().isAfter(startOfDay)) {
          photosToday++;
        }
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
    }

    if (mounted) {
      setState(() {
        _photosToday = photosToday;
        _pendingTasks = pendingTasks;
        _isCheckedIn = checkedIn;
        _loadingStats = false;
      });
    }
  }

  Future<void> _fetchSupervisors() async {
    final orgId = widget.delegate.organizationUID;
    final compId = widget.delegate.companyUID;

    if (orgId.isEmpty || compId.isEmpty) return;

    setState(() {
      _loadingSupervisor = true;
      _supervisorError = null;
      _supervisorsData = [];
    });

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
          final companyPhone = compData['phone'] as String? ?? compData['phoneNumber'] as String? ?? '';
          final companyEmail = compData['email'] as String? ?? compData['emailAddress'] as String? ?? '';
          final companySupervisorName = compData['supervisorName'] as String? ??
              compData['contactName'] as String? ??
              compData['adminName'] as String? ??
              compData['managerName'] as String? ??
              compData['displayName'] as String? ??
              '';

          if (companyPhone.isNotEmpty || companyEmail.isNotEmpty || companySupervisorName.isNotEmpty) {
            fetchedSupervisors.add({
              'displayName': companySupervisorName.isNotEmpty ? companySupervisorName : 'مشرف الشركة',
              'phoneNumber': companyPhone,
              'email': companyEmail,
              'isCompanyDoc': true, // To distinguish origin if needed
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
            
            // Avoid adding duplicates (e.g. if the company doc had the same info)
            final phone = adminData['phoneNumber'] as String? ?? '';
            final exists = fetchedSupervisors.any((s) => (s['phoneNumber'] as String? ?? '') == phone);
            
            if (!exists) {
              fetchedSupervisors.add(adminData);
            }
          }
        }
      }

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
      await launchUrl(uri);
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
          await _fetchSupervisors();
          await _fetchStats();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatsDashboard(context),
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

  Widget _buildStatsDashboard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loadingStats) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('organizations')
                    .doc(widget.delegate.organizationUID)
                    .collection('tasks')
                    .where('assignedTo', isEqualTo: widget.delegate.uid)
                    .where('status', isNotEqualTo: 'completed')
                    .snapshots(),
                builder: (context, snapshot) {
                  // Fallback to the initially loaded `_pendingTasks` if still loading
                  final pendingCount = snapshot.hasData ? snapshot.data!.docs.length : _pendingTasks;
                  return _buildStatCard(
                    context,
                    title: 'مهام قيد الانتظار',
                    value: '$pendingCount',
                    icon: Icons.task_rounded,
                    color: colorScheme.error,
                    containerColor: colorScheme.errorContainer,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                title: 'صور اليوم',
                value: '$_photosToday',
                icon: Icons.photo_camera_rounded,
                color: colorScheme.primary,
                containerColor: colorScheme.primaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildStatCard(
          context,
          title: 'حالة الحضور',
          value: _isCheckedIn ? 'حاضر (تم التسجيل)' : 'لم يتم التسجيل بعد',
          icon: _isCheckedIn ? Icons.how_to_reg_rounded : Icons.person_off_rounded,
          color: _isCheckedIn ? Colors.green.shade700 : colorScheme.outline,
          containerColor: _isCheckedIn ? Colors.green.shade50 : colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color containerColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: containerColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSupervisorsList(BuildContext context) {
    if (_loadingSupervisor) {
      return [
        const Center(child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ))
      ];
    }
    
    if (_supervisorsData.isEmpty) {
      return [_buildEmptySupervisorCard(context)];
    }
    
    return _supervisorsData.map((supervisor) => _buildSupervisorCard(context, supervisor)).toList();
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
              backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.2),
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
                      color: _supervisorError != null ? colorScheme.error : colorScheme.onSurfaceVariant,
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

  Widget _buildSupervisorCard(BuildContext context, Map<String, dynamic> supervisorData) {
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
                  backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.2),
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
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic ? 'تصوير العروض الميدانية' : 'Field Offer Photos',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArabic
                        ? 'التقاط وإرسال صور العروض والبرندات المعتمدة'
                        : 'Capture & send approved offer photos',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: () {
                context.push('/photo-permissions/delegate', extra: widget.delegate);
              },
              icon: const Icon(Icons.camera_rounded, size: 16),
              label: Text(isArabic ? 'الكاميرا' : 'Camera'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
