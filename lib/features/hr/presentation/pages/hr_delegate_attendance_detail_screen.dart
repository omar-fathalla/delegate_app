import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/widgets/branch_name_label.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';
import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';

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
        now.difference(checkInTime) < kAttendanceAutoCloseAfter;
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

  /// True inside the web HR shell (TAS-145): the breadcrumb carries the
  /// title and the back button, so the page draws no app bar and shows its
  /// actions in a toolbar instead.
  final bool inShell;

  const HRDelegateAttendanceDetailScreen({
    super.key,
    required this.delegate,
    this.initialMonth,
    this.branchesByName,
    this.hrDelegate,
    this.inShell = false,
  });

  /// Tests swap in a fake Firestore for the reads.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;

  @override
  State<HRDelegateAttendanceDetailScreen> createState() =>
      _HRDelegateAttendanceDetailScreenState();
}

/// Opens «سجل الحضور والانصراف التفصيلي» for [delegate] (TAS-145).
///
/// Inside the wide web HR shell it is an inner page with the breadcrumb
/// «current page › delegate name»; elsewhere (mobile, narrow web) it is
/// pushed full screen with its own app bar, as before.
Future<void> openHrDelegateAttendanceDetail(
  BuildContext context, {
  required Delegate delegate,
  DateTime? initialMonth,
  Map<String, Branch>? branchesByName,
  Delegate? hrDelegate,
}) {
  return pushHrInnerPage<void>(
    context,
    title: delegate.fullName,
    maxWidth: HrInnerPageWidth.wide,
    builder: (_, inShell) => HRDelegateAttendanceDetailScreen(
      delegate: delegate,
      initialMonth: initialMonth,
      branchesByName: branchesByName,
      hrDelegate: hrDelegate,
      inShell: inShell,
    ),
  );
}

/// Reads a delegate's attendance logs, scoped to one company (TAS-120).
///
/// HR and other company staff may only read logs whose `companyId` (or
/// `companyUID`) is their own company (`canReadAttendance` in
/// firestore.rules). Firestore checks a query against the rules before it
/// runs, so a query on `delegateId`/`userId` alone is rejected with
/// permission-denied even when every matching log is in the company. The
/// `companyId` filter makes the query provable. Attendance writes always set
/// `companyId`.
///
/// Returns the merged docs (by id) from the `delegateId` and legacy `userId`
/// queries. An empty [companyId] leaves the query unscoped (global staff).
@visibleForTesting
Future<Map<String, Map<String, dynamic>>> fetchDelegateAttendanceDocs({
  required FirebaseFirestore firestore,
  required List<String> identifiers,
  required String companyId,
}) async {
  final ids = identifiers.take(30).toList();
  if (ids.isEmpty) return {};
  Query<Map<String, dynamic>> base = firestore.collection(
    kAttendanceCollection,
  );
  if (companyId.isNotEmpty) {
    base = base.where('companyId', isEqualTo: companyId);
  }
  final results = await Future.wait([
    base.where('delegateId', whereIn: ids).get(),
    // Legacy logs keyed by userId.
    base.where('userId', whereIn: ids).get(),
  ]);
  return {
    for (final snap in results)
      for (final doc in snap.docs) doc.id: doc.data(),
  };
}

