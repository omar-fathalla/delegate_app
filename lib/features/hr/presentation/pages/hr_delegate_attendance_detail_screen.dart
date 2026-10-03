import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Model representing a single attendance session for a delegate
class DelegateAttendanceSession {
  final String id;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final String branchName;
  final String? deviceInfo;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final bool? isInsideGeofence;
  final String? checkOutDeviceInfo;
  final double? checkOutLatitude;
  final double? checkOutLongitude;
  final String? checkOutDocId;
  final bool isManuallyAdjusted;
  final String? lastAdjustedBy;
  final DateTime? lastAdjustedAt;
  final String? adjustmentReason;
  final bool isAutoCheckOut;
  final String? autoCheckOutReason;

  const DelegateAttendanceSession({
    required this.id,
    required this.checkInTime,
    this.checkOutTime,
    required this.branchName,
    this.deviceInfo,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.isInsideGeofence,
    this.checkOutDeviceInfo,
    this.checkOutLatitude,
    this.checkOutLongitude,
    this.checkOutDocId,
    this.isManuallyAdjusted = false,
    this.lastAdjustedBy,
    this.lastAdjustedAt,
    this.adjustmentReason,
    this.isAutoCheckOut = false,
    this.autoCheckOutReason,
  });

  /// Duration worked in this session (if check-out exists)
  Duration? get duration {
    if (checkOutTime == null) return null;
    return checkOutTime!.difference(checkInTime);
  }

  /// Whether the session is currently ongoing (today without checkout and within 9 hours)
  bool get isOngoing {
    if (checkOutTime != null || isAutoCheckOut) return false;
    final now = DateTime.now();
    return checkInTime.year == now.year &&
        checkInTime.month == now.month &&
        checkInTime.day == now.day &&
        now.difference(checkInTime) < const Duration(hours: 9);
  }

  /// Formatted duration string e.g. "8 س و 15 د"
  String get formattedDuration {
    final d = duration;
    if (d == null) {
      return isOngoing ? 'قيد العمل الآن' : 'غير مسجل';
    }
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return '$hours س و $minutes د';
    } else if (hours > 0) {
      return '$hours ساعة';
    } else {
      return '$minutes دقيقة';
    }
  }
}

/// Comprehensive HR Delegate Attendance Detail Screen
/// Displays full monthly check-in/check-out history, visited branches,
/// monthly analytics KPIs, month-by-month navigation, and export to CSV.
class HRDelegateAttendanceDetailScreen extends StatefulWidget {
  final Delegate delegate;
  final DateTime? initialMonth;
  final Map<String, Branch>? branchesByName;
  final Delegate? hrDelegate;

  const HRDelegateAttendanceDetailScreen({
    super.key,
    required this.delegate,
    this.initialMonth,
    this.branchesByName,
    this.hrDelegate,
  });

  @override
  State<HRDelegateAttendanceDetailScreen> createState() =>
      _HRDelegateAttendanceDetailScreenState();
}

