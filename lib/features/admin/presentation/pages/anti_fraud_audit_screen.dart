import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_create_penalty_page.dart';

/// شاشة رصد وتدقيق الأمان ومكافحة برامج الـ Fake Location وتزييف الموقع (Anti-Fraud & Mock Location Audit)
class AntiFraudAuditScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;
  final String initialTab;

  const AntiFraudAuditScreen({
    super.key,
    required this.delegate,
    this.showAppBar = false,
    this.initialTab = 'violations',
  });

  @override
  State<AntiFraudAuditScreen> createState() => _AntiFraudAuditScreenState();
}

class _AntiFraudAuditScreenState extends State<AntiFraudAuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _deviceSearchController = TextEditingController();
  String _searchQuery = '';
  String _deviceSearchQuery = '';
  String _timeFilter = 'all'; // all, today
  String _selectedBranchFilter = 'all'; // all, or specific detected branch name
  late String _currentTab; // violations, devices
  String _deviceStatusFilter = 'all'; // all, locked, unbound
  List<Map<String, dynamic>> _branchesList = [];
  Map<String, String> _companiesMap = {};
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _loadBranches();
    _loadCompanies();
  }

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      final list = snap.docs.map((d) {
        final data = d.data();
        final name = (data['branchName'] as String?) ??
            (data['name'] as String?) ??
            (data['title'] as String?) ??
            d.id;
        double? lat;
        double? lng;
        if (data['location'] is Map) {
          lat = (data['location']['latitude'] as num?)?.toDouble();
          lng = (data['location']['longitude'] as num?)?.toDouble();
        } else if (data['latitude'] != null && data['longitude'] != null) {
          lat = (data['latitude'] as num?)?.toDouble();
          lng = (data['longitude'] as num?)?.toDouble();
        }
        return {
          'id': d.id,
          'name': name,
          'latitude': lat,
          'longitude': lng,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _branchesList = list;
        });
      }
    } catch (_) {}
  }

  String _resolveBranchName(Map<String, dynamic> item) {
    final directBranch = (item['branchName'] as String?)?.trim() ?? '';
    if (directBranch.isNotEmpty && directBranch != 'غير محدد') {
      return directBranch;
    }

    final branchUid = (item['branchUID'] as String?)?.trim() ?? '';
    if (branchUid.isNotEmpty) {
      final match = _branchesList.firstWhere(
        (b) => b['id'] == branchUid,
        orElse: () => {'name': ''},
      );
      if ((match['name'] as String?)?.isNotEmpty == true) {
        return match['name'] as String;
      }
    }

    // Match closest branch from mock coordinates
    final lat = (item['latitude'] as num?)?.toDouble();
    final lng = (item['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null && _branchesList.isNotEmpty) {
      double minDistance = double.infinity;
      String bestName = '';
      String bestId = '';

      for (final b in _branchesList) {
        final bLat = b['latitude'] as double?;
        final bLng = b['longitude'] as double?;
        if (bLat != null && bLng != null) {
          final dist = Geolocator.distanceBetween(lat, lng, bLat, bLng);
          if (dist < minDistance) {
            minDistance = dist;
            bestName = b['name'] as String;
            bestId = b['id'] as String;
          }
        }
      }

      if (bestName.isNotEmpty) {
        final docId = item['docId']?.toString();
        if (docId != null && docId.isNotEmpty && item['_isUpdated'] != true) {
          item['_isUpdated'] = true;
          FirebaseFirestore.instance
              .collection('security_audit_logs')
              .doc(docId)
              .update({
                'branchName': bestName,
                'branchUID': bestId,
              })
              .catchError((_) {});
        }
        return bestName;
      }
    }

    return 'غير محدد';
  }

  Future<void> _loadCompanies() async {
    try {
      final snap = await FirebaseFirestore.instance.collectionGroup('companies').get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim() ??
            (data['companyName'] as String?)?.trim() ??
            '';
        if (name.isNotEmpty) {
          map[doc.id] = name;
        }
      }
      if (mounted) {
        setState(() {
          _companiesMap = map;
        });
      }
    } catch (_) {}
  }

  String _resolveCompanyName(Map<String, dynamic> item) {
    final compUid = (item['companyUID'] as String?)?.trim() ?? '';
    if (compUid.isNotEmpty && _companiesMap.containsKey(compUid)) {
      final officialName = _companiesMap[compUid]!;
      final currentName = (item['companyName'] as String?)?.trim() ?? '';
      if (currentName != officialName && item['_isCompUpdated'] != true) {
        item['_isCompUpdated'] = true;
        final docId = item['docId']?.toString();
        if (docId != null && docId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('security_audit_logs')
              .doc(docId)
              .update({'companyName': officialName})
              .catchError((_) {});
        }
      }
      return officialName;
    }
    return (item['companyName'] as String?)?.trim() ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _deviceSearchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _openLocationOnMap(double lat, double lng) async {
    final googleMapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(googleMapsUri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(googleMapsUri);
      } catch (_) {}
    }
  }

  Future<void> _exportToCSV(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لا توجد سجلات لتصديرها حالياً'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Helper function to escape CSV cell contents
      String escapeCsv(dynamic value) {
        if (value == null) return '""';
        final str = value.toString().replaceAll('"', '""');
        return '"$str"';
      }

      // UTF-8 BOM (\uFEFF) ensures Excel properly displays Arabic characters
      final buffer = StringBuffer();
      buffer.write('\uFEFF');

      // CSV Header Row
      buffer.writeln([
        'م',
        'اسم المندوب',
        'رقم الهاتف',
        'الجهاز المستخدم',
        'اسم الشركة',
        'الفرع المرصود',
        'تاريخ وتوقيت المحاولة',
        'الإحداثيات المرصودة (Lat, Lng)',
        'خط العرض (Latitude)',
        'خط الطول (Longitude)',
        'رابط خرائط جوجل (Google Maps)',
        'موقع اتصال الإنترنت الفعلي (ISP & Location)',
        'عنوان الـ IP',
        'نوع العملية',
        'حالة الرصد',
      ].map(escapeCsv).join(','));

      // CSV Data Rows
      for (int i = 0; i < logs.length; i++) {
        final data = logs[i];
        final index = (i + 1).toString();
        final delegateName = data['delegateName']?.toString() ?? 'غير محدد';
        final delegatePhone = data['delegatePhone']?.toString() ?? '';
        final deviceModel = data['deviceModel']?.toString() ?? 'غير معروف';
        final companyName = _resolveCompanyName(data);
        final branchName = _resolveBranchName(data);

        // Attempt Timestamp
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final realTs = data['realTimestamp'] != null
            ? DateTime.tryParse(data['realTimestamp'].toString())
            : (data['createdAt'] != null
                ? DateTime.tryParse(data['createdAt'].toString())
                : null);
        final effectiveDate = ts ?? realTs;
        final dateStr = effectiveDate != null
            ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveDate)
            : 'غير محدد';

        // Coordinates & Map Link
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final coordsStr = (lat != null && lng != null)
            ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
            : '';
        final latStr = lat != null ? lat.toStringAsFixed(6) : '';
        final lngStr = lng != null ? lng.toStringAsFixed(6) : '';
        final mapUrl = (lat != null && lng != null)
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            : '';

        final networkLocation = data['networkLocation']?.toString() ?? '';
        final ipCity = data['ipCity']?.toString() ?? '';
        final ipIsp = data['ipIsp']?.toString() ?? '';
        final fullNetLoc = networkLocation.isNotEmpty
            ? networkLocation
            : (ipCity.isNotEmpty ? '$ipCity ($ipIsp)' : '');
        final ipAddress = data['ipAddress']?.toString() ?? '';
        final actionType = data['actionType']?.toString() ?? 'تسجيل حضور/انصراف';
        const status = 'محظورة (Fake GPS)';

        buffer.writeln([
          index,
          delegateName,
          delegatePhone,
          deviceModel,
          companyName,
          branchName,
          dateStr,
          coordsStr,
          latStr,
          lngStr,
          mapUrl,
          fullNetLoc,
          ipAddress,
          actionType,
          status,
        ].map(escapeCsv).join(','));
      }

      final directory = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyy_MM_dd_HHmm').format(DateTime.now());
      final file = File('${directory.path}/تقرير_محاولات_تزييف_الموقع_$nowStr.csv');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير سجلات كشف التزييف والأمان (Fake GPS Audit Report) - $nowStr',
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تصدير الملف: $e'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _resetDelegateDevice(
    BuildContext context,
    String delegateUid,
    String delegateName, {
    String? orgId,
    String? compId,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    if (delegateUid.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحديد معرف المندوب'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.phonelink_erase_rounded, color: colorScheme.primary, size: 28),
            const SizedBox(width: 8),
            const Text('فك ربط الجهاز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من فك ربط جهاز المندوب "$delegateName"؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سيتمكن المندوب من ربط جهازه الجديد تلقائياً بمجرد تسجيل دخوله القادم.',
                      style: TextStyle(fontSize: 12, height: 1.3),
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد فك الربط'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DeviceBindingService.resetDelegateDeviceBinding(
          delegateUid: delegateUid,
          organizationUID: orgId,
          companyUID: compId,
          adminUid: widget.delegate.uid,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم فك ربط جهاز المندوب "$delegateName" بنجاح. يستطيع الآن الدخول من هاتفه الجديد.'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء فك الربط: $e'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteAuditLog(BuildContext context, String docId, String delegateName) async {
    final colorScheme = Theme.of(context).colorScheme;
    if (docId.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحديد معرف السجل الأمني'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: colorScheme.error, size: 28),
            const SizedBox(width: 8),
            const Text('حذف السجل الأمني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف سجل المخالفة الأمني للمندوب "$delegateName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('security_audit_logs').doc(docId).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم حذف السجل الأمني بنجاح'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحذف: $e'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _createPenaltyForDelegate(BuildContext context, Map<String, dynamic> data) {
    final companyUid = data['companyUID']?.toString() ?? '';
    final companyName = _resolveCompanyName(data);
    final delegateUid = data['delegateUid']?.toString() ?? '';
    final delegateName = data['delegateName']?.toString() ?? '';
    final resolvedBranchName = _resolveBranchName(data);
    String resolvedBranchUid = data['branchUID']?.toString() ?? '';
    if (resolvedBranchUid.isEmpty && resolvedBranchName != 'غير محدد') {
      final match = _branchesList.firstWhere(
        (b) => b['name'] == resolvedBranchName,
        orElse: () => {'id': ''},
      );
      resolvedBranchUid = (match['id'] as String?) ?? '';
    }
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير محدد';
    final actionType = data['actionType']?.toString() ?? 'تسجيل الحضور/الانصراف';

    final networkLocation = data['networkLocation']?.toString() ?? '';

    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final realTs = data['realTimestamp'] != null
        ? DateTime.tryParse(data['realTimestamp'].toString())
        : (data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null);
    final effectiveRealDate = ts ?? realTs;
    final realDateStr = effectiveRealDate != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveRealDate)
        : '';

    final incidentBuffer = StringBuffer();
    incidentBuffer.write('تم رصد محاولة تزييف موقع جغرافي (Fake GPS) بواسطة جهاز ($deviceModel)');
    if (actionType.isNotEmpty) {
      incidentBuffer.write(' أثناء $actionType');
    }
    if (resolvedBranchName.isNotEmpty && resolvedBranchName != 'غير محدد') {
      incidentBuffer.write(' بفرع $resolvedBranchName');
    }
    if (realDateStr.isNotEmpty) {
      incidentBuffer.write(' بتاريخ $realDateStr');
    }
    if (networkLocation.isNotEmpty) {
      incidentBuffer.write('، مع رصد اتصاله بالإنترنت من موقع ($networkLocation)');
    }
    incidentBuffer.write('، وتم اعتراض الإحداثيات وتوثيق الواقعة في سجل الأمان.');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: AdminCreatePenaltyPage(
            adminDelegate: widget.delegate,
            initialCompanyId: companyUid.isNotEmpty ? companyUid : null,
            initialCompanyName: companyName.isNotEmpty ? companyName : null,
            initialDelegateId: delegateUid.isNotEmpty ? delegateUid : null,
            initialDelegateName: delegateName.isNotEmpty ? delegateName : null,
            initialBranchId: resolvedBranchUid.isNotEmpty ? resolvedBranchUid : null,
            initialBranchName: resolvedBranchName != 'غير محدد' ? resolvedBranchName : null,
            initialViolationId: 28, // بند تزييف موقع الحضور والانصراف (Fake GPS) - 200 جنيه
            initialIncidentDetails: incidentBuffer.toString(),
          ),
        ),
      ),
    );
  }

  bool _matchesTimeFilter(DateTime? timestamp) {
    if (timestamp == null) return true;
    final now = DateTime.now();

    switch (_timeFilter) {
      case 'today':
        return timestamp.year == now.year &&
            timestamp.month == now.month &&
            timestamp.day == now.day;
      case 'all':
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final body = StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('security_audit_logs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final allLogs = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'docId': d.id,
            ...data,
          };
        }).toList();

        // Calculate summary metrics
        final now = DateTime.now();
        int todayAttempts = 0;
        final Set<String> uniqueDelegates = {};
        final Set<String> uniqueDevices = {};

        // Extract unique detected branch names from allLogs
        final Set<String> detectedBranchesSet = {};
        for (final item in allLogs) {
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          if (ts != null &&
              ts.year == now.year &&
              ts.month == now.month &&
              ts.day == now.day) {
            todayAttempts++;
          }
          final uid = item['delegateUid']?.toString() ?? '';
          if (uid.isNotEmpty) uniqueDelegates.add(uid);

          final dev = item['deviceModel']?.toString() ?? '';
          if (dev.isNotEmpty && dev != 'Unknown Device') uniqueDevices.add(dev);

          final bName = _resolveBranchName(item).trim();
          if (bName.isNotEmpty && bName != 'غير محدد') {
            detectedBranchesSet.add(bName);
          }
        }
        final detectedBranches = detectedBranchesSet.toList()..sort();

        // Apply filters
        final filteredLogs = allLogs.where((item) {
          // 1. Time filter (All or Today)
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          if (!_matchesTimeFilter(ts)) return false;

          // 2. Detected Branch filter
          if (_selectedBranchFilter != 'all') {
            final itemBranch = _resolveBranchName(item).trim();
            if (itemBranch != _selectedBranchFilter) {
              return false;
            }
          }

          // 3. Search query filter
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final name = (item['delegateName'] ?? '').toString().toLowerCase();
            final phone = (item['delegatePhone'] ?? '').toString().toLowerCase();
            final comp = _resolveCompanyName(item).toLowerCase();
            final branch = _resolveBranchName(item).toLowerCase();
            final dev = (item['deviceModel'] ?? '').toString().toLowerCase();

            if (!name.contains(q) &&
                !phone.contains(q) &&
                !comp.contains(q) &&
                !branch.contains(q) &&
                !dev.contains(q)) {
              return false;
            }
          }

          return true;
        }).toList();

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top Tab Switcher (Violations vs Device Binding)
                SliverToBoxAdapter(
                  child: _buildTabSwitcher(colorScheme, isArabic),
                ),

                if (_currentTab == 'devices') ...[
                  SliverToBoxAdapter(
                    child: _buildDeviceBindingSection(colorScheme, isArabic),
                  ),
                ] else ...[
                  // 1. Header Metrics Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: _buildHeaderMetrics(
                        colorScheme: colorScheme,
                        totalAttempts: allLogs.length,
                        todayAttempts: todayAttempts,
                        uniqueDelegatesCount: uniqueDelegates.length,
                        uniqueDevicesCount: uniqueDevices.length,
                        isArabic: isArabic,
                      ),
                    ),
                  ),

              // 2. Branch Dropdown, Search & Time Filters
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Branch Filter Dropdown (الفروع المرصودة فقط)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _selectedBranchFilter != 'all'
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: _selectedBranchFilter != 'all' ? 1.5 : 1.0,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: (detectedBranches.contains(_selectedBranchFilter) || _selectedBranchFilter == 'all')
                                ? _selectedBranchFilter
                                : 'all',
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(14),
                            icon: Icon(
                              Icons.arrow_drop_down_rounded,
                              color: _selectedBranchFilter != 'all'
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: 'all',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.storefront_rounded,
                                      size: 18,
                                      color: _selectedBranchFilter == 'all'
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isArabic
                                            ? 'جميع الفروع المرصودة (${allLogs.length})'
                                            : 'All Detected Branches (${allLogs.length})',
                                        style: TextStyle(
                                          fontWeight: _selectedBranchFilter == 'all'
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...detectedBranches.map((branchName) {
                                final branchLogsCount = allLogs
                                    .where((l) => _resolveBranchName(l).trim() == branchName)
                                    .length;
                                return DropdownMenuItem<String>(
                                  value: branchName,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$branchName ($branchLogsCount)',
                                          style: TextStyle(
                                            fontWeight: _selectedBranchFilter == branchName
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                            fontSize: 13,
                                            color: _selectedBranchFilter == branchName
                                                ? colorScheme.primary
                                                : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedBranchFilter = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Search bar with Dedicated Search Action Button
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (val) {
                                setState(() => _searchQuery = val.trim());
                              },
                              decoration: InputDecoration(
                                hintText: isArabic
                                    ? 'بحث بالمندوب، الشركة، الفرع، أو نوع الجهاز...'
                                    : 'Search delegate, company, branch, or device...',
                                prefixIcon: IconButton(
                                  icon: const Icon(Icons.search_rounded),
                                  tooltip: isArabic ? 'تنفيذ البحث' : 'Search',
                                  onPressed: () {
                                    setState(() => _searchQuery = _searchController.text.trim());
                                    FocusScope.of(context).unfocus();
                                  },
                                ),
                                suffixIcon: _searchController.text.isNotEmpty || _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        tooltip: isArabic ? 'مسح البحث' : 'Clear search',
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () {
                              setState(() => _searchQuery = _searchController.text.trim());
                              FocusScope.of(context).unfocus();
                            },
                            icon: const Icon(Icons.search_rounded, size: 20),
                            tooltip: isArabic ? 'بحث' : 'Search',
                          ),
                        ],
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.filter_alt_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isArabic
                                      ? 'نتائج البحث عن: "$_searchQuery" (${filteredLogs.length} سجل)'
                                      : 'Results for "$_searchQuery" (${filteredLogs.length} items)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isArabic ? 'إلغاء' : 'Clear',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(Icons.close_rounded, size: 14, color: colorScheme.error),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Time Filters (Only: All, Today)
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterChip(
                              'all',
                              isArabic ? 'الكل (${allLogs.length})' : 'All (${allLogs.length})',
                              colorScheme,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFilterChip(
                              'today',
                              isArabic ? 'اليوم ($todayAttempts)' : 'Today ($todayAttempts)',
                              colorScheme,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Results Count & Export Excel Button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isArabic
                              ? 'سجلات محاولات التزييف المكتشفة (${filteredLogs.length})'
                              : 'Detected Violations (${filteredLogs.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (filteredLogs.isNotEmpty)
                        IconButton.filledTonal(
                          onPressed: _isExporting ? null : () => _exportToCSV(filteredLogs),
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_download_rounded, size: 20),
                          tooltip: isArabic ? 'تصدير إكسيل' : 'Export Excel',
                        ),
                    ],
                  ),
                ),
              ),

              // 4. List of Violation Cards
              if (filteredLogs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 64,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isArabic ? 'سجل الأمان نظيف تماماً' : 'Security Log Clean',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isArabic
                                ? 'لم يتم تسجيل أي محاولات لاستخدام برامج Fake Location مطابقة للبحث المحدد.'
                                : 'No Fake Location / mock GPS attempts match your current filter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredLogs[index];
                        return _buildViolationCard(
                          context: context,
                          colorScheme: colorScheme,
                          data: item,
                          isArabic: isArabic,
                        );
                      },
                      childCount: filteredLogs.length,
                    ),
                  ),
                ),
                ],
            ],
          ),
        );
      },
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: colorScheme.surfaceContainer,
          elevation: 0,
          scrolledUnderElevation: 2.0,
          shape: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          title: Text(
            isArabic ? 'سجل الأمان وكشف التزييف' : 'Security & Anti-Fraud Logs',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: body,
      );
    }

    return body;
  }

  Widget _buildFilterChip(String key, String label, ColorScheme colorScheme) {
    final isSelected = _timeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _timeFilter = key);
        }
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
      ),
    );
  }

  Widget _buildHeaderMetrics({
    required ColorScheme colorScheme,
    required int totalAttempts,
    required int todayAttempts,
    required int uniqueDelegatesCount,
    required int uniqueDevicesCount,
    required bool isArabic,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.security_rounded,
                  color: colorScheme.onErrorContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'منظومة كشف التزييف والأمان' : 'Anti-Fraud & Security Monitor',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'رصد محاولات الـ Fake GPS وبصمات الأجهزة المخالفة'
                          : 'Real-time mock GPS & device fingerprint tracking',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
          const SizedBox(height: 12),

          // Stat row
          Row(
            children: [
              _buildStatBox(
                colorScheme: colorScheme,
                title: isArabic ? 'إجمالي المحاولات' : 'Total Attempts',
                value: '$totalAttempts',
                icon: Icons.gavel_rounded,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                colorScheme: colorScheme,
                title: isArabic ? 'اليوم' : 'Today',
                value: '$todayAttempts',
                icon: Icons.today_rounded,
                isHighlight: todayAttempts > 0,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                colorScheme: colorScheme,
                title: isArabic ? 'المناديب' : 'Delegates',
                value: '$uniqueDelegatesCount',
                icon: Icons.people_outline_rounded,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                colorScheme: colorScheme,
                title: isArabic ? 'الأجهزة' : 'Devices',
                value: '$uniqueDevicesCount',
                icon: Icons.phone_android_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required ColorScheme colorScheme,
    required String title,
    required String value,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isHighlight
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlight
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: isHighlight ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: isHighlight
                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViolationCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required bool isArabic,
  }) {
    final docId = (data['docId'] != null && data['docId'].toString().trim().isNotEmpty)
        ? data['docId'].toString().trim()
        : (data['id']?.toString().trim() ?? '');
    final delegateName = data['delegateName']?.toString() ?? 'مندوب غير محدد';
    final delegatePhone = data['delegatePhone']?.toString() ?? '';
    final companyName = _resolveCompanyName(data);
    final branchName = _resolveBranchName(data);
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير معروف';
    final actionType = data['actionType']?.toString() ?? '';
    final networkLocation = data['networkLocation']?.toString() ?? '';
    final ipAddress = data['ipAddress']?.toString() ?? '';
    final ipCity = data['ipCity']?.toString() ?? '';
    final ipIsp = data['ipIsp']?.toString() ?? '';

    // Coordinates
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    // Actual attempt timestamp
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final realTs = data['realTimestamp'] != null
        ? DateTime.tryParse(data['realTimestamp'].toString())
        : (data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null);
    final effectiveRealDate = ts ?? realTs;
    final realDateStr = effectiveRealDate != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveRealDate)
        : 'غير محدد';

    final isApple = deviceModel.toLowerCase().contains('iphone') ||
        deviceModel.toLowerCase().contains('ipad') ||
        deviceModel.toLowerCase().contains('ios');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Delegate Name & Avatar
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  radius: 20,
                  child: const Icon(Icons.person_off_rounded, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delegateName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (delegatePhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          delegatePhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 10),

            // Device Info Chip (Device Fingerprint)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(
                    isApple ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الجهاز المستخدم: $deviceModel',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Branch & Company Tags Row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Branch Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 15, color: colorScheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        'الفرع: $branchName',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                // Company Tag
                if (companyName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_rounded, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          'الشركة: $companyName',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Incident Details Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  // Attempt Timestamp Row
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'توقيت المحاولة: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          realDateStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'محظورة',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lat != null && lng != null) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _openLocationOnMap(lat, lng),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                'الإحداثيات المرصودة: ',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: colorScheme.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.map_rounded, size: 12, color: colorScheme.onPrimaryContainer),
                                    const SizedBox(width: 3),
                                    Text(
                                      'عرض بالخريطة',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (networkLocation.isNotEmpty || ipAddress.isNotEmpty || ipCity.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.wifi_tethering_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'اتصال الإنترنت الفعلي: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            networkLocation.isNotEmpty
                                ? networkLocation
                                : (ipCity.isNotEmpty ? '$ipCity ($ipIsp)' : 'IP: $ipAddress'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (actionType.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.event_note_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'نوع العملية: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          actionType,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons Bar (Responsive & Icon-First)
            Row(
              children: [
                if (lat != null && lng != null)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.map_rounded, size: 18),
                    tooltip: 'عرض الموقع على الخريطة',
                    onPressed: () => _openLocationOnMap(lat, lng),
                  ),
                if (delegatePhone.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    tooltip: 'اتصال هاتفي',
                    onPressed: () => _makePhoneCall(delegatePhone),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    tooltip: 'مراسلة عبر واتساب',
                    onPressed: () => _openWhatsApp(delegatePhone),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 18),
                  tooltip: 'تطبيق مخالفة وغرامة للمندوب',
                  onPressed: () => _createPenaltyForDelegate(context, data),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                  tooltip: 'فك ربط جهاز المندوب',
                  onPressed: () => _resetDelegateDevice(
                    context,
                    data['delegateUid']?.toString() ?? '',
                    delegateName,
                    orgId: data['organizationUID']?.toString(),
                    compId: data['companyUID']?.toString(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colorScheme.outline, size: 19),
                  tooltip: 'حذف السجل',
                  onPressed: () => _deleteAuditLog(context, docId, delegateName),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSwitcher(ColorScheme colorScheme, bool isArabic) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _currentTab = 'violations'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _currentTab == 'violations'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.security_rounded,
                      size: 18,
                      color: _currentTab == 'violations'
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isArabic ? 'سجلات كشف التزييف' : 'Fraud Violations',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: _currentTab == 'violations'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _currentTab = 'devices'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _currentTab == 'devices'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phonelink_lock_rounded,
                      size: 18,
                      color: _currentTab == 'devices'
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isArabic ? 'ربط أجهزة المناديب' : 'Device Binding',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: _currentTab == 'devices'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceBindingSection(ColorScheme colorScheme, bool isArabic) {
    Query query = FirebaseFirestore.instance.collectionGroup('delegates');
    if (widget.delegate.organizationUID.isNotEmpty &&
        widget.delegate.role != UserRole.technicalSupport &&
        widget.delegate.role != UserRole.superAdmin) {
      query = query.where('organizationUID', isEqualTo: widget.delegate.organizationUID);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final delegatesList = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'docId': d.id,
            'docPath': d.reference.path,
            ...data,
          };
        }).where((d) {
          // Exclude suspended / non-delegates if necessary
          final role = d['role']?.toString().toLowerCase() ?? '';
          return role.isEmpty || role == 'delegate';
        }).toList();

        int lockedCount = 0;
        int unboundCount = 0;
        for (final item in delegatesList) {
          final boundId = item['boundDeviceId']?.toString().trim() ?? '';
          if (boundId.isNotEmpty) {
            lockedCount++;
          } else {
            unboundCount++;
          }
        }

        // Apply filters
        final filteredDelegates = delegatesList.where((d) {
          final boundId = d['boundDeviceId']?.toString().trim() ?? '';
          if (_deviceStatusFilter == 'locked' && boundId.isEmpty) return false;
          if (_deviceStatusFilter == 'unbound' && boundId.isNotEmpty) return false;

          if (_deviceSearchQuery.isNotEmpty) {
            final q = _deviceSearchQuery.toLowerCase();
            final name = (d['fullName'] ?? d['firstName'] ?? '').toString().toLowerCase();
            final phone = (d['phoneNumber'] ?? '').toString().toLowerCase();
            final comp = (d['companyName'] ?? '').toString().toLowerCase();
            final dev = (d['boundDeviceModel'] ?? '').toString().toLowerCase();

            if (!name.contains(q) && !phone.contains(q) && !comp.contains(q) && !dev.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Device Binding Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.phonelink_lock_rounded, color: colorScheme.onPrimaryContainer, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'منظومة قفل وربط أجهزة المناديب',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'حساب كل مندوب مقترن بهاتفه المعتمد لمنع تبادل الحسابات',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _buildStatBox(
                          colorScheme: colorScheme,
                          title: 'إجمالي المناديب',
                          value: '${delegatesList.length}',
                          icon: Icons.people_outline_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildStatBox(
                          colorScheme: colorScheme,
                          title: 'أجهزة مقترنة',
                          value: '$lockedCount',
                          icon: Icons.lock_rounded,
                          isHighlight: lockedCount > 0,
                        ),
                        const SizedBox(width: 8),
                        _buildStatBox(
                          colorScheme: colorScheme,
                          title: 'متاح للربط',
                          value: '$unboundCount',
                          icon: Icons.lock_open_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 2. Search Bar with Dedicated Search Action Button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deviceSearchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (val) {
                        setState(() => _deviceSearchQuery = val.trim());
                      },
                      decoration: InputDecoration(
                        hintText: isArabic
                            ? 'بحث بالمندوب، الهاتف، الشركة، أو اسم الجهاز...'
                            : 'Search delegate, phone, company, or device...',
                        prefixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          tooltip: isArabic ? 'تنفيذ البحث' : 'Search',
                          onPressed: () {
                            setState(() => _deviceSearchQuery = _deviceSearchController.text.trim());
                            FocusScope.of(context).unfocus();
                          },
                        ),
                        suffixIcon: _deviceSearchController.text.isNotEmpty || _deviceSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                tooltip: isArabic ? 'مسح البحث' : 'Clear search',
                                onPressed: () {
                                  _deviceSearchController.clear();
                                  setState(() => _deviceSearchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      setState(() => _deviceSearchQuery = _deviceSearchController.text.trim());
                      FocusScope.of(context).unfocus();
                    },
                    icon: const Icon(Icons.search_rounded, size: 20),
                    tooltip: isArabic ? 'بحث' : 'Search',
                  ),
                ],
              ),
              if (_deviceSearchQuery.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isArabic
                              ? 'نتائج البحث عن: "$_deviceSearchQuery" (${filteredDelegates.length} مندوب)'
                              : 'Results for "$_deviceSearchQuery" (${filteredDelegates.length} delegates)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _deviceSearchController.clear();
                          setState(() => _deviceSearchQuery = '');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isArabic ? 'إلغاء' : 'Clear',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.close_rounded, size: 14, color: colorScheme.error),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // 3. Status Filters Chips
              Row(
                children: [
                  Expanded(
                    child: _buildDeviceFilterChip('all', 'الكل (${delegatesList.length})', colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDeviceFilterChip('locked', 'المقترنة ($lockedCount)', colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDeviceFilterChip('unbound', 'المتاحة ($unboundCount)', colorScheme),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 4. Delegates List
              Text(
                'قائمة المناديب وحالة الأجهزة (${filteredDelegates.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 8),

              if (filteredDelegates.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.person_search_rounded, size: 48, color: colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'لا يوجد مناديب مطابقين للبحث',
                          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredDelegates.length,
                  itemBuilder: (context, index) {
                    final item = filteredDelegates[index];
                    return _buildDelegateDeviceCard(context, colorScheme, item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceFilterChip(String key, String label, ColorScheme colorScheme) {
    final isSelected = _deviceStatusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _deviceStatusFilter = key);
        }
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
      ),
    );
  }

  Widget _buildDelegateDeviceCard(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, dynamic> delegateData,
  ) {
    final name = (delegateData['fullName'] ?? delegateData['firstName'] ?? 'مندوب').toString();
    final phone = (delegateData['phoneNumber'] ?? '').toString();
    final company = (delegateData['companyName'] ?? '').toString();
    final boundDeviceModel = (delegateData['boundDeviceModel'] as String?)?.trim() ?? '';
    final boundDeviceId = (delegateData['boundDeviceId'] as String?)?.trim() ?? '';
    final isLocked = boundDeviceId.isNotEmpty;
    final delegateUid = delegateData['docId']?.toString() ?? delegateData['uid']?.toString() ?? '';
    final orgId = delegateData['organizationUID']?.toString();
    final compId = delegateData['companyUID']?.toString();

    DateTime? boundAt;
    if (delegateData['deviceBoundAt'] is Timestamp) {
      boundAt = (delegateData['deviceBoundAt'] as Timestamp).toDate();
    } else if (delegateData['deviceBoundAt'] != null) {
      boundAt = DateTime.tryParse(delegateData['deviceBoundAt'].toString());
    }

    final boundDateStr = boundAt != null ? DateFormat('yyyy-MM-dd hh:mm a').format(boundAt) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isLocked ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                  foregroundColor: isLocked ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  radius: 18,
                  child: Icon(
                    isLocked ? Icons.phonelink_lock_rounded : Icons.phonelink_setup_rounded,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          phone,
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (company.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      company,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            if (isLocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_android_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الجهاز المقترن: $boundDeviceModel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (boundDateStr.isNotEmpty)
                            Text(
                              'تاريخ الاعتماد: $boundDateStr',
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _resetDelegateDevice(
                        context,
                        delegateUid,
                        name,
                        orgId: orgId,
                        compId: compId,
                      ),
                      icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                      tooltip: 'فك ربط الجهاز',
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_open_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'متاح للربط: سيتم اعتماد أول هاتف يسجل منه المندوب تلقائياً.',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
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
}