/// Clear Arabic message for a failed attendance load. Never shows the raw
/// Firebase text (TAS-120).
@visibleForTesting
String hrAttendanceLoadErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية لعرض سجل حضور هذا المندوب.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'تعذر الاتصال بالخادم. تحقق من الاتصال بالإنترنت ثم أعد المحاولة.';
    }
  }
  return 'حدث خطأ أثناء تحميل سجل الحضور. يرجى المحاولة مرة أخرى.';
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

  // Layout-only: scroll state for the collapsing delegate header.
  final ScrollController _scrollController = ScrollController();
  bool _headerShrunk = false; // header card scaled down slightly
  bool _showCompactHeader = false; // header scrolled away -> photo + name in AppBar

  void _onScroll() {
    final o = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final shrunk = o > 24;
    final compact = o > 150;
    if (shrunk != _headerShrunk || compact != _showCompactHeader) {
      setState(() {
        _headerShrunk = shrunk;
        _showCompactHeader = compact;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final init = widget.initialMonth ?? DateTime.now();
    _selectedMonth = DateTime(init.year, init.month, 1);
    if (widget.branchesByName != null) {
      _branchesByName = Map.from(widget.branchesByName!);
    }
    _loadBranchesAndAttendance();
  }

  FirebaseFirestore get _db =>
      HRDelegateAttendanceDetailScreen.debugFirestore?.call() ??
      FirebaseFirestore.instance;

  /// The viewer's company. The screen is only opened from the HR shell, so
  /// this is the HR user's company; the delegate's company is a fallback.
  String get _scopeCompanyId {
    final hrCompany = widget.hrDelegate?.companyUID.trim() ?? '';
    return hrCompany.isNotEmpty
        ? hrCompany
        : widget.delegate.companyUID.trim();
  }

  void _showLoadError(Object e) {
    debugPrint('HRDelegateAttendanceDetailScreen load failed: $e');
    if (!mounted) return;
    setState(() {
      _errorMessage = hrAttendanceLoadErrorMessage(e);
      _isLoading = false;
    });
  }

  Future<void> _refreshLogs() async {
    try {
      await _fetchDelegateLogs();
    } catch (e) {
      _showLoadError(e);
    }
  }

  Future<void> _loadBranchesAndAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load branches if not provided
      if (_branchesByName.isEmpty) {
        final branchesSnap = await _db.collection('branches').get();
        final Map<String, Branch> bMap = {};
        for (final doc in branchesSnap.docs) {
          final b = BranchModel.fromFirestore(doc);
          registerBranchInLookupMap(bMap, b);
        }
        _branchesByName = bMap;
      }

      // 2. Fetch all attendance logs for this delegate across all history
      await _fetchDelegateLogs();
    } catch (e) {
      _showLoadError(e);
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

    // Company-scoped, merged and deduplicated by document ID.
    final rawDocs = await fetchDelegateAttendanceDocs(
      firestore: _db,
      identifiers: identifiers.toList(),
      companyId: _scopeCompanyId,
    );

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

      // Check for related checkout (prefer denormalized fields on check-in — fix2)
      String? checkOutDocId = checkInData['checkOutDocId']?.toString();
      Map<String, dynamic>? checkOutData;

      final relatedOut = checkOutsByRelatedId[checkInId];
      if (relatedOut != null) {
        checkOutDocId = relatedOut.key;
        checkOutData = relatedOut.value;
      } else if (checkOutDocId != null &&
          checkOutDocId.isNotEmpty &&
          checkOutsByRelatedId.values.any((e) => e.key == checkOutDocId)) {
        // rare: id known on check-in but not keyed by relatedCheckInId
        for (final entry in checkOutsByRelatedId.values) {
          if (entry.key == checkOutDocId) {
            checkOutData = entry.value;
            break;
          }
        }
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

      // Denormalized checkOutTime on the check-in doc (fix2).
      final stampedOut = checkInData['checkOutTime'];
      if (stampedOut is Timestamp) {
        checkOutTime = stampedOut.toDate();
      }
      final stampedLoc = checkInData['checkOutLocation'];
      if (stampedLoc is Map) {
        outLat = (stampedLoc['latitude'] as num?)?.toDouble();
        outLng = (stampedLoc['longitude'] as num?)?.toDouble();
      }

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

      bool isAutoCheckOut = checkOutData?['isAutoCheckOut'] == true ||
          checkInData['isAutoCheckOut'] == true;
      String? autoCheckOutReason = checkOutData?['autoCheckOutReason']?.toString() ??
          checkInData['autoCheckOutReason']?.toString();

      // قاعدة الإغلاق التلقائي: إغلاق الانصراف ديناميكياً إذا انقضت الوردية (11.5 ساعة) أو كان تاريخاً سابقاً
      if (checkOutTime == null) {
        final now = DateTime.now();
        final isPastDay = checkInTime.isBefore(DateTime(now.year, now.month, now.day));
        final isElapsedAutoClose = now.difference(checkInTime) >= kAttendanceAutoCloseAfter;
        if (isPastDay || isElapsedAutoClose) {
          checkOutTime = checkInTime.add(kAttendanceAutoCloseAfter);
          isAutoCheckOut = true;
          autoCheckOutReason = kAttendanceAutoCloseReasonAr;
        }
      }

      // Calculate distance to branch
      double? distance;
      bool? isInside;

      if (inLat != null && inLng != null && branchName != 'غير محدد') {
        final matchedBranch = lookupBranchForAttendanceLog(
          branchesByName: _branchesByName,
          log: checkInData,
          fallbackBranchName: branchName,
        );
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
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        ),
        builder: (ctx) => _SessionDetailsSheet(
          session: session,
          delegate: widget.delegate,
          isBottomSheet: true,
          onEdit: () => _showEditAttendanceDialog(session),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.pill)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: _SessionDetailsSheet(
              session: session,
              delegate: widget.delegate,
              isBottomSheet: false,
              onEdit: () => _showEditAttendanceDialog(session),
            ),
          ),
        ),
      );
    }
  }

  void _showEditAttendanceDialog(DelegateAttendanceSession session) {
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        ),
        builder: (ctx) => _EditAttendanceSheet(
          session: session,
          delegate: widget.delegate,
          hrDelegate: widget.hrDelegate,
          isBottomSheet: true,
          onSave: ({
            required newInTime,
            required newOutTime,
            required hasCheckOut,
            required reason,
            required notes,
          }) => _executeAttendanceAdjustment(
            session: session,
            newInTime: newInTime,
            newOutTime: newOutTime,
            hasCheckOut: hasCheckOut,
            reason: reason,
            notes: notes,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.pill)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: _EditAttendanceSheet(
              session: session,
              delegate: widget.delegate,
              hrDelegate: widget.hrDelegate,
              isBottomSheet: false,
              onSave: ({
                required newInTime,
                required newOutTime,
                required hasCheckOut,
                required reason,
                required notes,
              }) => _executeAttendanceAdjustment(
                session: session,
                newInTime: newInTime,
                newOutTime: newOutTime,
                hasCheckOut: hasCheckOut,
                reason: reason,
                notes: notes,
              ),
            ),
          ),
        ),
      );
    }
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

    final String delegateDisplayName = widget.delegate.fullName.trim();
    final String delegatePhone = widget.delegate.phoneNumber.trim();
    final String delegateCompany = widget.delegate.companyName.trim();
    final String? delegatePhoto = widget.delegate.personalPhotoUrl;

    batch.update(checkInRef, {
      'timestamp': Timestamp.fromDate(newInTime),
      'isManuallyAdjusted': true,
      'lastAdjustedBy': hrName,
      'lastAdjustedAt': FieldValue.serverTimestamp(),
      'adjustmentReason': reason,
      if (notes.isNotEmpty) 'adjustmentNotes': notes,
      // Denormalize checkout onto check-in (fix2) when HR sets/adjusts out time.
      if (hasCheckOut && newOutTime != null) 'checkOutTime': Timestamp.fromDate(newOutTime),
      if (!hasCheckOut) 'checkOutTime': FieldValue.delete(),
      // Fix3: backfill display fields from HR-known delegate profile when possible.
      if (delegateDisplayName.isNotEmpty) 'delegateName': delegateDisplayName,
      if (delegatePhone.isNotEmpty) 'phoneNumber': delegatePhone,
      if (delegateCompany.isNotEmpty) 'companyName': delegateCompany,
      if (delegatePhoto != null && delegatePhoto.trim().isNotEmpty)
        'personalPhotoURL': delegatePhoto.trim(),
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

    // Keep checkOutDocId denormalized on the check-in for marketing/HR (fix2).
    if (hasCheckOut && newOutTime != null && checkOutDocId.isNotEmpty) {
      batch.update(checkInRef, {'checkOutDocId': checkOutDocId});
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
          'قامت إدارة الموارد البشرية بتعديل توقيت جلسة حضورك في فرع "${BranchDisplayCache.instance.displayName(session.branchName)}" بتاريخ $dateStr. السبب: $reason.',
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
        SnackBar(
          content: Text(
            'تم تعديل توقيت جلسة الحضور بنجاح وتسجيل العملية في سجل التدقيق.',
          ),
          backgroundColor: HrStatusColors.of(context).success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateToAdjustments() {
    // Web shell (TAS-146): one «سجل تعديلات الحضور» page, the sidebar tab,
    // filtered to this delegate. Mobile keeps the full-screen push.
    if (widget.inShell && HrShellLink.canOpenAdjustments) {
      HrShellLink.openAdjustmentsFor(
        delegateUID: widget.delegate.uid,
        delegateName: widget.delegate.fullName,
      );
      return;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width > 768;

    final body = _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? HrEmptyState(
                  key: const Key('hr_attendance_detail_error'),
                  icon: Icons.error_outline_rounded,
                  title: 'تعذر تحميل سجل الحضور',
                  message: _errorMessage,
                  action: FilledButton.tonal(
                    onPressed: _loadBranchesAndAttendance,
                    child: const Text('إعادة المحاولة'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshLogs,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 24 : 12,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Delegate Profile Card
                        AnimatedScale(
                          scale: _headerShrunk ? 0.96 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedOpacity(
                            opacity: _showCompactHeader ? 0.4 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: _buildDelegateProfileHeader(colorScheme, isWide),
                          ),
                        ),
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
                );

    if (widget.inShell) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildShellToolbar(),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 0,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _showCompactHeader
              ? Row(
                  key: const ValueKey('compact'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppAvatar(
                      imageUrl: widget.delegate.personalPhotoUrl,
                      fallbackText: widget.delegate.fullName,
                      radius: 16,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.delegate.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                )
              : KeyedSubtree(
                  key: const ValueKey('full'),
                  child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isWide ? 'سجل الحضور والانصراف التفصيلي' : 'سجل حضور المندوب',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: HrFont.body,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.delegate.fullName,
              style: TextStyle(
                fontSize: HrFont.labelSmall,
                fontWeight: FontWeight.normal,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
                ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'سجل التعديلات الإدارية',
            onPressed: _navigateToAdjustments,
            icon: const Icon(Icons.history_edu_rounded),
          ),
          IconButton(
            tooltip: 'تصدير التقرير الشهري (CSV)',
            onPressed: _exportMonthlyReportToCSV,
            icon: const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  /// Actions of the page inside the web shell, where there is no app bar.
  Widget _buildShellToolbar() {
    return Padding(
      key: const Key('hr_attendance_detail_toolbar'),
      padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 0),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('hr_attendance_detail_open_edits'),
            onPressed: _navigateToAdjustments,
            icon: const Icon(Icons.history_edu_rounded, size: 18),
            label: const Text('سجل تعديلات الحضور'),
          ),
          OutlinedButton.icon(
            key: const Key('hr_attendance_detail_export'),
            onPressed: _exportMonthlyReportToCSV,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تصدير التقرير الشهري'),
          ),
        ],
      ),
    );
  }

  // --- 1. Delegate Profile Header ---
  Widget _buildDelegateProfileHeader(ColorScheme colorScheme, bool isWide) {
    final textTheme = Theme.of(context).textTheme;
    final infoLines = <Widget>[
      _buildInfoBadge(Icons.phone_rounded, widget.delegate.phoneNumber),
      _buildInfoBadge(Icons.badge_outlined, widget.delegate.nationalityID),
      if (widget.delegate.companyName.isNotEmpty)
        _buildInfoBadge(Icons.apartment_rounded, widget.delegate.companyName),
      if (widget.delegate.boundDeviceModel != null && widget.delegate.boundDeviceModel!.isNotEmpty)
        _buildInfoBadge(Icons.smartphone_rounded, widget.delegate.boundDeviceModel!),
    ];
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 20 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Start side (right in RTL): name + data lines.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.delegate.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (isWide)
                    Wrap(spacing: 16, runSpacing: 4, children: infoLines)
                  else
                    ...infoLines.map((w) => Padding(padding: const EdgeInsets.only(bottom: 3), child: w)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // End side (left in RTL): avatar, then actions, then role badge.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppAvatar(
                  imageUrl: widget.delegate.personalPhotoUrl,
                  fallbackText: widget.delegate.fullName,
                  radius: isWide ? 32 : 28,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TashilIconButton(
                      icon: Icons.call_rounded,
                      color: HrStatusColors.of(context).success,
                      size: isWide ? 36 : 32,
                      iconSize: isWide ? 18 : 16,
                      tooltip: 'اتصال هاتفي بالمندوب',
                      onPressed: () => _makePhoneCall(widget.delegate.phoneNumber),
                    ),
                    const SizedBox(width: 6),
                    TashilIconButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: Colors.teal.shade700,
                      size: isWide ? 36 : 32,
                      iconSize: isWide ? 18 : 16,
                      tooltip: 'مراسلة عبر واتساب',
                      onPressed: () => _openWhatsApp(widget.delegate.phoneNumber),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(HrRadius.chip),
                  ),
                  child: Text(
                    widget.delegate.role == UserRole.delegate ? 'مندوب / مروج' : 'مشرف',
                    style: TextStyle(
                      fontSize: HrFont.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
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
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  // --- 2. Month Selector Navigation Bar ---
  Widget _buildMonthSelectorBar(ColorScheme colorScheme, bool isWide) {
    final monthDisplay = DateFormat('MMMM yyyy', 'ar').format(_selectedMonth);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 8, vertical: isWide ? 10 : 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(HrRadius.card),
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
        children: [
          // Previous month (start side = right in RTL)
          if (isWide)
            FilledButton.tonalIcon(
              onPressed: _goToPreviousMonth,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
              ),
              icon: const Icon(Icons.chevron_right_rounded, size: 18, textDirection: TextDirection.ltr),
              label: const Text('الشهر السابق'),
            )
          else
            IconButton.filledTonal(
              tooltip: 'الشهر السابق',
              onPressed: _goToPreviousMonth,
              icon: const Icon(Icons.chevron_right_rounded, textDirection: TextDirection.ltr),
            ),

          // Current displayed month (+ jump to current month)
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_month_rounded, color: colorScheme.primary, size: isWide ? 22 : 20),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      monthDisplay,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: isWide ? 18 : 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (!_isCurrentMonth) ...[
                  const SizedBox(width: 4),
                  if (isWide)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.today_rounded, size: 16),
                      label: const Text('الشهر الحالي', style: TextStyle(fontSize: HrFont.labelSmall)),
                      onPressed: _goToCurrentMonth,
                    )
                  else
                    IconButton(
                      tooltip: 'الشهر الحالي',
                      visualDensity: VisualDensity.compact,
                      color: colorScheme.primary,
                      onPressed: _goToCurrentMonth,
                      icon: const Icon(Icons.today_rounded, size: 20),
                    ),
                ],
              ],
            ),
          ),

          // Next month (end side = left in RTL)
          if (isWide)
            FilledButton.tonalIcon(
              onPressed: _goToNextMonth,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
              ),
              label: const Text('الشهر التالي'),
              icon: const Icon(Icons.chevron_left_rounded, size: 18, textDirection: TextDirection.ltr),
            )
          else
            IconButton.filledTonal(
              tooltip: 'الشهر التالي',
              onPressed: _goToNextMonth,
              icon: const Icon(Icons.chevron_left_rounded, textDirection: TextDirection.ltr),
            ),
        ],
      ),
    );
  }

  // --- 3. Monthly Analytics KPI Cards (No horizontal scroll, 2x2 responsive grid on mobile) ---
  Widget _buildMonthlyKpiCards(ColorScheme colorScheme, bool isWide) {
    final kpis = [
      _KpiItem(
        title: 'أيام الحضور',
        value: '$_uniquePresentDaysCount يوم',
        subtitle: 'خلال هذا الشهر',
        icon: Icons.how_to_reg_rounded,
        color: HrStatusColors.of(context).success,
      ),
      _KpiItem(
        title: 'مرات الانصراف',
        value: '$_completedCheckOutsCount مرة',
        subtitle: 'جلسات مكتملة',
        icon: Icons.logout_rounded,
        color: Colors.indigo,
      ),
      _KpiItem(
        title: 'إجمالي الساعات',
        value: _formattedTotalWorkedHours,
        subtitle: 'وقت العمل الفعلي',
        icon: Icons.access_time_filled_rounded,
        color: colorScheme.primary,
      ),
      _KpiItem(
        title: 'متوسط الساعات',
        value: _formattedAverageDailyHours,
        subtitle: 'لكل يوم عمل',
        icon: Icons.speed_rounded,
        color: Colors.teal,
      ),
      _KpiItem(
        title: 'الفروع المزارة',
        value: '${_branchesInCurrentMonth.length} فرع',
        subtitle: _branchesInCurrentMonth.isEmpty ? 'لا فروع' : _branchesInCurrentMonth.take(2).map((b) => BranchDisplayCache.instance.displayName(b)).join(', '),
        icon: Icons.store_rounded,
        color: Colors.deepPurple,
      ),
    ];

    // One compact single-line row with the four stats (phone and wide).
    return Column(
      children: [
          _buildCompactStatsRow(kpis.take(4).toList(), colorScheme),
          if (_branchesInCurrentMonth.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card.outlined(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HrRadius.card),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                dense: true,
                visualDensity: VisualDensity.compact,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(Icons.storefront_rounded, size: 18, color: Colors.deepPurple.shade600),
                title: Text(
                  'الفروع المزارة (${_branchesInCurrentMonth.length})',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                children: [
                  for (int i = 0; i < _branchesInCurrentMonth.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.store_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BranchNameLabel(
                              branchName: _branchesInCurrentMonth.elementAt(i),
                              style: const TextStyle(fontSize: HrFont.body, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildChainChip(_branchesInCurrentMonth.elementAt(i), colorScheme),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
    );
  }

  /// Small chip with the branch's chain (organization) name; hidden if unknown.
  Widget _buildChainChip(
    String branchName,
    ColorScheme colorScheme, {
    EdgeInsetsGeometry margin = const EdgeInsetsDirectional.only(start: 8),
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: BranchDisplayCache.instance.version,
      builder: (context, _, child) {
        final chain = BranchDisplayCache.instance.organizationNameFor(branchName);
        if (chain.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: margin,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          constraints: const BoxConstraints(maxWidth: 120),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(HrRadius.chip),
          ),
          child: Text(
            chain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        );
      },
    );
  }

  /// Shortens the existing value strings for the compact row (display only).
  String _compactKpiValue(String v) => v
      .replaceAll(' ساعة و ', 'س ')
      .replaceAll(' دقيقة', 'د')
      .replaceAll(' ساعة/يوم', ' س/يوم')
      .replaceAll(' ساعة', 'س');

  Widget _buildCompactStatsRow(List<_KpiItem> items, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(height: 28, child: VerticalDivider(width: 8, color: colorScheme.outlineVariant)),
              Expanded(
                child: Tooltip(
                  message: '${items[i].title}: ${items[i].value}',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(items[i].icon, size: 14, color: items[i].color),
                          const SizedBox(width: 3),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _compactKpiValue(items[i].value),
                                maxLines: 1,
                                style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        items[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- 4. Filter Bar (Single Row: Branch Dropdown + Status Button Group + Compact Count Badge) ---
  /// Month sessions narrowed by the selected branch only (used for status counts).
  List<DelegateAttendanceSession> get _branchFilteredMonthlySessions {
    if (_selectedBranchFilter == 'all') return _monthlySessions;
    final sel = _selectedBranchFilter.toLowerCase().trim();
    return _monthlySessions.where((s) => s.branchName.toLowerCase().trim() == sel).toList();
  }

  Widget _buildFilterBar(ColorScheme colorScheme, bool isWide) {
    final branches = ['all', ..._branchesInCurrentMonth];
    if (!isWide) {
      // Phone: branch chip on its own line, the three status chips on a second line.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBranchFilterControl(branches, colorScheme),
          const SizedBox(height: 8),
          _buildStatusFilterControl(colorScheme),
        ],
      );
    }
    // Wide: one horizontally scrollable row.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: _buildBranchFilterControl(branches, colorScheme),
          ),
          const SizedBox(width: 8),
          _buildStatusFilterControl(colorScheme),
        ],
      ),
    );
  }

  Widget _buildBranchFilterControl(List<String> branches, ColorScheme colorScheme) {
    final selectedBranch = branches.contains(_selectedBranchFilter) ? _selectedBranchFilter : 'all';
    final label = selectedBranch == 'all'
        ? 'جميع الفروع (${_branchesInCurrentMonth.length})'
        : BranchDisplayCache.instance.displayName(selectedBranch);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(HrRadius.pill),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'تصفية حسب الفرع',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
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
                Expanded(
                  child: Text(
                    b == 'all' ? 'جميع الفروع (${_branchesInCurrentMonth.length})' : BranchDisplayCache.instance.displayName(b),
                    style: TextStyle(
                      fontSize: HrFont.body,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: HrFont.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterControl(ColorScheme colorScheme) {
    final base = _branchFilteredMonthlySessions;
    final completed = base.where((s) => s.checkOutTime != null).length;
    // Red only for truly unfinished sessions (present-now is not an error).
    final hasAlert = base.any(_isIncompleteSession);
    final options = <(String, String, int)>[
      ('all', 'الكل', base.length),
      ('completed', 'مكتمل', completed),
      ('incomplete', 'غير مكتمل', base.length - completed),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label, count) in options) ...[
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selected: _selectedStatusFilter == value,
            onSelected: (_) => setState(() => _selectedStatusFilter = value),
            selectedColor: value == 'incomplete' && hasAlert ? colorScheme.errorContainer : colorScheme.secondaryContainer,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: HrFont.labelMedium, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Badge(
                  label: Text('$count'),
                  backgroundColor: value == 'incomplete' && hasAlert ? colorScheme.error : colorScheme.primary,
                  textColor: value == 'incomplete' && hasAlert ? colorScheme.onError : colorScheme.onPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  // --- 5. Attendance History Section (Table View on Mobile & Web) ---
  Widget _buildHistorySection(ColorScheme colorScheme, bool isWide) {
    final sessions = _filteredMonthlySessions;

    if (sessions.isEmpty) {
      return Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.card),
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
                  fontSize: HrFont.titleMedium,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك التنقل للأشهر السابقة أو التالية باستخدام أزرار التنقل أعلاه.',
                style: TextStyle(
                  fontSize: HrFont.labelMedium,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return _buildAttendanceTable(sessions, colorScheme);
  }

  // Desktop & Mobile Table Column Flex Constants (Guaranteed 1:1 Header/Row Synchronization)
  static const int _colFlexDate = 15;        // التاريخ واليوم
  static const int _colFlexBranch = 20;      // الفرع
  static const int _colFlexInTime = 14;      // تسجيل الحضور
  static const int _colFlexOutTime = 18;     // تسجيل الانصراف
  static const int _colFlexDuration = 13;    // مدة العمل
  static const int _colFlexStatus = 15;      // الحالة
  static const int _colFlexActions = 10;     // الإجراءات

  // Table View (Responsive on Mobile with Smooth Horizontal Scroll & Direct on Desktop)
  Widget _buildAttendanceTable(List<DelegateAttendanceSession> sessions, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return _buildAttendanceDayCards(sessions, colorScheme);
        }
        return _buildAttendanceTableView(sessions, colorScheme);
      },
    );
  }

  // Compact/medium widths (<840dp): one Material 3 card per session instead of the wide table.
  Widget _buildAttendanceDayCards(List<DelegateAttendanceSession> sessions, ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) => _buildAttendanceDayCard(sessions[index], colorScheme),
    );
  }

  Widget _buildAttendanceDayCard(DelegateAttendanceSession s, ColorScheme colorScheme) {
    final dateStr = DateFormat('yyyy/MM/dd', 'en').format(s.checkInTime);
    final dayStr = DateFormat('EEEE', 'ar').format(s.checkInTime);
    final inTimeStr = DateFormat('hh:mm a', 'ar').format(s.checkInTime);
    final outTimeStr = s.checkOutTime != null ? DateFormat('hh:mm a', 'ar').format(s.checkOutTime!) : '-';
    final outColor = s.isAutoCheckOut
        ? Colors.deepPurple.shade900
        : (s.checkOutTime != null ? Colors.indigo.shade900 : colorScheme.onSurfaceVariant);
    final outIconColor = s.isAutoCheckOut
        ? Colors.deepPurple.shade700
        : (s.checkOutTime != null ? Colors.indigo.shade700 : colorScheme.error.withValues(alpha: 0.6));

    Widget metric(IconData icon, Color iconColor, String label, String value, Color valueColor) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 15, color: iconColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: HrFont.labelMedium, fontWeight: FontWeight.w600, color: valueColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final bool isAlert = _isIncompleteSession(s);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: isAlert ? colorScheme.error.withValues(alpha: 0.55) : colorScheme.outlineVariant,
        ),
      ),
      child: Container(
        decoration: isAlert
            ? BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: colorScheme.error, width: 4)),
              )
            : null,
        child: InkWell(
        onTap: () => _showSessionDetailsDialog(s),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date + weekday, status and actions
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(dayStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body)),
                  const SizedBox(width: 8),
                  Text(dateStr, style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant)),
                  const Spacer(),
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
              const SizedBox(height: 10),
              // Branch (full name, up to 2 lines, address underneath)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.storefront_rounded, size: 16, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BranchNameLabel(
                      branchName: s.branchName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: HrFont.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildChainChip(s.branchName, colorScheme),
                ],
              ),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: _buildStatusBadge(s, colorScheme)),
              const Divider(height: 20),
              // Check-in / check-out / duration
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metric(Icons.login_rounded, HrStatusColors.of(context).success, 'الحضور', inTimeStr, HrStatusColors.of(context).success),
                    metric(
                      s.isAutoCheckOut ? Icons.auto_mode_rounded : Icons.logout_rounded,
                      outIconColor,
                      s.isAutoCheckOut ? 'الانصراف (تلقائي)' : 'الانصراف',
                      outTimeStr,
                      outColor,
                    ),
                    metric(
                      Icons.schedule_rounded,
                      colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      'مدة العمل',
                      s.formattedDuration,
                      colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // Expanded widths (>=840dp): table with flexible, wrapping branch column.
  Widget _buildAttendanceTableView(List<DelegateAttendanceSession> sessions, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minTableWidth = 840.0;
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

                    final bool isAlert = _isIncompleteSession(s);
                    return Material(
                      color: isAlert
                          ? colorScheme.errorContainer.withValues(alpha: 0.18)
                          : (isEven
                              ? colorScheme.surface
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)),
                      shape: isAlert
                          ? BorderDirectional(start: BorderSide(color: colorScheme.error, width: 4))
                          : null,
                      child: InkWell(
                        onTap: () => _showSessionDetailsDialog(s),
                        hoverColor: colorScheme.primary.withValues(alpha: 0.04),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateStr,
                                          style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant),
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
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _buildChainChip(s.branchName, colorScheme,
                                                  margin: const EdgeInsets.only(bottom: 2)),
                                              BranchNameLabel(
                                                branchName: s.branchName,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: HrFont.body),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
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
                                        Icon(Icons.login_rounded, size: 16, color: HrStatusColors.of(context).success),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            inTimeStr,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: HrFont.body,
                                              color: HrStatusColors.of(context).success,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // 4. Check-out Time (Wrapped with generous flex to eliminate overflow, clear non-orange colors)
                              Expanded(
                                flex: _colFlexOutTime,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 12),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 3,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              s.isAutoCheckOut
                                                  ? Icons.auto_mode_rounded
                                                  : Icons.logout_rounded,
                                              size: 16,
                                              color: s.isAutoCheckOut
                                                  ? Colors.deepPurple.shade700
                                                  : (s.checkOutTime != null
                                                      ? Colors.indigo.shade700
                                                      : colorScheme.error.withValues(alpha: 0.6)),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              outTimeStr,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: HrFont.labelMedium,
                                                color: s.isAutoCheckOut
                                                    ? Colors.deepPurple.shade900
                                                    : (s.checkOutTime != null
                                                        ? Colors.indigo.shade900
                                                        : colorScheme.onSurfaceVariant),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (s.isAutoCheckOut)
                                          Tooltip(
                                            message: 'تم إغلاق الانصراف تلقائياً بعد مرور 11.5 ساعة على بداية الوردية لعدم تسجيل الانصراف يدوياً',
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurple.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                'تلقائي (11.5 س)',
                                                style: TextStyle(
                                                  fontSize: HrFont.labelSmall,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.deepPurple.shade800,
                                                ),
                                              ),
                                            ),
                                          ),
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
                                        Flexible(
                                          child: Text(
                                            s.formattedDuration,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: HrFont.labelMedium,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.onSurface,
                                            ),
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

                              // 7. Actions (Edit & Details)
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
                        ),
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
              fontSize: HrFont.labelMedium,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// No check-out recorded and not currently checked in (unfinished session).
  bool _isIncompleteSession(DelegateAttendanceSession s) =>
      s.checkOutTime == null && !s.isAutoCheckOut && !s.isOngoing;

  Widget _buildStatusBadge(DelegateAttendanceSession s, ColorScheme colorScheme) {
    final bool isCompleted = s.checkOutTime != null;
    final bool isOngoing = s.isOngoing;

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData icon;
    final String label;

    final status = HrStatusColors.of(context);
    final isWeb = WebRuntimePolicy.isWeb;

    if (isWeb && s.isAutoCheckOut) {
      // Web, approved status colors: auto check-out = warning.
      bgColor = status.warningContainer;
      borderColor = status.warning.withValues(alpha: 0.5);
      textColor = status.onWarningContainer;
      icon = Icons.auto_mode_rounded;
      label = 'مكتمل (تلقائي)';
    } else if (isWeb && isCompleted) {
      // Web, approved status colors: normal check-out = info.
      bgColor = status.infoContainer;
      borderColor = status.info.withValues(alpha: 0.5);
      textColor = status.onInfoContainer;
      icon = Icons.check_circle_rounded;
      label = 'مكتمل الانصراف';
    } else if (isWeb && isOngoing) {
      // Web, approved status colors: present = success.
      bgColor = status.successContainer;
      borderColor = status.success.withValues(alpha: 0.5);
      textColor = status.onSuccessContainer;
      icon = Icons.timelapse_rounded;
      label = 'حاضر الآن';
    } else if (s.isAutoCheckOut) {
      // Closed by the system: counted as complete, shown neutral (not an error).
      bgColor = colorScheme.secondaryContainer;
      borderColor = colorScheme.outlineVariant;
      textColor = colorScheme.onSecondaryContainer;
      icon = Icons.auto_mode_rounded;
      label = 'مكتمل (تلقائي)';
    } else if (isCompleted) {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      textColor = HrStatusColors.of(context).success;
      icon = Icons.check_circle_rounded;
      label = 'مكتمل الانصراف';
    } else if (isOngoing) {
      bgColor = colorScheme.primaryContainer;
      borderColor = colorScheme.primary.withValues(alpha: 0.4);
      textColor = colorScheme.onPrimaryContainer;
      icon = Icons.timelapse_rounded;
      label = 'حاضر الآن';
    } else {
      bgColor = colorScheme.errorContainer;
      borderColor = colorScheme.error.withValues(alpha: 0.5);
      textColor = colorScheme.onErrorContainer;
      icon = Icons.warning_amber_rounded;
      label = 'غير مكتمل - لم يسجل انصراف';
    }

    final badgeWidget = Tooltip(
      key: Key('hr_attendance_status_badge_${s.id}'),
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(HrRadius.card),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 5),
            // Shrinks with an ellipsis in a narrow column or with a wider font
            // instead of overflowing (TAS-184).
            Flexible(
              child: Text(
                label,
                key: const Key('hr_attendance_status_badge_label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HrFont.labelSmall,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
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
            color: isWeb
                ? colorScheme.surfaceContainerHigh
                : Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(HrRadius.chip),
            border: Border.all(
              color: isWeb
                  ? colorScheme.outlineVariant
                  : Colors.blueGrey.shade200,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 11,
                color: isWeb
                    ? colorScheme.onSurfaceVariant
                    : Colors.blueGrey.shade800,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  'مُعدّل إدارياً',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.bold,
                    color: isWeb
                        ? colorScheme.onSurfaceVariant
                        : Colors.blueGrey.shade800,
                  ),
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

// ============================================================================
// Modern Material 3 Attendance Time Adjustment Bottom Sheet / Dialog
// ============================================================================
class _EditAttendanceSheet extends StatefulWidget {
  final DelegateAttendanceSession session;
  final Delegate delegate;
  final Delegate? hrDelegate;
  final bool isBottomSheet;
  final Future<void> Function({
    required DateTime newInTime,
    required DateTime? newOutTime,
    required bool hasCheckOut,
    required String reason,
    required String notes,
  }) onSave;

  const _EditAttendanceSheet({
    required this.session,
    required this.delegate,
    this.hrDelegate,
    required this.isBottomSheet,
    required this.onSave,
  });

  @override
  State<_EditAttendanceSheet> createState() => _EditAttendanceSheetState();
}

class _EditAttendanceSheetState extends State<_EditAttendanceSheet> {
  static const List<String> _adjustmentReasons = [
    'نسيان تسجيل الانصراف من قِبل المندوب',
    'عطل في هاتف المندوب أو نفاد البطارية',
    'مشكلة تقنية في تطبيق المندوب أو الاتصال',
    'توجيه إداري بتمديد أو تعديل فترة العمل',
    'إذن مسبق وموافق عليه من المشرف الميداني',
    'تصحيح توقيت الحضور (حضور مبكر/متأخر معتمد)',
    'أخرى (يرجى التوضيح في الملاحظات الإدارية)',
  ];

  late TimeOfDay _selectedCheckInTime;
  late bool _hasCheckOut;
  late TimeOfDay _selectedCheckOutTime;
  late String _selectedReason;
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;
  String? _localValidationError;

  @override
  void initState() {
    super.initState();
    _selectedCheckInTime = TimeOfDay.fromDateTime(widget.session.checkInTime);
    _hasCheckOut = widget.session.checkOutTime != null;
    _selectedCheckOutTime = widget.session.checkOutTime != null
        ? TimeOfDay.fromDateTime(widget.session.checkOutTime!)
        : const TimeOfDay(hour: 17, minute: 0);
    _selectedReason = _adjustmentReasons.first;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'ص' : 'م';
    return '$h:$m $period';
  }

  IconData _getReasonIcon(String reason) {
    if (reason.contains('نسيان')) return Icons.timer_off_rounded;
    if (reason.contains('عطل') || reason.contains('البطارية')) return Icons.battery_alert_rounded;
    if (reason.contains('مشكلة تقنية') || reason.contains('الاتصال')) {
      return Icons.phonelink_erase_rounded;
    }
    if (reason.contains('توجيه إداري')) return Icons.assignment_turned_in_rounded;
    if (reason.contains('إذن مسبق')) return Icons.verified_user_rounded;
    if (reason.contains('تصحيح توقيت')) return Icons.edit_calendar_rounded;
    return Icons.more_horiz_rounded;
  }

  Future<void> _handleSave() async {
    final newInDateTime = DateTime(
      widget.session.checkInTime.year,
      widget.session.checkInTime.month,
      widget.session.checkInTime.day,
      _selectedCheckInTime.hour,
      _selectedCheckInTime.minute,
    );

    final newOutDateTime = _hasCheckOut
        ? DateTime(
            widget.session.checkInTime.year,
            widget.session.checkInTime.month,
            widget.session.checkInTime.day,
            _selectedCheckOutTime.hour,
            _selectedCheckOutTime.minute,
          )
        : null;

    final bool checkInChanged = newInDateTime != widget.session.checkInTime;
    final bool checkOutChanged = (widget.session.checkOutTime == null && _hasCheckOut) ||
        (widget.session.checkOutTime != null &&
            (!_hasCheckOut || newOutDateTime != widget.session.checkOutTime));

    if (!checkInChanged && !checkOutChanged) {
      setState(() {
        _localValidationError = 'لم تقم بتغيير وقت الحضور أو الانصراف.';
      });
      return;
    }

    if (_selectedReason.startsWith('أخرى') && _notesController.text.trim().isEmpty) {
      setState(() {
        _localValidationError = 'يرجى كتابة الملاحظات الإدارية عند اختيار سبب أخرى.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _localValidationError = null;
    });

    try {
      await widget.onSave(
        newInTime: newInDateTime,
        newOutTime: newOutDateTime,
        hasCheckOut: _hasCheckOut,
        reason: _selectedReason,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _localValidationError = 'حدث خطأ أثناء حفظ التعديل: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(widget.session.checkInTime);
    final mediaQuery = MediaQuery.of(context);

    final newInDateTime = DateTime(
      widget.session.checkInTime.year,
      widget.session.checkInTime.month,
      widget.session.checkInTime.day,
      _selectedCheckInTime.hour,
      _selectedCheckInTime.minute,
    );

    final newOutDateTime = _hasCheckOut
        ? DateTime(
            widget.session.checkInTime.year,
            widget.session.checkInTime.month,
            widget.session.checkInTime.day,
            _selectedCheckOutTime.hour,
            _selectedCheckOutTime.minute,
          )
        : null;

    final bool isNegativeDuration = _hasCheckOut &&
        newOutDateTime != null &&
        (newOutDateTime.isBefore(newInDateTime) || newOutDateTime.isAtSameMomentAs(newInDateTime));

    final Duration? newDuration = _hasCheckOut && !isNegativeDuration && newOutDateTime != null
        ? newOutDateTime.difference(newInDateTime)
        : null;

    String? durationDiffText;
    Color? durationDiffColor;
    if (newDuration != null) {
      final oldDurationMins = widget.session.duration?.inMinutes ?? 0;
      final newDurationMins = newDuration.inMinutes;
      final diffMins = newDurationMins - oldDurationMins;
      if (diffMins != 0) {
        final isPositive = diffMins > 0;
        final absMins = diffMins.abs();
        final h = absMins ~/ 60;
        final m = absMins % 60;
        final formattedDiff = h > 0 ? '$h س ${m > 0 ? "و $m د" : ""}' : '$m دقيقة';
        durationDiffText = '${isPositive ? "+" : "-"}$formattedDiff';
        durationDiffColor = isPositive ? HrStatusColors.of(context).success : HrStatusColors.of(context).danger;
      } else {
        durationDiffText = 'بدون تغيير في المدة';
        durationDiffColor = colorScheme.onSurfaceVariant;
      }
    }

    final bool canSave = !_isSaving && !isNegativeDuration;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Drag handle on mobile bottom sheet
        if (widget.isBottomSheet)
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

        // 2. Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(Icons.edit_calendar_rounded, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تعديل توقيت جلسة الحضور',
                      style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${widget.delegate.fullName} • $dateStr',
                      style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Branch Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BranchNameLabel(
                          branchName: widget.session.branchName,
                          prefix: 'الفرع: ',
                          style: const TextStyle(fontSize: HrFont.body, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Time Adjustment Section (Cohesive Dual Connected Cards)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section Header with Checkout Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'ضبط الأوقات',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _hasCheckOut ? 'تسجيل الانصراف' : 'بدون انصراف',
                                style: TextStyle(
                                  fontSize: HrFont.labelSmall,
                                  fontWeight: FontWeight.w600,
                                  color: _hasCheckOut
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Switch.adaptive(
                                value: _hasCheckOut,
                                activeTrackColor: colorScheme.primary.withValues(alpha: 0.5),
                                activeThumbColor: colorScheme.primary,
                                onChanged: _isSaving
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _hasCheckOut = val;
                                          _localValidationError = null;
                                        });
                                      },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Symmetrical Connected Dual-Tile Box (Button group style)
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(HrRadius.card),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            // 1. Check-in Time Tile
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _isSaving
                                      ? null
                                      : () async {
                                          final picked = await showTimePicker(
                                            context: context,
                                            initialTime: _selectedCheckInTime,
                                          );
                                          if (picked != null) {
                                            setState(() {
                                              _selectedCheckInTime = picked;
                                              _localValidationError = null;
                                            });
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.login_rounded,
                                              size: 15,
                                              color: HrStatusColors.of(context).success,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'وقت الحضور',
                                              style: TextStyle(
                                                fontSize: HrFont.labelSmall,
                                                fontWeight: FontWeight.bold,
                                                color: HrStatusColors.of(context).success,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(HrRadius.chip),
                                            border: Border.all(
                                              color: Colors.green.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                size: 14,
                                                color: HrStatusColors.of(context).success,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatTime(_selectedCheckInTime),
                                                style: TextStyle(
                                                  fontSize: HrFont.body,
                                                  fontWeight: FontWeight.bold,
                                                  color: HrStatusColors.of(context).success,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'انقر للتعديل',
                                          style: TextStyle(
                                            fontSize: HrFont.labelSmall,
                                            color: HrStatusColors.of(context).success.withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Vertical Divider
                            Container(
                              width: 1,
                              height: 64,
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),

                            // 2. Check-out Time Tile
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: (!_hasCheckOut || _isSaving)
                                      ? null
                                      : () async {
                                          final picked = await showTimePicker(
                                            context: context,
                                            initialTime: _selectedCheckOutTime,
                                          );
                                          if (picked != null) {
                                            setState(() {
                                              _selectedCheckOutTime = picked;
                                              _localValidationError = null;
                                            });
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.logout_rounded,
                                              size: 15,
                                              color: _hasCheckOut
                                                  ? Colors.indigo.shade700
                                                  : colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'وقت الانصراف',
                                              style: TextStyle(
                                                fontSize: HrFont.labelSmall,
                                                fontWeight: FontWeight.bold,
                                                color: _hasCheckOut
                                                    ? Colors.indigo.shade900
                                                    : colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _hasCheckOut
                                                ? Colors.indigo.withValues(alpha: 0.08)
                                                : colorScheme.surfaceContainerHighest.withValues(
                                                    alpha: 0.4,
                                                  ),
                                            borderRadius: BorderRadius.circular(HrRadius.chip),
                                            border: Border.all(
                                              color: _hasCheckOut
                                                  ? Colors.indigo.withValues(alpha: 0.25)
                                                  : colorScheme.outlineVariant.withValues(
                                                      alpha: 0.25,
                                                    ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                size: 14,
                                                color: _hasCheckOut
                                                    ? Colors.indigo.shade700
                                                    : colorScheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _hasCheckOut
                                                    ? _formatTime(_selectedCheckOutTime)
                                                    : 'غير مسجل',
                                                style: TextStyle(
                                                  fontSize: HrFont.body,
                                                  fontWeight: FontWeight.bold,
                                                  color: _hasCheckOut
                                                      ? Colors.indigo.shade900
                                                      : colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _hasCheckOut ? 'انقر للتعديل' : 'تفعيل من المفتاح',
                                          style: TextStyle(
                                            fontSize: HrFont.labelSmall,
                                            color: _hasCheckOut
                                                ? Colors.indigo.shade700
                                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                  ),
                ),
                const SizedBox(height: 12),

                // Duration Comparison Preview
                if (isNegativeDuration)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(HrRadius.card),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: HrStatusColors.of(context).danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تنبيه: وقت الانصراف يجب أن يكون بعد وقت الحضور!',
                            style: TextStyle(
                              fontSize: HrFont.labelMedium,
                              color: HrStatusColors.of(context).danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_hasCheckOut && newDuration != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                                    style: TextStyle(
                                      fontSize: HrFont.labelMedium,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '${newDuration.inHours} س و ${newDuration.inMinutes.remainder(60)} د',
                                    style: TextStyle(
                                      fontSize: HrFont.body,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              if (durationDiffText != null)
                                Text(
                                  'الفارق عن السابق: $durationDiffText (سابقاً: ${widget.session.formattedDuration})',
                                  style: TextStyle(
                                    fontSize: HrFont.labelSmall,
                                    fontWeight: FontWeight.w600,
                                    color: durationDiffColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),

                // Reason Dropdown (Material 3 Animated Popup Menu)
                const Text(
                  'سبب التعديل الإداري (إلزامي للتدقيق):',
                  style: TextStyle(fontSize: HrFont.body, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'تحديد سبب التعديل',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
                    elevation: 4,
                    color: colorScheme.surfaceContainerHigh,
                    initialValue: _selectedReason,
                    onSelected: _isSaving
                        ? null
                        : (val) {
                            setState(() {
                              _selectedReason = val;
                              _localValidationError = null;
                            });
                          },
                    itemBuilder: (ctx) => _adjustmentReasons.map((r) {
                      final isSelected = r == _selectedReason;
                      return PopupMenuItem<String>(
                        value: r,
                        child: Row(
                          children: [
                            Icon(
                              _getReasonIcon(r),
                              size: 18,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: HrFont.labelMedium,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(_getReasonIcon(_selectedReason), size: 18, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedReason,
                              style: TextStyle(
                                fontSize: HrFont.labelMedium,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Additional Notes (Optional)
                const Text(
                  'ملاحظات إضافية (اختياري):',
                  style: TextStyle(fontSize: HrFont.body, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  enabled: !_isSaving,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'أدخل أي تفاصيل إدارية توضيحية لتسجيلها في ملف التدقيق...',
                    hintStyle: TextStyle(
                      fontSize: HrFont.labelMedium,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),

                if (_localValidationError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(HrRadius.chip),
                      border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _localValidationError!,
                            style: TextStyle(
                              fontSize: HrFont.labelMedium,
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
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
        ),

        // 4. Pinned Bottom Action Button Group (Connected Dual Buttons)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(HrRadius.pill),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Cancel Button (إلغاء)
                Expanded(
                  flex: 2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSaving ? null : () => Navigator.pop(context),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'إلغاء',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 28,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // Save Button (حفظ التعديل)
                Expanded(
                  flex: 3,
                  child: Material(
                    color: canSave
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.12),
                    child: InkWell(
                      onTap: canSave ? _handleSave : null,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isSaving)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: canSave
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface.withValues(alpha: 0.38),
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _isSaving ? 'جارٍ الحفظ...' : 'حفظ التعديل',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: canSave
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface.withValues(alpha: 0.38),
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
        ),
      ],
    );

    if (widget.isBottomSheet) {
      final double sheetHeight = mediaQuery.size.height * 0.82;
      return SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: content,
        ),
      );
    }

    return content;
  }
}

// ============================================================================
// Modern Material 3 Attendance Session Details Bottom Sheet / Dialog
// ============================================================================
class _SessionDetailsSheet extends StatelessWidget {
  final DelegateAttendanceSession session;
  final Delegate delegate;
  final bool isBottomSheet;
  final VoidCallback onEdit;

  const _SessionDetailsSheet({
    required this.session,
    required this.delegate,
    required this.isBottomSheet,
    required this.onEdit,
  });

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: HrFont.labelMedium,
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
    final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(session.checkInTime);
    final inTimeStr = DateFormat('hh:mm:ss a', 'ar').format(session.checkInTime);
    final outTimeStr = session.checkOutTime != null
        ? (session.isAutoCheckOut
            ? '${DateFormat('hh:mm:ss a', 'ar').format(session.checkOutTime!)} (إغلاق تلقائي)'
            : DateFormat('hh:mm:ss a', 'ar').format(session.checkOutTime!))
        : 'لم يتم تسجيل انصراف';

    final mediaQuery = MediaQuery.of(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Drag handle on mobile bottom sheet
        if (isBottomSheet)
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

        // 2. Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تفاصيل جلسة الحضور',
                      style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${delegate.fullName} • $dateStr',
                      style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session.isAutoCheckOut) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(HrRadius.card),
                      border: Border.all(color: Colors.deepPurple.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_mode_rounded, size: 18, color: Colors.deepPurple.shade900),
                            const SizedBox(width: 8),
                            Text(
                              'تم إغلاق الانصراف تلقائياً (نظام الـ 11.5 ساعة)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: HrFont.body,
                                color: Colors.deepPurple.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          session.autoCheckOutReason ??
                              'تم إغلاق الجلسة أوتوماتيكياً لاكتمال مدة الشفت (11.5 ساعة) دون تسجيل انصراف يدوي من المندوب.',
                          style: TextStyle(fontSize: HrFont.labelMedium, color: Colors.deepPurple.shade900),
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
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(HrRadius.card),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 18, color: Colors.blueGrey.shade900),
                            const SizedBox(width: 8),
                            Text(
                              'تم تعديل هذه الجلسة إدارياً',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: HrFont.body,
                                color: Colors.blueGrey.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'المسؤول: ${session.lastAdjustedBy ?? "إدارة الموارد البشرية"}',
                          style: TextStyle(fontSize: HrFont.labelMedium, color: Colors.blueGrey.shade900),
                        ),
                        if (session.adjustmentReason != null && session.adjustmentReason!.isNotEmpty)
                          Text(
                            'السبب: ${session.adjustmentReason}',
                            style: TextStyle(fontSize: HrFont.labelMedium, color: Colors.blueGrey.shade900),
                          ),
                        if (session.lastAdjustedAt != null)
                          Text(
                            'تاريخ التعديل: ${DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(session.lastAdjustedAt!)}',
                            style: TextStyle(fontSize: HrFont.labelSmall, color: Colors.blueGrey.shade700),
                          ),
                      ],
                    ),
                  ),
                ],
                _buildDetailRow(context, Icons.store_rounded, 'الفرع', BranchDisplayCache.instance.displayName(session.branchName)),
                const Divider(height: 16),
                _buildDetailRow(
                  context,
                  Icons.login_rounded,
                  'وقت الحضور الدقيق',
                  inTimeStr,
                  valueColor: HrStatusColors.of(context).success,
                ),
                if (session.latitude != null && session.longitude != null)
                  _buildDetailRow(
                    context,
                    Icons.location_on_outlined,
                    'إحداثيات الحضور',
                    '${session.latitude!.toStringAsFixed(6)}, ${session.longitude!.toStringAsFixed(6)}',
                  ),
                if (session.deviceInfo != null)
                  _buildDetailRow(context, Icons.smartphone_rounded, 'جهاز الحضور', session.deviceInfo!),
                const Divider(height: 16),
                _buildDetailRow(
                  context,
                  Icons.logout_rounded,
                  'وقت الانصراف الدقيق',
                  outTimeStr,
                  valueColor: session.checkOutTime != null ? Colors.indigo.shade800 : colorScheme.error,
                ),
                if (session.checkOutLatitude != null && session.checkOutLongitude != null)
                  _buildDetailRow(
                    context,
                    Icons.location_on_outlined,
                    'إحداثيات الانصراف',
                    '${session.checkOutLatitude!.toStringAsFixed(6)}, ${session.checkOutLongitude!.toStringAsFixed(6)}',
                  ),
                if (session.checkOutDeviceInfo != null)
                  _buildDetailRow(context, Icons.smartphone_rounded, 'جهاز الانصراف', session.checkOutDeviceInfo!),
                const Divider(height: 16),
                _buildDetailRow(
                  context,
                  Icons.timer_outlined,
                  'إجمالي مدة العمل',
                  session.formattedDuration,
                  valueColor: colorScheme.primary,
                ),
                if (session.distanceMeters != null)
                  _buildDetailRow(
                    context,
                    Icons.radar_rounded,
                    'المسافة من الفرع',
                    '${session.distanceMeters!.round()} متر (${session.isInsideGeofence == true ? 'داخل النطاق الجغرافي' : 'خارج النطاق الجغرافي'})',
                    valueColor: session.isInsideGeofence == true ? HrStatusColors.of(context).success : HrStatusColors.of(context).danger,
                  ),
              ],
            ),
          ),
        ),

        // 4. Pinned Bottom Action Button Group (Connected Dual Buttons)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(HrRadius.pill),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Close Button (إغلاق)
                Expanded(
                  flex: 2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'إغلاق',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 28,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // Edit Time Button (تعديل التوقيت)
                Expanded(
                  flex: 3,
                  child: Material(
                    color: colorScheme.primary,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        onEdit();
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_calendar_rounded, size: 18, color: colorScheme.onPrimary),
                            const SizedBox(width: 6),
                            Text(
                              'تعديل التوقيت',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
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
        ),
      ],
    );

    if (isBottomSheet) {
      final double sheetHeight = mediaQuery.size.height * 0.78;
      return SizedBox(
        height: sheetHeight,
        child: content,
      );
    }

    return content;
  }
}