class _HRDelegateAttendanceDetailScreenState
    extends State<HRDelegateAttendanceDetailScreen> {
  late DateTime _selectedMonth;
  bool _isLoading = true;
  String? _errorMessage;

  List<DelegateAttendanceSession> _allSessions = [];
  Map<String, Branch> _branchesByName = {};
  String _selectedBranchFilter = 'all';
  String _selectedStatusFilter = 'all'; // 'all', 'completed', 'incomplete'

  @override
  void initState() {
    super.initState();
    final init = widget.initialMonth ?? DateTime.now();
    _selectedMonth = DateTime(init.year, init.month, 1);
    if (widget.branchesByName != null) {
      _branchesByName = Map.from(widget.branchesByName!);
    }
    _loadBranchesAndAttendance();
  }

  Future<void> _loadBranchesAndAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load branches if not provided
      if (_branchesByName.isEmpty) {
        final branchesSnap =
            await FirebaseFirestore.instance.collection('branches').get();
        final Map<String, Branch> bMap = {};
        for (final doc in branchesSnap.docs) {
          final b = BranchModel.fromFirestore(doc);
          final name = b.branchName.trim();
          if (name.isNotEmpty) {
            bMap[name.toLowerCase()] = b;
          }
          bMap[doc.id.toLowerCase().trim()] = b;
        }
        _branchesByName = bMap;
      }

      // 2. Fetch all attendance logs for this delegate across all history
      await _fetchDelegateLogs();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء تحميل سجل الحضور: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDelegateLogs() async {
    final Set<String> identifiers = {widget.delegate.uid};
    if (widget.delegate.nationalityID.trim().isNotEmpty) {
      identifiers.add(widget.delegate.nationalityID.trim());
    }
    final rawPhone = widget.delegate.phoneNumber.trim();
    if (rawPhone.isNotEmpty) {
      identifiers.add(rawPhone);
      final clean = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.isNotEmpty) identifiers.add(clean);
    }

    final queryList = identifiers.take(30).toList();

    // Query logs where delegateId matches
    final snapDelegateId = await FirebaseFirestore.instance
        .collection(kAttendanceCollection)
        .where('delegateId', whereIn: queryList)
        .get();

    // Also query logs where userId matches (legacy compatibility)
    final snapUserId = await FirebaseFirestore.instance
        .collection(kAttendanceCollection)
        .where('userId', whereIn: queryList)
        .get();

    // Merge and deduplicate by document ID
    final Map<String, Map<String, dynamic>> rawDocs = {};
    for (final doc in snapDelegateId.docs) {
      rawDocs[doc.id] = doc.data();
    }
    for (final doc in snapUserId.docs) {
      rawDocs[doc.id] = doc.data();
    }

    // Separate check-ins and check-outs
    final Map<String, MapEntry<String, Map<String, dynamic>>> checkOutsByRelatedId = {};
    final List<MapEntry<String, Map<String, dynamic>>> unassignedCheckOuts = [];
    final List<MapEntry<String, Map<String, dynamic>>> checkIns = [];

    rawDocs.forEach((id, data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'check_out') {
        final relId = data['relatedCheckInId']?.toString();
        if (relId != null && relId.isNotEmpty) {
          checkOutsByRelatedId[relId] = MapEntry(id, data);
        } else {
          unassignedCheckOuts.add(MapEntry(id, data));
        }
      } else {
        checkIns.add(MapEntry(id, data));
      }
    });

    final List<DelegateAttendanceSession> sessions = [];

    for (final entry in checkIns) {
      final checkInId = entry.key;
      final checkInData = entry.value;

      DateTime checkInTime = DateTime.now();
      final ts = checkInData['timestamp'];
      if (ts is Timestamp) {
        checkInTime = ts.toDate();
      }

      final branchName =
          (checkInData['branchName'] ?? 'غير محدد').toString().trim();
      final deviceInfo = checkInData['deviceInfo']?.toString();

      double? inLat;
      double? inLng;
      final loc = checkInData['location'];
      if (loc is GeoPoint) {
        inLat = loc.latitude;
        inLng = loc.longitude;
      } else if (loc is Map) {
        inLat = (loc['latitude'] as num?)?.toDouble() ??
            (loc['lat'] as num?)?.toDouble() ??
            double.tryParse(loc['latitude']?.toString() ?? '');
        inLng = (loc['longitude'] as num?)?.toDouble() ??
            (loc['lng'] as num?)?.toDouble() ??
            double.tryParse(loc['longitude']?.toString() ?? '');
      }
      inLat ??= (checkInData['latitude'] as num?)?.toDouble() ??
          (checkInData['lat'] as num?)?.toDouble();
      inLng ??= (checkInData['longitude'] as num?)?.toDouble() ??
          (checkInData['lng'] as num?)?.toDouble();

      // Check for related checkout
      String? checkOutDocId;
      Map<String, dynamic>? checkOutData;

      final relatedOut = checkOutsByRelatedId[checkInId];
      if (relatedOut != null) {
        checkOutDocId = relatedOut.key;
        checkOutData = relatedOut.value;
      } else if (unassignedCheckOuts.isNotEmpty) {
        // If not linked by relatedCheckInId, match chronologically by day
        for (int i = 0; i < unassignedCheckOuts.length; i++) {
          final outEntry = unassignedCheckOuts[i];
          final outTs = outEntry.value['timestamp'];
          if (outTs is Timestamp) {
            final outTime = outTs.toDate();
            if (outTime.year == checkInTime.year &&
                outTime.month == checkInTime.month &&
                outTime.day == checkInTime.day &&
                outTime.isAfter(checkInTime)) {
              checkOutDocId = outEntry.key;
              checkOutData = outEntry.value;
              unassignedCheckOuts.removeAt(i);
              break;
            }
          }
        }
      }

      DateTime? checkOutTime;
      String? outDeviceInfo;
      double? outLat;
      double? outLng;

      if (checkOutData != null) {
        final outTs = checkOutData['timestamp'];
        if (outTs is Timestamp) {
          checkOutTime = outTs.toDate();
        }
        outDeviceInfo = checkOutData['deviceInfo']?.toString();
        final outLoc = checkOutData['location'];
        if (outLoc is GeoPoint) {
          outLat = outLoc.latitude;
          outLng = outLoc.longitude;
        } else if (outLoc is Map) {
          outLat = (outLoc['latitude'] as num?)?.toDouble() ??
              (outLoc['lat'] as num?)?.toDouble() ??
              double.tryParse(outLoc['latitude']?.toString() ?? '');
          outLng = (outLoc['longitude'] as num?)?.toDouble() ??
              (outLoc['lng'] as num?)?.toDouble() ??
              double.tryParse(outLoc['longitude']?.toString() ?? '');
        }
        outLat ??= (checkOutData['latitude'] as num?)?.toDouble() ??
            (checkOutData['lat'] as num?)?.toDouble();
        outLng ??= (checkOutData['longitude'] as num?)?.toDouble() ??
            (checkOutData['lng'] as num?)?.toDouble();
      }

      bool isAutoCheckOut = checkOutData?['isAutoCheckOut'] == true;
      String? autoCheckOutReason = checkOutData?['autoCheckOutReason']?.toString();

      // قاعدة الـ 9 ساعات: إغلاق الانصراف ديناميكياً إذا انقضت الوردية (9 ساعات) أو كان تاريخاً سابقاً
      if (checkOutTime == null) {
        final now = DateTime.now();
        final isPastDay = checkInTime.isBefore(DateTime(now.year, now.month, now.day));
        final isElapsed9Hours = now.difference(checkInTime) >= const Duration(hours: 9);
        if (isPastDay || isElapsed9Hours) {
          checkOutTime = checkInTime.add(const Duration(hours: 9));
          isAutoCheckOut = true;
          autoCheckOutReason = 'نهاية شيفت العمل (9 ساعات) - إغلاق تلقائي';
        }
      }

      // Calculate distance to branch
      double? distance;
      bool? isInside;

      if (inLat != null && inLng != null && branchName != 'غير محدد') {
        final cleanBranch = branchName.toLowerCase().trim();
        Branch? matchedBranch = _branchesByName[cleanBranch];
        if (matchedBranch == null) {
          for (final entry in _branchesByName.entries) {
            if (entry.key.contains(cleanBranch) || cleanBranch.contains(entry.key)) {
              matchedBranch = entry.value;
              break;
            }
          }
        }
        if (matchedBranch != null &&
            matchedBranch.latitude != 0.0 &&
            matchedBranch.longitude != 0.0) {
          distance = Geolocator.distanceBetween(
            inLat,
            inLng,
            matchedBranch.latitude,
            matchedBranch.longitude,
          );
          isInside = distance <= (matchedBranch.geofenceRadius + 20.0);
        }
      }

      // Check if session was manually adjusted by HR
      final bool isManuallyAdjusted = (checkInData['isManuallyAdjusted'] == true) ||
          (checkOutData != null && checkOutData['isManuallyAdjusted'] == true);
      final String? lastAdjustedBy = checkInData['lastAdjustedBy']?.toString() ??
          checkOutData?['lastAdjustedBy']?.toString();
      DateTime? lastAdjustedAt;
      final adjTs = checkInData['lastAdjustedAt'] ?? checkOutData?['lastAdjustedAt'];
      if (adjTs is Timestamp) {
        lastAdjustedAt = adjTs.toDate();
      }
      final String? adjustmentReason = checkInData['adjustmentReason']?.toString() ??
          checkOutData?['adjustmentReason']?.toString();

      sessions.add(
        DelegateAttendanceSession(
          id: checkInId,
          checkInTime: checkInTime,
          checkOutTime: checkOutTime,
          branchName: branchName,
          deviceInfo: deviceInfo,
          latitude: inLat,
          longitude: inLng,
          distanceMeters: distance,
          isInsideGeofence: isInside,
          checkOutDeviceInfo: outDeviceInfo,
          checkOutLatitude: outLat,
          checkOutLongitude: outLng,
          checkOutDocId: checkOutDocId,
          isManuallyAdjusted: isManuallyAdjusted,
          lastAdjustedBy: lastAdjustedBy,
          lastAdjustedAt: lastAdjustedAt,
          adjustmentReason: adjustmentReason,
          isAutoCheckOut: isAutoCheckOut,
          autoCheckOutReason: autoCheckOutReason,
        ),
      );
    }

    // Sort descending by check-in time
    sessions.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

    if (mounted) {
      setState(() {
        _allSessions = sessions;
        _isLoading = false;
      });
    }
  }

  // --- Filtering Sessions for the Selected Month ---
  List<DelegateAttendanceSession> get _monthlySessions {
    return _allSessions.where((s) {
      return s.checkInTime.year == _selectedMonth.year &&
          s.checkInTime.month == _selectedMonth.month;
    }).toList();
  }

  List<DelegateAttendanceSession> get _filteredMonthlySessions {
    return _monthlySessions.where((s) {
      // Branch filter
      if (_selectedBranchFilter != 'all') {
        if (s.branchName.toLowerCase().trim() !=
            _selectedBranchFilter.toLowerCase().trim()) {
          return false;
        }
      }
      // Status filter
      if (_selectedStatusFilter == 'completed') {
        if (s.checkOutTime == null) return false;
      } else if (_selectedStatusFilter == 'incomplete') {
        if (s.checkOutTime != null) return false;
      }
      return true;
    }).toList();
  }

  Set<String> get _branchesInCurrentMonth {
    final set = <String>{};
    for (final s in _monthlySessions) {
      if (s.branchName.isNotEmpty && s.branchName != 'غير محدد') {
        set.add(s.branchName);
      }
    }
    return set;
  }

  // --- Monthly Analytics KPIs ---
  int get _uniquePresentDaysCount {
    final days = <String>{};
    for (final s in _monthlySessions) {
      days.add('${s.checkInTime.year}-${s.checkInTime.month}-${s.checkInTime.day}');
    }
    return days.length;
  }

  int get _completedCheckOutsCount {
    return _monthlySessions.where((s) => s.checkOutTime != null).length;
  }

  Duration get _totalMonthlyWorkedDuration {
    var totalSeconds = 0;
    for (final s in _monthlySessions) {
      final d = s.duration;
      if (d != null) {
        totalSeconds += d.inSeconds;
      }
    }
    return Duration(seconds: totalSeconds);
  }

  String get _formattedTotalWorkedHours {
    final d = _totalMonthlyWorkedDuration;
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60);
    return '$hours ساعة و $mins دقيقة';
  }

  String get _formattedAverageDailyHours {
    final days = _uniquePresentDaysCount;
    if (days == 0) return '0.0 ساعة/يوم';
    final totalHours = _totalMonthlyWorkedDuration.inMinutes / 60.0;
    final avg = totalHours / days;
    return '${avg.toStringAsFixed(1)} ساعة/يوم';
  }

  // --- Month Navigation Actions ---
  void _goToPreviousMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
        1,
      );
      _selectedBranchFilter = 'all';
    });
  }

  void _goToNextMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        1,
      );
      _selectedBranchFilter = 'all';
    });
  }

  void _goToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _selectedMonth = DateTime(now.year, now.month, 1);
      _selectedBranchFilter = 'all';
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  Future<void> _exportMonthlyReportToCSV() async {
    final sessions = _filteredMonthlySessions;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات حضور لتصديرها في هذا الشهر')),
      );
      return;
    }

    final monthStr = DateFormat('yyyy_MM', 'en').format(_selectedMonth);
    final safeName = widget.delegate.fullName
        .replaceAll(RegExp(r'[\/\\?%*:|"<> ]'), '_')
        .trim();
    final fileName = 'تقرير_حضور_${safeName}_$monthStr.csv';

    final buffer = StringBuffer();
    // UTF-8 BOM for Arabic support in Microsoft Excel
    buffer.write('\uFEFF');

    // Header metadata
    buffer.writeln('تقرير الحضور والانصراف التفصيلي');
    buffer.writeln('المندوب:,"${widget.delegate.fullName}"');
    buffer.writeln('الهاتف:,"${widget.delegate.phoneNumber}"');
    buffer.writeln('الرقم القومي:,"${widget.delegate.nationalityID}"');
    buffer.writeln('الشهر:,"${DateFormat('MMMM yyyy', 'ar').format(_selectedMonth)}"');
    buffer.writeln('أيام الحضور:,$_uniquePresentDaysCount');
    buffer.writeln('إجمالي ساعات العمل:,"$_formattedTotalWorkedHours"');
    buffer.writeln('متوسط ساعات العمل اليومي:,"$_formattedAverageDailyHours"');
    buffer.writeln('');

    // Table Headers
    buffer.writeln('التاريخ,اليوم,الفرع,وقت الحضور,وقت الانصراف,ساعات العمل,الحالة,الجهاز المستخدم,المسافة من الفرع');

    for (final s in sessions) {
      final dateStr = DateFormat('yyyy-MM-dd', 'en').format(s.checkInTime);
      final dayStr = DateFormat('EEEE', 'ar').format(s.checkInTime);
      final branchStr = s.branchName;
      final checkInStr = DateFormat('hh:mm a', 'ar').format(s.checkInTime);
      final checkOutStr = s.checkOutTime != null
          ? (s.isAutoCheckOut
              ? '${DateFormat('hh:mm a', 'ar').format(s.checkOutTime!)} (إغلاق تلقائي)'
              : DateFormat('hh:mm a', 'ar').format(s.checkOutTime!))
          : 'لم يسجل انصراف';
      final durationStr = s.formattedDuration;
      final statusStr = s.isAutoCheckOut
          ? 'مكتمل (تلقائي)'
          : (s.checkOutTime != null
              ? 'مكتمل'
              : (s.isOngoing ? 'حاضر الآن' : 'غير مكتمل'));
      final deviceStr = s.deviceInfo ?? 'غير مسجل';
      final distanceStr = s.distanceMeters != null
          ? '${s.distanceMeters!.round()} م (${s.isInsideGeofence == true ? 'داخل النطاق' : 'خارج النطاق'})'
          : 'غير محدد';

      buffer.writeln(
        '"$dateStr","$dayStr","$branchStr","$checkInStr","$checkOutStr","$durationStr","$statusStr","$deviceStr","$distanceStr"',
      );
    }

    await FileDownloadHelper.downloadString(
      content: buffer.toString(),
      fileName: fileName,
      mimeType: 'text/csv;charset=utf-8',
      shareText: 'تقرير حضور ${widget.delegate.fullName} لشهر ${DateFormat('MMMM yyyy', 'ar').format(_selectedMonth)}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تصدير التقرير الشهري بنجاح: $fileName'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    var clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('0')) {
      clean = '20${clean.substring(1)}';
    } else if (!clean.startsWith('20')) {
      clean = '20$clean';
    }
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSessionDetailsDialog(DelegateAttendanceSession session) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(session.checkInTime);
    final inTimeStr = DateFormat('hh:mm:ss a', 'ar').format(session.checkInTime);
    final outTimeStr = session.checkOutTime != null
        ? (session.isAutoCheckOut
            ? '${DateFormat('hh:mm:ss a', 'ar').format(session.checkOutTime!)} (إغلاق تلقائي)'
            : DateFormat('hh:mm:ss a', 'ar').format(session.checkOutTime!))
        : 'لم يتم تسجيل انصراف';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.info_outline_rounded, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تفاصيل جلسة الحضور', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(dateStr, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session.isAutoCheckOut) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_mode_rounded, size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Text(
                              'تم إغلاق الانصراف تلقائياً (نظام الـ 9 ساعات)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          session.autoCheckOutReason ??
                              'تم إغلاق الجلسة أوتوماتيكياً لاكتمال مدة الشفت (9 ساعات) دون تسجيل انصراف يدوي من المندوب.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF451A03)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (session.isManuallyAdjusted) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Text(
                              'تم تعديل هذه الجلسة إدارياً',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'المسؤول: ${session.lastAdjustedBy ?? "إدارة الموارد البشرية"}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF451A03)),
                        ),
                        if (session.adjustmentReason != null && session.adjustmentReason!.isNotEmpty)
                          Text(
                            'السبب: ${session.adjustmentReason}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF451A03)),
                          ),
                        if (session.lastAdjustedAt != null)
                          Text(
                            'تاريخ التعديل: ${DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(session.lastAdjustedAt!)}',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                          ),
                      ],
                    ),
                  ),
                ],
                _buildDialogDetailRow(Icons.store_rounded, 'الفرع', session.branchName),
                const Divider(height: 16),
                _buildDialogDetailRow(Icons.login_rounded, 'وقت الحضور الدقيق', inTimeStr, valueColor: Colors.green.shade700),
                if (session.latitude != null && session.longitude != null)
                  _buildDialogDetailRow(
                    Icons.location_on_outlined,
                    'إحداثيات الحضور',
                    '${session.latitude!.toStringAsFixed(6)}, ${session.longitude!.toStringAsFixed(6)}',
                  ),
                if (session.deviceInfo != null)
                  _buildDialogDetailRow(Icons.smartphone_rounded, 'جهاز الحضور', session.deviceInfo!),
                const Divider(height: 16),
                _buildDialogDetailRow(
                  Icons.logout_rounded,
                  'وقت الانصراف الدقيق',
                  outTimeStr,
                  valueColor: session.checkOutTime != null ? Colors.orange.shade800 : colorScheme.error,
                ),
                if (session.checkOutLatitude != null && session.checkOutLongitude != null)
                  _buildDialogDetailRow(
                    Icons.location_on_outlined,
                    'إحداثيات الانصراف',
                    '${session.checkOutLatitude!.toStringAsFixed(6)}, ${session.checkOutLongitude!.toStringAsFixed(6)}',
                  ),
                if (session.checkOutDeviceInfo != null)
                  _buildDialogDetailRow(Icons.smartphone_rounded, 'جهاز الانصراف', session.checkOutDeviceInfo!),
                const Divider(height: 16),
                _buildDialogDetailRow(Icons.timer_outlined, 'إجمالي مدة العمل', session.formattedDuration, valueColor: colorScheme.primary),
                if (session.distanceMeters != null)
                  _buildDialogDetailRow(
                    Icons.radar_rounded,
                    'المسافة من الفرع',
                    '${session.distanceMeters!.round()} متر (${session.isInsideGeofence == true ? 'داخل النطاق الجغرافي' : 'خارج النطاق الجغرافي'})',
                    valueColor: session.isInsideGeofence == true ? Colors.green.shade700 : Colors.red.shade700,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditAttendanceDialog(session);
            },
            icon: const Icon(Icons.edit_calendar_rounded, size: 16),
            label: const Text('تعديل التوقيت'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showEditAttendanceDialog(DelegateAttendanceSession session) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(session.checkInTime);

    TimeOfDay selectedCheckInTime = TimeOfDay.fromDateTime(session.checkInTime);
    bool hasCheckOut = session.checkOutTime != null;
    TimeOfDay selectedCheckOutTime = session.checkOutTime != null
        ? TimeOfDay.fromDateTime(session.checkOutTime!)
        : const TimeOfDay(hour: 17, minute: 0);

    const List<String> adjustmentReasons = [
      'نسيان تسجيل الانصراف من قِبل المندوب',
      'عطل في هاتف المندوب أو نفاد البطارية',
      'مشكلة تقنية في تطبيق المندوب أو الاتصال',
      'توجيه إداري بتمديد أو تعديل فترة العمل',
      'إذن مسبق وموافق عليه من المشرف الميداني',
      'تصحيح توقيت الحضور (حضور مبكر/متأخر معتمد)',
      'أخرى (يرجى التوضيح في الملاحظات الإدارية)',
    ];

    String selectedReason = adjustmentReasons.first;
    final notesController = TextEditingController();
    bool isSaving = false;
    String? localValidationError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final newInDateTime = DateTime(
            session.checkInTime.year,
            session.checkInTime.month,
            session.checkInTime.day,
            selectedCheckInTime.hour,
            selectedCheckInTime.minute,
          );

          final newOutDateTime = hasCheckOut
              ? DateTime(
                  session.checkInTime.year,
                  session.checkInTime.month,
                  session.checkInTime.day,
                  selectedCheckOutTime.hour,
                  selectedCheckOutTime.minute,
                )
              : null;

          final bool isNegativeDuration = hasCheckOut && newOutDateTime!.isBefore(newInDateTime);
          final Duration? newDuration = hasCheckOut && !isNegativeDuration
              ? newOutDateTime!.difference(newInDateTime)
              : null;

          String? durationDiffText;
          Color? durationDiffColor;
          if (newDuration != null) {
            final oldDurationMins = session.duration?.inMinutes ?? 0;
            final newDurationMins = newDuration.inMinutes;
            final diffMins = newDurationMins - oldDurationMins;
            if (diffMins != 0) {
              final isPositive = diffMins > 0;
              final absMins = diffMins.abs();
              final h = absMins ~/ 60;
              final m = absMins % 60;
              final formattedDiff = h > 0 ? '$h س ${m > 0 ? "و $m د" : ""}' : '$m دقيقة';
              durationDiffText = '${isPositive ? "+" : "-"}$formattedDiff';
              durationDiffColor = isPositive ? Colors.green.shade700 : Colors.red.shade700;
            } else {
              durationDiffText = 'بدون تغيير في المدة';
              durationDiffColor = colorScheme.onSurfaceVariant;
            }
          }

          String formatTime(TimeOfDay t) {
            final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
            final m = t.minute.toString().padLeft(2, '0');
            final period = t.period == DayPeriod.am ? 'ص' : 'م';
            return '$h:$m $period';
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.edit_calendar_rounded, color: Colors.amber.shade900, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'تعديل توقيت جلسة الحضور',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.delegate.fullName} • $dateStr',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.store_rounded, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'الفرع: ${session.branchName}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Time adjustments card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ضبط الأوقات',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 12),

                          // 1. Check-in picker
                          Row(
                            children: [
                              Icon(Icons.login_rounded, size: 18, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('وقت تسجيل الحضور:', style: TextStyle(fontSize: 13)),
                              ),
                              OutlinedButton.icon(
                                onPressed: isSaving ? null : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: selectedCheckInTime,
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedCheckInTime = picked;
                                      localValidationError = null;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time_rounded, size: 16),
                                label: Text(
                                  formatTime(selectedCheckInTime),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),

                          // 2. Check-out toggle & picker
                          Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 18,
                                color: hasCheckOut ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('تسجيل الانصراف:', style: TextStyle(fontSize: 13)),
                                    if (session.checkOutTime == null)
                                      Text(
                                        'لم يسجل المندوب انصرافاً',
                                        style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                                      ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: hasCheckOut,
                                onChanged: isSaving ? null : (val) {
                                  setDialogState(() {
                                    hasCheckOut = val;
                                    localValidationError = null;
                                  });
                                },
                              ),
                              if (hasCheckOut) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: isSaving ? null : () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: selectedCheckOutTime,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedCheckOutTime = picked;
                                        localValidationError = null;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.access_time_rounded, size: 16),
                                  label: Text(
                                    formatTime(selectedCheckOutTime),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Duration Comparison Preview
                    if (isNegativeDuration)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تنبيه: وقت الانصراف يجب أن يكون بعد وقت الحضور!',
                                style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (hasCheckOut && newDuration != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timelapse_rounded, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'المدة الجديدة: ',
                                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                      ),
                                      Text(
                                        '${newDuration.inHours} س و ${newDuration.inMinutes.remainder(60)} د',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (durationDiffText != null)
                                    Text(
                                      'الفارق عن السابق: $durationDiffText (سابقاً: ${session.formattedDuration})',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: durationDiffColor),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Mandatory Adjustment Reason
                    const Text(
                      'سبب التعديل الإداري (إلزامي للتدقيق):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: adjustmentReasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: isSaving ? null : (val) {
                        if (val != null) {
                          setDialogState(() => selectedReason = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Additional Notes
                    const Text(
                      'ملاحظات إضافية (اختياري):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      enabled: !isSaving,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'أدخل أي تفاصيل إدارية توضيحية لتسجيلها في ملف التدقيق...',
                        hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),

                    if (localValidationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        localValidationError!,
                        style: TextStyle(fontSize: 12, color: colorScheme.error, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: (isSaving || isNegativeDuration)
                    ? null
                    : () async {
                        final bool checkInChanged = newInDateTime != session.checkInTime;
                        final bool checkOutChanged = (session.checkOutTime == null && hasCheckOut) ||
                            (session.checkOutTime != null && (!hasCheckOut || newOutDateTime != session.checkOutTime));

                        if (!checkInChanged && !checkOutChanged) {
                          setDialogState(() {
                            localValidationError = 'لم تقم بتغيير وقت الحضور أو الانصراف.';
                          });
                          return;
                        }

                        if (selectedReason.startsWith('أخرى') && notesController.text.trim().isEmpty) {
                          setDialogState(() {
                            localValidationError = 'يرجى كتابة الملاحظات الإدارية عند اختيار سبب أخرى.';
                          });
                          return;
                        }

                        setDialogState(() {
                          isSaving = true;
                          localValidationError = null;
                        });

                        try {
                          await _executeAttendanceAdjustment(
                            session: session,
                            newInTime: newInDateTime,
                            newOutTime: newOutDateTime,
                            hasCheckOut: hasCheckOut,
                            reason: selectedReason,
                            notes: notesController.text.trim(),
                          );
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setDialogState(() {
                              isSaving = false;
                              localValidationError = 'حدث خطأ أثناء حفظ التعديل: $e';
                            });
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(isSaving ? 'جارٍ الحفظ والاعتماد...' : 'حفظ التعديل والاعتماد'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeAttendanceAdjustment({
    required DelegateAttendanceSession session,
    required DateTime newInTime,
    required DateTime? newOutTime,
    required bool hasCheckOut,
    required String reason,
    required String notes,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    final String hrName = widget.hrDelegate?.fullName.isNotEmpty == true
        ? widget.hrDelegate!.fullName
        : 'مسؤول الموارد البشرية';
    final String hrUid = widget.hrDelegate?.uid ?? 'HR';
    final String companyUID = widget.delegate.companyUID.isNotEmpty
        ? widget.delegate.companyUID
        : (widget.hrDelegate?.companyUID ?? '');
    final String orgUID = widget.delegate.organizationUID;

    // 1. Update Check-In Doc in attendance_logs
    final checkInRef = FirebaseFirestore.instance
        .collection(kAttendanceCollection)
        .doc(session.id);

    batch.update(checkInRef, {
      'timestamp': Timestamp.fromDate(newInTime),
      'isManuallyAdjusted': true,
      'lastAdjustedBy': hrName,
      'lastAdjustedAt': FieldValue.serverTimestamp(),
      'adjustmentReason': reason,
      if (notes.isNotEmpty) 'adjustmentNotes': notes,
    });

    // 2. Handle Check-Out Doc in attendance_logs
    String checkOutDocId = session.checkOutDocId ?? '';
    final bool isNewCheckOutCreated =
        (session.checkOutDocId == null || session.checkOutDocId!.isEmpty) &&
            hasCheckOut &&
            newOutTime != null;

    if (hasCheckOut && newOutTime != null) {
      if (isNewCheckOutCreated) {
        final newOutRef =
            FirebaseFirestore.instance.collection(kAttendanceCollection).doc();
        checkOutDocId = newOutRef.id;
        batch.set(newOutRef, {
          'delegateId': widget.delegate.uid,
          'userId': widget.delegate.uid,
          'companyId': companyUID,
          'organizationId': orgUID,
          'timestamp': Timestamp.fromDate(newOutTime),
          'type': 'check_out',
          'relatedCheckInId': session.id,
          'branchName': session.branchName,
          'deviceInfo': 'تسجيل يدوي بواسطة الموارد البشرية',
          if (session.latitude != null && session.longitude != null)
            'location': {
              'latitude': session.latitude,
              'longitude': session.longitude,
            },
          'isManuallyAdjusted': true,
          'lastAdjustedBy': hrName,
          'lastAdjustedAt': FieldValue.serverTimestamp(),
          'adjustmentReason': reason,
          if (notes.isNotEmpty) 'adjustmentNotes': notes,
        });
      } else {
        final outRef = FirebaseFirestore.instance
            .collection(kAttendanceCollection)
            .doc(checkOutDocId);
        batch.update(outRef, {
          'timestamp': Timestamp.fromDate(newOutTime),
          'isManuallyAdjusted': true,
          'lastAdjustedBy': hrName,
          'lastAdjustedAt': FieldValue.serverTimestamp(),
          'adjustmentReason': reason,
          if (notes.isNotEmpty) 'adjustmentNotes': notes,
        });
      }
    }

    // 3. Create Audit Record in attendance_adjustment_logs
    final auditRef = FirebaseFirestore.instance
        .collection(kAttendanceAdjustmentLogsCollection)
        .doc();

    final bool wasCheckInModified = newInTime != session.checkInTime;
    final bool wasCheckOutModified =
        (session.checkOutTime == null && hasCheckOut) ||
            (session.checkOutTime != null &&
                (!hasCheckOut || newOutTime != session.checkOutTime));

    final int? origDurationMins = session.duration?.inMinutes;
    final int? newDurationMins = hasCheckOut && newOutTime != null
        ? newOutTime.difference(newInTime).inMinutes
        : null;

    batch.set(auditRef, {
      'companyUID': companyUID,
      'organizationUID': orgUID,
      'delegateUID': widget.delegate.uid,
      'delegateName': widget.delegate.fullName,
      'delegatePhotoUrl': widget.delegate.personalPhotoUrl,
      'delegatePhone': widget.delegate.phoneNumber,
      'delegateRole': widget.delegate.role.name,
      'branchName': session.branchName,
      'attendanceSessionId': session.id,
      'checkInDocId': session.id,
      'checkOutDocId': checkOutDocId,
      'sessionDate': Timestamp.fromDate(
        DateTime(session.checkInTime.year, session.checkInTime.month, session.checkInTime.day),
      ),
      'originalCheckInTime': Timestamp.fromDate(session.checkInTime),
      'newCheckInTime': Timestamp.fromDate(newInTime),
      'wasCheckInModified': wasCheckInModified,
      'originalCheckOutTime': session.checkOutTime != null
          ? Timestamp.fromDate(session.checkOutTime!)
          : null,
      'newCheckOutTime':
          hasCheckOut && newOutTime != null ? Timestamp.fromDate(newOutTime) : null,
      'wasCheckOutModified': wasCheckOutModified,
      'isNewCheckOutCreated': isNewCheckOutCreated,
      'originalDurationMinutes': origDurationMins,
      'newDurationMinutes': newDurationMins,
      'adjustedByUID': hrUid,
      'adjustedByName': hrName,
      'adjustedByRole': 'HR',
      'reason': reason,
      'notes': notes.isNotEmpty ? notes : null,
      'adjustedAt': FieldValue.serverTimestamp(),
    });

    // 4. Send In-App Notification to Delegate
    final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
    final dateStr = DateFormat('yyyy/MM/dd', 'ar').format(session.checkInTime);
    batch.set(notifRef, {
      'delegateUid': widget.delegate.uid,
      'phoneNumber': widget.delegate.phoneNumber,
      'companyUID': companyUID,
      'organizationId': orgUID,
      'title': 'تعديل إداري في سجل الحضور والانصراف',
      'body':
          'قامت إدارة الموارد البشرية بتعديل توقيت جلسة حضورك في فرع "${session.branchName}" بتاريخ $dateStr. السبب: $reason.',
      'type': 'attendance_adjusted',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': hrUid,
      'senderName': hrName,
    });

    // 5. Commit batch atomically
    await batch.commit();

    // 6. Reload attendance data
    await _fetchDelegateLogs();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تعديل توقيت جلسة الحضور بنجاح وتسجيل العملية في سجل التدقيق.',
          ),
          backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildDialogDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('سجل الحضور والانصراف التفصيلي', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HRAttendanceAdjustmentsScreen(
                      hrDelegate: widget.hrDelegate ?? widget.delegate,
                      initialDelegateUID: widget.delegate.uid,
                      showAppBar: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.history_edu_rounded, size: 18),
              label: Text(isWide ? 'سجل التعديلات الإدارية' : 'التعديلات'),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.tonalIcon(
              onPressed: _exportMonthlyReportToCSV,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(isWide ? 'تصدير التقرير الشهري (CSV)' : 'تصدير'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: _loadBranchesAndAttendance,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchDelegateLogs,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 24 : 12,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Delegate Profile Card
                        _buildDelegateProfileHeader(colorScheme, isWide),
                        const SizedBox(height: 16),

                        // 2. Month Selector Navigation Bar
                        _buildMonthSelectorBar(colorScheme, isWide),
                        const SizedBox(height: 16),

                        // 3. Monthly Analytics KPI Cards
                        _buildMonthlyKpiCards(colorScheme, isWide),
                        const SizedBox(height: 20),

                        // 4. Filter & Search Controls
                        _buildFilterBar(colorScheme, isWide),
                        const SizedBox(height: 16),

                        // 5. Attendance History Table / Cards
                        _buildHistorySection(colorScheme, isWide),
                      ],
                    ),
                  ),
                ),
    );
  }

  // --- 1. Delegate Profile Header ---
  Widget _buildDelegateProfileHeader(ColorScheme colorScheme, bool isWide) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 20 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppAvatar(
              imageUrl: widget.delegate.personalPhotoUrl,
              fallbackText: widget.delegate.fullName,
              radius: isWide ? 32 : 26,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        widget.delegate.fullName,
                        style: TextStyle(
                          fontSize: isWide ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.delegate.role == UserRole.delegate ? 'مندوب / مروج' : 'مشرف',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _buildInfoBadge(Icons.phone_rounded, widget.delegate.phoneNumber),
                      _buildInfoBadge(Icons.badge_outlined, 'قومي: ${widget.delegate.nationalityID}'),
                      if (widget.delegate.companyName.isNotEmpty)
                        _buildInfoBadge(Icons.apartment_rounded, widget.delegate.companyName),
                      if (widget.delegate.boundDeviceModel != null &&
                          widget.delegate.boundDeviceModel!.isNotEmpty)
                        _buildInfoBadge(Icons.smartphone_rounded, widget.delegate.boundDeviceModel!),
                    ],
                  ),
                ],
              ),
            ),
            if (isWide) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TashilIconButton(
                    icon: Icons.call_rounded,
                    color: Colors.green,
                    tooltip: 'اتصال هاتفي',
                    onPressed: () => _makePhoneCall(widget.delegate.phoneNumber),
                  ),
                  const SizedBox(width: 8),
                  TashilIconButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    color: Colors.teal,
                    tooltip: 'مراسلة عبر واتساب',
                    onPressed: () => _openWhatsApp(widget.delegate.phoneNumber),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  // --- 2. Month Selector Navigation Bar ---
  Widget _buildMonthSelectorBar(ColorScheme colorScheme, bool isWide) {
    final monthDisplay = DateFormat('MMMM yyyy', 'ar').format(_selectedMonth);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Month Button (< الشهر السابق)
          FilledButton.tonalIcon(
            onPressed: _goToPreviousMonth,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            label: Text(isWide ? 'الشهر السابق' : 'السابق'),
          ),

          // Current Displayed Month
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                monthDisplay,
                style: TextStyle(
                  fontSize: isWide ? 18 : 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              if (!_isCurrentMonth) ...[
                const SizedBox(width: 10),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('الشهر الحالي', style: TextStyle(fontSize: 11)),
                  onPressed: _goToCurrentMonth,
                ),
              ],
            ],
          ),

          // Next Month Button (الشهر التالي >)
          FilledButton.tonalIcon(
            onPressed: _goToNextMonth,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            label: Text(isWide ? 'الشهر التالي' : 'التالي'),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
          ),
        ],
      ),
    );
  }

  // --- 3. Monthly Analytics KPI Cards ---
  Widget _buildMonthlyKpiCards(ColorScheme colorScheme, bool isWide) {
    final kpis = [
      _KpiItem(
        title: 'أيام الحضور',
        value: '$_uniquePresentDaysCount يوم',
        subtitle: 'خلال هذا الشهر',
        icon: Icons.how_to_reg_rounded,
        color: Colors.green,
      ),
      _KpiItem(
        title: 'مرات الانصراف',
        value: '$_completedCheckOutsCount مرة',
        subtitle: 'جلسات مكتملة',
        icon: Icons.logout_rounded,
        color: Colors.orange,
      ),
      _KpiItem(
        title: 'إجمالي الساعات',
        value: _formattedTotalWorkedHours,
        subtitle: 'وقت العمل الفعلي',
        icon: Icons.access_time_filled_rounded,
        color: colorScheme.primary,
      ),
      _KpiItem(
        title: 'متوسط الساعات اليومي',
        value: _formattedAverageDailyHours,
        subtitle: 'لكل يوم عمل',
        icon: Icons.speed_rounded,
        color: Colors.teal,
      ),
      _KpiItem(
        title: 'الفروع المزارة',
        value: '${_branchesInCurrentMonth.length} فرع',
        subtitle: _branchesInCurrentMonth.isEmpty ? 'لا فروع' : _branchesInCurrentMonth.take(2).join(', '),
        icon: Icons.store_rounded,
        color: Colors.deepPurple,
      ),
    ];

    if (isWide) {
      return Row(
        children: kpis.map((kpi) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _buildSingleKpiCard(kpi, colorScheme),
            ),
          );
        }).toList(),
      );
    } else {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kpis.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(
            width: 170,
            child: _buildSingleKpiCard(kpis[i], colorScheme),
          ),
        ),
      );
    }
  }

  Widget _buildSingleKpiCard(_KpiItem kpi, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                kpi.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              CircleAvatar(
                radius: 14,
                backgroundColor: kpi.color.withValues(alpha: 0.15),
                child: Icon(kpi.icon, size: 16, color: kpi.color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            kpi.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            kpi.subtitle,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- 4. Filter Bar (Unified Design across Branch Selector, Status Filters, & Records Count) ---
  Widget _buildFilterBar(ColorScheme colorScheme, bool isWide) {
    final branches = ['all', ..._branchesInCurrentMonth];

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1. Branch Selector (Unified Capsule Track)
        _buildBranchFilterControl(branches, colorScheme),

        // 2. Status Filter Group (Unified Capsule Track)
        _buildStatusFilterControl(colorScheme),

        // 3. Record Count Badge (Unified Capsule Track)
        _buildRecordCountBadge(colorScheme),
      ],
    );
  }

  Widget _buildBranchFilterControl(List<String> branches, ColorScheme colorScheme) {
    final selectedBranch = branches.contains(_selectedBranchFilter) ? _selectedBranchFilter : 'all';
    final label = selectedBranch == 'all'
        ? 'جميع الفروع (${_branchesInCurrentMonth.length})'
        : selectedBranch;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'تصفية حسب الفرع',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        initialValue: selectedBranch,
        onSelected: (val) {
          setState(() => _selectedBranchFilter = val);
        },
        itemBuilder: (ctx) => branches.map((b) {
          final isSelected = b == selectedBranch;
          return PopupMenuItem<String>(
            value: b,
            child: Row(
              children: [
                Icon(
                  b == 'all' ? Icons.storefront_rounded : Icons.store_rounded,
                  size: 18,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  b == 'all' ? 'جميع الفروع (${_branchesInCurrentMonth.length})' : b,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_rounded, size: 17, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterControl(ColorScheme colorScheme) {
    return TashilConnectedButtonGroup<String>(
      height: 40,
      items: const [
        TashilConnectedButtonItem(value: 'all', label: 'الكل'),
        TashilConnectedButtonItem(value: 'completed', label: 'مكتمل'),
        TashilConnectedButtonItem(value: 'incomplete', label: 'غير مكتمل'),
      ],
      selectedValue: _selectedStatusFilter,
      onSelected: (val) {
        setState(() => _selectedStatusFilter = val);
      },
    );
  }

  Widget _buildRecordCountBadge(ColorScheme colorScheme) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 17, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'عدد السجلات: ${_filteredMonthlySessions.length}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // --- 5. Attendance History Section (Desktop Table / Mobile Cards) ---
  Widget _buildHistorySection(ColorScheme colorScheme, bool isWide) {
    final sessions = _filteredMonthlySessions;

    if (sessions.isEmpty) {
      return Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy_rounded, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                'لا توجد سجلات حضور مسجلة لهذا المندوب في شهر ${DateFormat('MMMM yyyy', 'ar').format(_selectedMonth)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك التنقل للأشهر السابقة أو التالية باستخدام أزرار التنقل أعلاه.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (isWide) {
      return _buildDesktopTable(sessions, colorScheme);
    } else {
      return _buildMobileCardsList(sessions, colorScheme);
    }
  }

  // Desktop / Web Table Column Flex Constants (Guaranteed 1:1 Header/Row Synchronization)
  static const int _colFlexDate = 14;        // التاريخ واليوم
  static const int _colFlexBranch = 14;      // الفرع
  static const int _colFlexInTime = 13;      // تسجيل الحضور
  static const int _colFlexOutTime = 13;     // تسجيل الانصراف
  static const int _colFlexDuration = 12;    // مدة العمل
  static const int _colFlexStatus = 16;      // الحالة
  static const int _colFlexDevice = 17;      // الجهاز والمسافة
  static const int _colFlexActions = 11;     // التعديل والتفاصيل

  // Desktop / Web Table
  Widget _buildDesktopTable(List<DelegateAttendanceSession> sessions, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minTableWidth = 980.0;
          final bool needsScroll = constraints.maxWidth < minTableWidth;
          final double tableWidth = needsScroll ? minTableWidth : constraints.maxWidth;

          Widget tableContent = SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      _buildHeaderCell('التاريخ واليوم', flex: _colFlexDate),
                      _buildHeaderCell('الفرع', flex: _colFlexBranch),
                      _buildHeaderCell('تسجيل الحضور', flex: _colFlexInTime),
                      _buildHeaderCell('تسجيل الانصراف', flex: _colFlexOutTime),
                      _buildHeaderCell('مدة العمل', flex: _colFlexDuration),
                      _buildHeaderCell('الحالة', flex: _colFlexStatus),
                      _buildHeaderCell('الجهاز والمسافة', flex: _colFlexDevice),
                      _buildHeaderCell('الإجراءات', flex: _colFlexActions, alignment: AlignmentDirectional.center),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),

                // Table Rows
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  itemBuilder: (ctx, index) {
                    final s = sessions[index];
                    final isEven = index % 2 == 0;
                    final dateStr = DateFormat('yyyy/MM/dd', 'en').format(s.checkInTime);
                    final dayStr = DateFormat('EEEE', 'ar').format(s.checkInTime);
                    final inTimeStr = DateFormat('hh:mm a', 'ar').format(s.checkInTime);
                    final outTimeStr = s.checkOutTime != null
                        ? DateFormat('hh:mm a', 'ar').format(s.checkOutTime!)
                        : '-';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: isEven
                          ? colorScheme.surface
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                      child: Row(
                        children: [
                          // 1. Date & Day
                          Expanded(
                            flex: _colFlexDate,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      dayStr,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dateStr,
                                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 2. Branch
                          Expanded(
                            flex: _colFlexBranch,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.storefront_rounded, size: 16, color: colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        s.branchName,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 3. Check-in Time
                          Expanded(
                            flex: _colFlexInTime,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.login_rounded, size: 16, color: Colors.green.shade700),
                                    const SizedBox(width: 6),
                                    Text(
                                      inTimeStr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 4. Check-out Time
                          Expanded(
                            flex: _colFlexOutTime,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      s.isAutoCheckOut
                                          ? Icons.auto_mode_rounded
                                          : Icons.logout_rounded,
                                      size: 16,
                                      color: s.isAutoCheckOut
                                          ? Colors.amber.shade800
                                          : (s.checkOutTime != null
                                              ? Colors.orange.shade800
                                              : colorScheme.error.withValues(alpha: 0.6)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      outTimeStr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: s.isAutoCheckOut
                                            ? Colors.amber.shade900
                                            : (s.checkOutTime != null
                                                ? Colors.orange.shade900
                                                : colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                    if (s.isAutoCheckOut) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'تم إغلاق الانصراف تلقائياً بعد مرور 9 ساعات على بداية الوردية لعدم تسجيل الانصراف يدوياً',
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                          ),
                                          child: Text(
                                            'تلقائي (9 س)',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 5. Work Duration
                          Expanded(
                            flex: _colFlexDuration,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 15,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.formattedDuration,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 6. Status Badge
                          Expanded(
                            flex: _colFlexStatus,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _buildStatusBadge(s, colorScheme),
                              ),
                            ),
                          ),

                          // 7. Device & Distance
                          Expanded(
                            flex: _colFlexDevice,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (s.deviceInfo != null && s.deviceInfo!.isNotEmpty)
                                      Text(
                                        s.deviceInfo!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (s.distanceMeters != null) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            s.isInsideGeofence == true
                                                ? Icons.check_circle_outline_rounded
                                                : Icons.location_off_rounded,
                                            size: 11,
                                            color: s.isInsideGeofence == true
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${s.distanceMeters!.round()} م (${s.isInsideGeofence == true ? 'داخل النطاق' : 'خارج'})',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: s.isInsideGeofence == true
                                                  ? Colors.green.shade700
                                                  : Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 8. Actions (Edit & Details)
                          Expanded(
                            flex: _colFlexActions,
                            child: Align(
                              alignment: AlignmentDirectional.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TashilIconButton(
                                    icon: Icons.edit_calendar_rounded,
                                    size: 32,
                                    iconSize: 16,
                                    tooltip: 'تعديل توقيت الجلسة',
                                    onPressed: () => _showEditAttendanceDialog(s),
                                  ),
                                  const SizedBox(width: 4),
                                  TashilIconButton(
                                    icon: Icons.info_outline_rounded,
                                    size: 32,
                                    iconSize: 16,
                                    tooltip: 'عرض تفاصيل الجلسة',
                                    onPressed: () => _showSessionDetailsDialog(s),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );

          if (needsScroll) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: tableContent,
            );
          }
          return tableContent;
        },
      ),
    );
  }

  Widget _buildHeaderCell(
    String text, {
    required int flex,
    AlignmentDirectional alignment = AlignmentDirectional.centerStart,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Align(
          alignment: alignment,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // Mobile Cards List
  Widget _buildMobileCardsList(List<DelegateAttendanceSession> sessions, ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final s = sessions[index];
        final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(s.checkInTime);
        final inTimeStr = DateFormat('hh:mm a', 'ar').format(s.checkInTime);
        final outTimeStr = s.checkOutTime != null
            ? DateFormat('hh:mm a', 'ar').format(s.checkOutTime!)
            : 'لم يسجل انصراف';

        return Card(
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showSessionDetailsDialog(s),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      _buildStatusBadge(s, colorScheme),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.store_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(s.branchName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.login_rounded, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text('حضور: $inTimeStr', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              s.isAutoCheckOut ? Icons.auto_mode_rounded : Icons.logout_rounded,
                              size: 14,
                              color: s.isAutoCheckOut ? Colors.amber.shade800 : Colors.orange.shade800,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'انصراف: $outTimeStr',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (s.isAutoCheckOut) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  'تلقائي',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'مدة العمل: ${s.formattedDuration}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'تعديل التوقيت',
                            onPressed: () => _showEditAttendanceDialog(s),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.chevron_left_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(DelegateAttendanceSession s, ColorScheme colorScheme) {
    final bool isCompleted = s.checkOutTime != null;
    final bool isOngoing = s.isOngoing;

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData icon;
    final String label;

    if (s.isAutoCheckOut) {
      bgColor = Colors.amber.shade50;
      borderColor = Colors.amber.shade200;
      textColor = Colors.amber.shade900;
      icon = Icons.auto_mode_rounded;
      label = 'مكتمل (تلقائي)';
    } else if (isCompleted) {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      textColor = Colors.green.shade800;
      icon = Icons.check_circle_rounded;
      label = 'مكتمل الانصراف';
    } else if (isOngoing) {
      bgColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      textColor = Colors.blue.shade800;
      icon = Icons.timelapse_rounded;
      label = 'حاضر الآن';
    } else {
      bgColor = Colors.red.shade50;
      borderColor = Colors.red.shade200;
      textColor = Colors.red.shade800;
      icon = Icons.warning_amber_rounded;
      label = 'لم يسجل انصراف';
    }

    final badgeWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );

    if (!s.isManuallyAdjusted) {
      return badgeWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        badgeWidget,
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_rounded, size: 11, color: Colors.amber.shade900),
              const SizedBox(width: 3),
              Text(
                'مُعدّل إدارياً',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KpiItem {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
