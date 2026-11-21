import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/widgets/branch_name_label.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';
import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';

/// Model representing a delegate's attendance record on a specific date for HR
class HRAttendanceRecord {
  final Delegate delegate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? branchName;
  final double? latitude;
  final double? longitude;
  final String? deviceInfo;
  final String? deviceUuid;
  final double? distanceMeters;
  final bool? isInsideGeofence;
  final bool isMockLocation;
  final bool isVpnUsed;
  final bool hasSecurityViolation;
  final String? violationReason;
  final int trustScore; // 0 to 100
  final String integrityStatus; // 'trusted' (🟢), 'warning' (🟡), 'violation' (🔴), 'none'
  final String? ipAddress;
  final String? ipIsp;
  final bool isOnApprovedLeave;
  final String? leaveReason;
  final String? leaveType;
  final bool isAutoCheckOut;
  final String? autoCheckOutReason;

  const HRAttendanceRecord({
    required this.delegate,
    this.checkInTime,
    this.checkOutTime,
    this.branchName,
    this.latitude,
    this.longitude,
    this.deviceInfo,
    this.deviceUuid,
    this.distanceMeters,
    this.isInsideGeofence,
    this.isMockLocation = false,
    this.isVpnUsed = false,
    this.hasSecurityViolation = false,
    this.violationReason,
    this.trustScore = 100,
    this.integrityStatus = 'none',
    this.ipAddress,
    this.ipIsp,
    this.isOnApprovedLeave = false,
    this.leaveReason,
    this.leaveType,
    this.isAutoCheckOut = false,
    this.autoCheckOutReason,
  });

  bool get isPresent => checkInTime != null && checkOutTime == null && !isAutoCheckOut;
  bool get isDeparted => checkInTime != null && (checkOutTime != null || isAutoCheckOut);
  bool get isAbsent => checkInTime == null;
  bool get isOnLeave => isAbsent && isOnApprovedLeave;

  String get formattedLeaveType {
    switch (leaveType) {
      case 'annual':
        return 'إجازة اعتيادية';
      case 'sick':
        return 'إجازة مرضية';
      case 'emergency':
        return 'إجازة عارضة';
      case 'delay':
        return 'عذر تأخير';
      case 'absence':
        return 'عذر غياب';
      default:
        return 'إجازة معتمدة';
    }
  }

  /// صافي مدة العمل المحسوبة
  Duration? get duration {
    if (checkInTime == null) return null;
    if (checkOutTime != null) {
      return checkOutTime!.difference(checkInTime!);
    }
    if (isAutoCheckOut) {
      return kAttendanceAutoCloseAfter;
    }
    // إذا كان المندوب على رأس العمل اليوم ولم ينصرف بعد
    final now = DateTime.now();
    if (checkInTime!.year == now.year &&
        checkInTime!.month == now.month &&
        checkInTime!.day == now.day) {
      return now.difference(checkInTime!);
    }
    return null;
  }

  /// صياغة نصية مفهومة لصافي ساعات العمل
  String get formattedDuration {
    if (checkInTime == null) return '-';
    if (checkOutTime == null && !isAutoCheckOut) {
      final now = DateTime.now();
      final isToday = checkInTime!.year == now.year &&
          checkInTime!.month == now.month &&
          checkInTime!.day == now.day;
      if (isToday) {
        final d = now.difference(checkInTime!);
        final hours = d.inHours;
        final minutes = d.inMinutes.remainder(60);
        if (hours > 0 && minutes > 0) {
          return '$hours س و $minutes د';
        } else if (hours > 0) {
          return '$hours س';
        } else {
          return '$minutes د';
        }
      }
      return 'لم يسجل انصراف';
    }
    final effectiveOut = checkOutTime ?? checkInTime!.add(kAttendanceAutoCloseAfter);
    final d = effectiveOut.difference(checkInTime!);
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

  /// مستوى الأمان ومطابقة النطاق الجغرافي للصيدلية/الفرع
  /// Returns: 'safe' (داخل النطاق/آمن), 'warning' (خارج النطاق/تحذير), 'violation' (مخالفة احتيال), 'unknown' (غير محدد)
  String get safetyLevel {
    if (checkInTime == null) return 'unknown';
    if (isMockLocation || hasSecurityViolation) return 'violation';
    if (isInsideGeofence == true && (distanceMeters == null || distanceMeters! <= 50)) {
      return 'safe';
    }
    if (isInsideGeofence == false || (distanceMeters != null && distanceMeters! > 50)) {
      return 'warning';
    }
    return 'safe';
  }
}

/// Read-only snapshot of the attendance tab's existing data and filters.
class HRAttendanceViewData {
  final bool isLoading;
  final String? errorMessage;
  final DateTime selectedDate;
  final bool isToday;
  final String statusFilter; // 'all','present','departed','absent','violation','leave'
  final String selectedChain; // 'all' or chain
  final String selectedBranch; // 'all' or branch
  final Set<String> chains;
  final Set<String> branches;
  final List<HRAttendanceRecord> records; // already filtered
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onChainChanged;
  final ValueChanged<String> onBranchChanged;
  final Future<void> Function() onRefresh;

  /// Every company delegate's record for [selectedDate], before filters.
  final List<HRAttendanceRecord> allRecords;
  final Map<String, Branch> branchesByName;

  /// Reloads delegates, branches and attendance and clears [errorMessage].
  final Future<void> Function()? onReload;

  const HRAttendanceViewData({
    required this.isLoading,
    required this.errorMessage,
    required this.selectedDate,
    required this.isToday,
    required this.statusFilter,
    required this.selectedChain,
    required this.selectedBranch,
    required this.chains,
    required this.branches,
    required this.records,
    required this.searchController,
    required this.onSearchChanged,
    required this.onDateChanged,
    required this.onStatusChanged,
    required this.onChainChanged,
    required this.onBranchChanged,
    required this.onRefresh,
    this.allRecords = const [],
    this.branchesByName = const {},
    this.onReload,
  });
}

/// Cards view grid (TAS-147). Above [kHrAttendanceCardsGridMinWidth] the
/// cards sit in a grid with a fixed column count; below it they stack in a
/// list (mobile keeps its list).
const double kHrAttendanceCardsGridMinWidth = 750;

/// Narrowest a card may get in the grid before a column is dropped.
const double kHrAttendanceCardMinWidth = 360;

/// Fixed card height in the grid.
const double kHrAttendanceCardHeight = 235;

/// Gap between grid cells, both ways.
const double kHrAttendanceCardsGridSpacing = 12;

/// Horizontal padding around the grid.
const double kHrAttendanceCardsGridPadding = 16;

/// Most columns the cards grid uses on very wide screens.
const int kHrAttendanceCardsMaxColumns = 4;

/// Column count for the cards grid in [contentWidth] (width inside the
/// grid padding): as many columns of at least [kHrAttendanceCardMinWidth]
/// as fit, between 1 and [kHrAttendanceCardsMaxColumns].
int hrAttendanceCardColumns(double contentWidth) {
  final fit = ((contentWidth + kHrAttendanceCardsGridSpacing) /
          (kHrAttendanceCardMinWidth + kHrAttendanceCardsGridSpacing))
      .floor();
  return fit.clamp(1, kHrAttendanceCardsMaxColumns);
}

class HRAttendanceTab extends StatefulWidget {
  final Delegate hrDelegate;
  final ValueChanged<int>? onNavigateToTab;

  /// Optional read-only view hook (web-only desktop table). When null
  /// (mobile), the tab renders exactly as before.
  final Widget Function(BuildContext context, HRAttendanceViewData data)?
      viewBuilder;

  const HRAttendanceTab({
    super.key,
    required this.hrDelegate,
    this.onNavigateToTab,
    this.viewBuilder,
  });

  @override
  State<HRAttendanceTab> createState() => _HRAttendanceTabState();
}

class _HRAttendanceTabState extends State<HRAttendanceTab> {
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  ScrollController? _horizontalTableScrollController;
  ScrollController? _verticalTableScrollController;

  ScrollController get _hScrollCtrl =>
      _horizontalTableScrollController ??= ScrollController();

  ScrollController get _vScrollCtrl =>
      _verticalTableScrollController ??= ScrollController();

  String _statusFilter = 'all'; // 'all', 'present', 'departed', 'absent', 'violation', 'leave'
  String _selectedChain = 'all';
  String _selectedBranch = 'all';
  bool _isTableView = true; // Table view is the primary default per user specification

  bool _isLoading = true;
  String? _errorMessage;

  List<Delegate> _companyDelegates = [];
  Map<String, Branch> _branchesByName = {};
  List<HRAttendanceRecord> _records = [];
  Set<String> _availableBranches = {};
  Set<String> _availableChains = {};

  Set<String> get _cascadingAvailableBranches {
    if (_selectedChain == 'all') {
      return _availableBranches;
    }
    final matchingBranches = <String>{};
    for (final bName in _availableBranches) {
      final branchObj = _branchesByName[bName.trim().toLowerCase()];
      if (branchObj != null && branchObj.organizationName != null) {
        if (branchObj.organizationName!.trim() == _selectedChain.trim()) {
          matchingBranches.add(bName);
          continue;
        }
      }
      final hasRecordInChain = _records.any((r) =>
          r.branchName == bName &&
          (r.delegate.organizationName == _selectedChain ||
              r.delegate.allOrganizationNames.contains(_selectedChain)));
      if (hasRecordInChain) {
        matchingBranches.add(bName);
      }
    }
    return matchingBranches;
  }

  void _populateAvailableChains() {
    final Set<String> chains = {};
    // 1. From HR / Supervisor delegate
    for (final org in widget.hrDelegate.allOrganizationNames) {
      if (org.trim().isNotEmpty) chains.add(org.trim());
    }
    if (widget.hrDelegate.organizationName.trim().isNotEmpty) {
      chains.add(widget.hrDelegate.organizationName.trim());
    }
    // 2. From company delegates (e.g. Omar Ahmed Fathalla in 'جملة ماركت' and 'fathalla market')
    for (final d in _companyDelegates) {
      if (d.organizationName.trim().isNotEmpty) {
        chains.add(d.organizationName.trim());
      }
      for (final org in d.allOrganizationNames) {
        if (org.trim().isNotEmpty) {
          chains.add(org.trim());
        }
      }
    }
    // 3. From attendance records
    for (final r in _records) {
      if (r.delegate.organizationName.trim().isNotEmpty) {
        chains.add(r.delegate.organizationName.trim());
      }
      for (final org in r.delegate.allOrganizationNames) {
        if (org.trim().isNotEmpty) {
          chains.add(org.trim());
        }
      }
    }
    _availableChains = chains;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalTableScrollController?.dispose();
    _verticalTableScrollController?.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load branches to calculate geofence distances accurately
      final branchesSnap =
          await FirebaseFirestore.instance.collection('branches').get();
      BranchDisplayCache.instance.registerSnapshot(branchesSnap);
      final Map<String, Branch> branchesMap = {};
      for (final doc in branchesSnap.docs) {
        final b = BranchModel.fromFirestore(doc);
        registerBranchInLookupMap(branchesMap, b);
      }
      _branchesByName = branchesMap;

      // 2. Load company delegates across all organizations where the company has delegates
      final delegatesResult = await di.sl<GetCompanyDelegates>()(
        GetCompanyDelegatesParams(
          organizationUID: widget.hrDelegate.companyUID.isNotEmpty
              ? ''
              : widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );

      delegatesResult.fold(
        (failure) {
          _errorMessage = failure.message;
        },
        (page) {
          _companyDelegates = page.delegates;
        },
      );

      _populateAvailableChains();

      await _fetchAttendanceForSelectedDate();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء تحميل البيانات: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAttendanceForSelectedDate() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        0,
        0,
        0,
      );
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      // Query attendance logs for this company
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection(kAttendanceCollection)
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID);

      final snapshot = await query.get();

      // Query security_audit_logs for this company to cross-reference anti-fraud violations
      final Map<String, List<Map<String, dynamic>>> auditLogsByDelegate = {};
      try {
        Query<Map<String, dynamic>> auditQuery = FirebaseFirestore.instance
            .collection('security_audit_logs')
            .where('companyUID', isEqualTo: widget.hrDelegate.companyUID);

        final auditSnapshot = await auditQuery.get();
        for (final doc in auditSnapshot.docs) {
          final data = doc.data();
          final delegateUid = (data['delegateUid'] ?? '').toString();
          if (delegateUid.isEmpty) continue;

          DateTime? auditDate;
          final ts = data['timestamp'];
          if (ts is Timestamp) {
            auditDate = ts.toDate();
          } else if (data['realTimestamp'] != null) {
            auditDate = DateTime.tryParse(data['realTimestamp'].toString());
          } else if (data['createdAt'] != null) {
            auditDate = DateTime.tryParse(data['createdAt'].toString());
          }

          if (auditDate != null) {
            if (auditDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
                auditDate.isBefore(endOfDay.add(const Duration(seconds: 1)))) {
              auditLogsByDelegate.putIfAbsent(delegateUid, () => []).add(data);
            }
          } else if (data['status'] == 'pending_review') {
            auditLogsByDelegate.putIfAbsent(delegateUid, () => []).add(data);
          }
        }
      } catch (e) {
        debugPrint('HR: Error loading security audit logs: $e');
      }

      // Query approved leave requests for this company to cross-reference approved absences
      final Map<String, Map<String, dynamic>> activeLeavesByDelegate = {};
      try {
        Query<Map<String, dynamic>> leaveQuery = FirebaseFirestore.instance
            .collection('leave_requests')
            .where('companyUID', isEqualTo: widget.hrDelegate.companyUID)
            .where('status', isEqualTo: 'approved');

        final leaveSnapshot = await leaveQuery.get();

        // Map active approved leaves for the selected date by delegate UID
        final selectedCal = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        for (final doc in leaveSnapshot.docs) {
          final data = doc.data();
          final startTs = data['startDate'];
          final endTs = data['endDate'];
          if (startTs is Timestamp) {
            final start = startTs.toDate();
            final end = endTs is Timestamp ? endTs.toDate() : start;
            final startCal = DateTime(start.year, start.month, start.day);
            final endCal = DateTime(end.year, end.month, end.day, 23, 59, 59);
            if (!selectedCal.isBefore(startCal) && !selectedCal.isAfter(endCal)) {
              final delId = (data['delegateUid'] ?? data['delegateUID'] ?? '').toString();
              if (delId.isNotEmpty) {
                activeLeavesByDelegate[delId] = data;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('HR: Error loading leave requests: $e');
      }

      // Group logs by delegate ID
      final Map<String, List<Map<String, dynamic>>> logsByDelegate = {};
      final Set<String> branchNames = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          final date = ts.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) {
            continue;
          }
        }

        final delegateId =
            (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delegateId.isNotEmpty) {
          logsByDelegate.putIfAbsent(delegateId, () => []).add(data);
        }

        final bName = (data['branchName'] ?? '').toString().trim();
        if (bName.isNotEmpty) {
          branchNames.add(bName);
        }
      }

      // Build attendance records for each delegate
      final List<HRAttendanceRecord> list = [];

      for (final d in _companyDelegates) {
        final logs = logsByDelegate[d.uid] ?? [];
        final auditLogs = auditLogsByDelegate[d.uid] ?? [];
        final leaveData = activeLeavesByDelegate[d.uid];
        final isOnLeave = leaveData != null;
        final leaveReason = leaveData?['reason']?.toString();
        final leaveType = leaveData?['type']?.toString() ?? leaveData?['leaveType']?.toString();
        DateTime? checkIn;
        DateTime? checkOut;
        String? branch;
        double? lat;
        double? lng;
        String? device;
        String? deviceUuid;
        String? ipAddress;
        String? ipIsp;
        bool isMockLocation = false;
        bool isVpnUsed = false;
        bool isAutoCheckOut = false;
        String? autoCheckOutReason;

        for (final log in logs) {
          final type = (log['type'] ?? '').toString();
          final ts = log['timestamp'];
          DateTime? logTime;
          if (ts is Timestamp) logTime = ts.toDate();

          if (type == 'check_in') {
            if (checkIn == null ||
                (logTime != null && logTime.isBefore(checkIn))) {
              checkIn = logTime;
              branch = log['branchName']?.toString();
              device = log['deviceInfo']?.toString();
              deviceUuid = log['deviceUuid']?.toString() ??
                  log['uuid']?.toString() ??
                  log['deviceId']?.toString();
              ipAddress = log['ipAddress']?.toString() ?? log['ip']?.toString();
              ipIsp = log['isp']?.toString() ?? log['networkIsp']?.toString();

              if (log['isMockLocation'] == true ||
                  log['isMocked'] == true ||
                  log['mockLocation'] == true) {
                isMockLocation = true;
              }
              if (log['isVpnUsed'] == true ||
                  log['isVpn'] == true ||
                  log['vpn'] == true) {
                isVpnUsed = true;
              }

              final loc = log['location'];
              if (loc is GeoPoint) {
                lat = loc.latitude;
                lng = loc.longitude;
              } else if (loc is Map) {
                lat = (loc['latitude'] as num?)?.toDouble() ??
                    (loc['lat'] as num?)?.toDouble() ??
                    double.tryParse(loc['latitude']?.toString() ?? '') ??
                    double.tryParse(loc['lat']?.toString() ?? '');
                lng = (loc['longitude'] as num?)?.toDouble() ??
                    (loc['lng'] as num?)?.toDouble() ??
                    double.tryParse(loc['longitude']?.toString() ?? '') ??
                    double.tryParse(loc['lng']?.toString() ?? '');
              }
              lat ??= (log['latitude'] as num?)?.toDouble() ??
                  (log['lat'] as num?)?.toDouble() ??
                  double.tryParse(log['latitude']?.toString() ?? '');
              lng ??= (log['longitude'] as num?)?.toDouble() ??
                  (log['lng'] as num?)?.toDouble() ??
                  double.tryParse(log['longitude']?.toString() ?? '');
            }
          } else if (type == 'check_out') {
            if (checkOut == null ||
                (logTime != null && logTime.isAfter(checkOut))) {
              checkOut = logTime;
              if (log['isAutoCheckOut'] == true) {
                isAutoCheckOut = true;
                autoCheckOutReason = log['autoCheckOutReason']?.toString();
              }
            }
          }
        }

        // قاعدة الإغلاق التلقائي: إغلاق الانصراف ديناميكياً إذا انقضت الوردية (11.5 ساعة) أو كان تاريخاً سابقاً
        if (checkIn != null && checkOut == null) {
          final now = DateTime.now();
          final isPastDate = _selectedDate.isBefore(DateTime(now.year, now.month, now.day));
          final isElapsedAutoClose = now.difference(checkIn) >= kAttendanceAutoCloseAfter;

          if (isPastDate || isElapsedAutoClose) {
            checkOut = checkIn.add(kAttendanceAutoCloseAfter);
            isAutoCheckOut = true;
            autoCheckOutReason = kAttendanceAutoCloseReasonAr;
          }
        }

        // Fallback scan across all logs of the day if coordinates weren't in the earliest check-in
        if (lat == null || lng == null) {
          for (final log in logs) {
            final loc = log['location'];
            if (loc is GeoPoint) {
              lat ??= loc.latitude;
              lng ??= loc.longitude;
            } else if (loc is Map) {
              lat ??= (loc['latitude'] as num?)?.toDouble() ??
                  (loc['lat'] as num?)?.toDouble() ??
                  double.tryParse(loc['latitude']?.toString() ?? '');
              lng ??= (loc['longitude'] as num?)?.toDouble() ??
                  (loc['lng'] as num?)?.toDouble() ??
                  double.tryParse(loc['longitude']?.toString() ?? '');
            }
            lat ??= (log['latitude'] as num?)?.toDouble() ??
                (log['lat'] as num?)?.toDouble() ??
                double.tryParse(log['latitude']?.toString() ?? '');
            lng ??= (log['longitude'] as num?)?.toDouble() ??
                (log['lng'] as num?)?.toDouble() ??
                double.tryParse(log['longitude']?.toString() ?? '');
            if (lat != null && lng != null) break;
          }
        }

        // Fallback branch name from any log of the day if not present in check-in
        if (branch == null || branch.isEmpty) {
          for (final log in logs) {
            final b = log['branchName']?.toString().trim();
            if (b != null && b.isNotEmpty) {
              branch = b;
              break;
            }
          }
        }

        // Calculate anti-fraud geofence status
        double? distance;
        bool? isInside;
        Branch? matchedBranch;

        if (lat != null && lng != null) {
          final checkInLog = logs.cast<Map<String, dynamic>?>().firstWhere(
            (l) => (l?['type'] ?? '') == 'check_in',
            orElse: () => null,
          );
          if (checkInLog != null) {
            matchedBranch = lookupBranchForAttendanceLog(
              branchesByName: _branchesByName,
              log: checkInLog,
              fallbackBranchName: branch,
            );
          } else if (branch != null && branch.trim().isNotEmpty) {
            matchedBranch = lookupBranchForAttendanceLog(
              branchesByName: _branchesByName,
              log: {'branchName': branch},
            );
          }

          // If still not matched by branch name, find the closest branch within 500m
          if (matchedBranch == null && _branchesByName.isNotEmpty) {
            double minDistance = double.infinity;
            Branch? closest;
            for (final b in _branchesByName.values) {
              if (b.latitude != 0.0 && b.longitude != 0.0) {
                final dMeters = Geolocator.distanceBetween(lat, lng, b.latitude, b.longitude);
                if (dMeters < minDistance) {
                  minDistance = dMeters;
                  closest = b;
                }
              }
            }
            if (closest != null && minDistance <= 500.0) {
              matchedBranch = closest;
            }
          }

          if (matchedBranch != null &&
              matchedBranch.latitude != 0.0 &&
              matchedBranch.longitude != 0.0) {
            distance = Geolocator.distanceBetween(
              lat,
              lng,
              matchedBranch.latitude,
              matchedBranch.longitude,
            );
            isInside = distance <= matchedBranch.geofenceRadius;
          }
        }

        // Evaluate Anti-Fraud & Integrity Score
        bool hasSecurityViolation = auditLogs.isNotEmpty || isMockLocation;
        String? violationReason;
        if (auditLogs.isNotEmpty) {
          final firstAudit = auditLogs.first;
          violationReason = firstAudit['violationTitle']?.toString() ??
              firstAudit['actionType']?.toString() ??
              'استخدام تطبيق تزييف الموقع (Fake GPS)';
          device ??= firstAudit['deviceModel']?.toString();
          ipAddress ??= firstAudit['ipAddress']?.toString();
          ipIsp ??= firstAudit['ipIsp']?.toString();
        }

        int trustScore = 100;
        String integrityStatus = 'none';

        if (checkIn == null) {
          integrityStatus = 'none';
          trustScore = 100;
        } else if (hasSecurityViolation) {
          integrityStatus = 'violation';
          trustScore = 15;
          violationReason ??= 'رصد تزييف موقع (Mock Location / Fake GPS)';
        } else if (isVpnUsed) {
          integrityStatus = 'warning';
          trustScore = 55;
          violationReason = 'رصد اتصال مشبوه عبر VPN/Proxy';
        } else if (isInside == false || (distance != null && matchedBranch != null && distance > matchedBranch.geofenceRadius)) {
          integrityStatus = 'warning';
          final radius = matchedBranch?.geofenceRadius ?? 100.0;
          if (distance != null && distance > 500.0) {
            trustScore = 60;
            violationReason =
                'تسجيل من مسافة بعيدة جداً عن الفرع (${distance.toStringAsFixed(0)}م)';
          } else if (distance != null && distance > radius) {
            trustScore = 75;
            violationReason =
                'تسجيل خارج نطاق الفرع (${distance.toStringAsFixed(0)}م - الحد المسموح: ${radius.toInt()}م)';
          } else {
            trustScore = 80;
            violationReason = 'تسجيل خارج النطاق الجغرافي للفرع';
          }
        } else if (isInside == true) {
          integrityStatus = 'trusted';
          trustScore = 100;
          violationReason =
              'مطابق للنطاق الجغرافي للفرع (${distance?.toStringAsFixed(0) ?? '—'}م) وبدون تنبيهات احتيال';
        } else {
          integrityStatus = 'trusted';
          trustScore = 100;
          violationReason = 'سليم وبدون تنبيهات احتيال';
        }

        list.add(
          HRAttendanceRecord(
            delegate: d,
            checkInTime: checkIn,
            checkOutTime: checkOut,
            branchName: branch,
            latitude: lat,
            longitude: lng,
            deviceInfo: device,
            deviceUuid: deviceUuid,
            distanceMeters: distance,
            isInsideGeofence: isInside,
            isMockLocation: isMockLocation,
            isVpnUsed: isVpnUsed,
            hasSecurityViolation: hasSecurityViolation,
            violationReason: violationReason,
            trustScore: trustScore,
            integrityStatus: integrityStatus,
            ipAddress: ipAddress,
            ipIsp: ipIsp,
            isOnApprovedLeave: isOnLeave,
            leaveReason: leaveReason,
            leaveType: leaveType,
            isAutoCheckOut: isAutoCheckOut,
            autoCheckOutReason: autoCheckOutReason,
          ),
        );
      }

      // Sort: Present first, then Departed, then on approved leave, then Absent
      list.sort((a, b) {
        if (a.isPresent && !b.isPresent) return -1;
        if (!a.isPresent && b.isPresent) return 1;
        if (a.isDeparted && !b.isDeparted) return -1;
        if (!a.isDeparted && b.isDeparted) return 1;
        if (a.isOnLeave && !b.isOnLeave) return -1;
        if (!a.isOnLeave && b.isOnLeave) return 1;
        return a.delegate.fullName.compareTo(b.delegate.fullName);
      });

      if (mounted) {
        setState(() {
          _records = list;
          _availableBranches = branchNames;
          _populateAvailableChains();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'فشل تحديث بيانات الحضور: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Same state/filters as the mobile UI; setters mirror its existing
  /// handlers exactly (date changes refetch; chain resets an invalid branch).
  HRAttendanceViewData _viewData() => HRAttendanceViewData(
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        selectedDate: _selectedDate,
        isToday: _isSameDay(_selectedDate, DateTime.now()),
        statusFilter: _statusFilter,
        selectedChain: _selectedChain,
        selectedBranch: _selectedBranch,
        chains: _availableChains,
        branches: _cascadingAvailableBranches,
        records: _filteredRecords,
        searchController: _searchController,
        onSearchChanged: () => setState(() {}),
        onDateChanged: (d) {
          setState(() => _selectedDate = d);
          _fetchAttendanceForSelectedDate();
        },
        onStatusChanged: (v) => setState(() => _statusFilter = v),
        onChainChanged: (val) {
          setState(() {
            _selectedChain = val;
            if (_selectedBranch != 'all') {
              final validBranches = _cascadingAvailableBranches;
              if (!validBranches.contains(_selectedBranch)) {
                _selectedBranch = 'all';
              }
            }
          });
        },
        onBranchChanged: (val) => setState(() => _selectedBranch = val),
        onRefresh: _fetchAttendanceForSelectedDate,
        allRecords: _records,
        branchesByName: _branchesByName,
        onReload: _loadInitialData,
      );

  List<HRAttendanceRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records.where((record) {
      // 1. Search Query
      if (query.isNotEmpty) {
        final matchesName =
            record.delegate.fullName.toLowerCase().contains(query);
        final matchesPhone = record.delegate.phoneNumber.contains(query);
        final matchesBranch =
            record.branchName?.toLowerCase().contains(query) ?? false;
        if (!matchesName && !matchesPhone && !matchesBranch) return false;
      }

      // 2. Status Filter
      if (_statusFilter == 'present' && !record.isPresent) return false;
      if (_statusFilter == 'departed' && !record.isDeparted) return false;
      if (_statusFilter == 'leave' && !record.isOnLeave) return false;
      if (_statusFilter == 'absent' && (!record.isAbsent || record.isOnLeave)) return false;
      if (_statusFilter == 'violation' && record.integrityStatus != 'violation') {
        return false;
      }
      if (_statusFilter == 'warning' && record.integrityStatus != 'warning') {
        return false;
      }

      // 3. Chain Filter (السلسلة)
      if (_selectedChain != 'all') {
        final matchesOrg = record.delegate.organizationName == _selectedChain ||
            record.delegate.allOrganizationNames.contains(_selectedChain);
        final branchObj = _branchesByName[(record.branchName ?? '').trim().toLowerCase()];
        final matchesBranchOrg = branchObj?.organizationName == _selectedChain;
        if (!matchesOrg && !matchesBranchOrg) return false;
      }

      // 4. Branch Filter (الفرع)
      if (_selectedBranch != 'all' && record.branchName != _selectedBranch) {
        return false;
      }

      return true;
    }).toList();
  }

  // ── 1. تصدير كشف الحضور اليومي إلى Excel ──
  Future<void> _exportDailyToExcel() async {
    final filtered = _filteredRecords;
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات لتصديرها.')),
      );
      return;
    }

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final csvHeader =
          '\uFEFFاسم المندوب,رقم الهاتف,التاريخ,وقت الحضور,وقت الانصراف,صافي ساعات العمل,الفرع,مؤشر النزاهة (%),حالة النزاهة الرقمية,فحص Fake GPS,فحص الـ VPN,حالة النطاق الجغرافي,المسافة المقدرة بالمتر,حالة الحضور,بيانات الجهاز,معرف الجهاز UUID\n';

      final csvRows = filtered.map((r) {
        final name = r.delegate.fullName.replaceAll(',', ' ');
        final phone = r.delegate.phoneNumber;
        final checkIn = r.checkInTime != null
            ? DateFormat('HH:mm:ss').format(r.checkInTime!)
            : 'لم يسجل';
        final checkOut = r.checkOutTime != null
            ? DateFormat('HH:mm:ss').format(r.checkOutTime!)
            : 'لم ينصرف';
        final duration = r.formattedDuration.replaceAll(',', ' ');
        final branch = (r.branchName ?? 'غير محدد').replaceAll(',', ' ');

        final trustScoreStr = '${r.trustScore}%';
        String integrityStatusStr = 'لم يسجل';
        if (r.integrityStatus == 'trusted') {
          integrityStatusStr = 'موثوق بالكامل';
        } else if (r.integrityStatus == 'warning') {
          integrityStatusStr = 'تنبيه أمني مشبوه';
        } else if (r.integrityStatus == 'violation') {
          integrityStatusStr = 'مخالفة أمنية خطيرة';
        }

        final fakeGpsStr = (r.isMockLocation || r.hasSecurityViolation)
            ? 'تم رصد Fake GPS'
            : 'سليم';
        final vpnStr = r.isVpnUsed ? 'تم رصد VPN' : 'سليم';

        String geofence = 'غير متوفر';
        if (r.isInsideGeofence == true) {
          geofence = 'داخل النطاق';
        } else if (r.isInsideGeofence == false) {
          geofence = 'خارج النطاق';
        }

        final distance = r.distanceMeters != null
            ? '${r.distanceMeters!.toStringAsFixed(1)}م'
            : '-';

        String status = 'غائب';
        if (r.isPresent) {
          status = 'حاضر الآن';
        } else if (r.isDeparted) {
          status = 'انصرف';
        } else if (r.isOnLeave) {
          status = 'إجازة (${r.formattedLeaveType})';
        }

        final device = (r.deviceInfo ?? '-').replaceAll(',', ' ');
        final uuid = (r.deviceUuid ?? r.delegate.boundDeviceId ?? '-').replaceAll(',', ' ');

        return '$name,$phone,$dateStr,$checkIn,$checkOut,$duration,$branch,$trustScoreStr,$integrityStatusStr,$fakeGpsStr,$vpnStr,$geofence,$distance,$status,$device,$uuid';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'hr_attendance_daily_${dateStr}_$nowStr.csv';

      await FileDownloadHelper.downloadString(
        content: csvContent,
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        shareText: 'تقرير حضور وانصراف شركة ${widget.hrDelegate.companyName} ($dateStr)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير كشف الحضور اليومي بنجاح'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تصدير التقرير اليومي: $e')),
        );
      }
    }
  }

  // ── 2. تصدير التقرير الشهري التجميعي للشركة إلى Excel ──
  Future<void> _exportMonthlyConsolidatedToExcel() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('جاري تجميع وإعداد التقرير الشهري للشركة...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );

      final monthStart =
          DateTime(_selectedDate.year, _selectedDate.month, 1, 0, 0, 0);
      final nextMonth =
          DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

      // جلب جميع سجلات الحضور الخاصة بشركة الـ HR خلال الشهر
      final query = await FirebaseFirestore.instance
          .collection(kAttendanceCollection)
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      // خريطة تجميع إحصائيات كل مندوب
      final Map<String, Map<String, dynamic>> delegateStats = {};

      for (final d in _companyDelegates) {
        delegateStats[d.uid] = {
          'delegate': d,
          'attendedDates': <String>{},
          'departedDates': <String>{},
          'totalMinutes': 0,
          'geofenceViolations': 0,
          'insideGeofenceCount': 0,
        };
      }

      final Map<String, Map<String, List<Map<String, dynamic>>>>
          logsByDelegateAndDate = {};

      for (final doc in query.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          final date = ts.toDate();
          if (date.isBefore(monthStart) || date.isAfter(monthEnd)) {
            continue;
          }
          final delegateId =
              (data['delegateId'] ?? data['userId'] ?? '').toString();
          if (delegateId.isEmpty || !delegateStats.containsKey(delegateId)) {
            continue;
          }

          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          logsByDelegateAndDate
              .putIfAbsent(delegateId, () => {})
              .putIfAbsent(dateKey, () => [])
              .add(data);
        }
      }

      // حساب الساعات اليومية والمخالفات لكل مندوب
      for (final entry in logsByDelegateAndDate.entries) {
        final delegateId = entry.key;
        final datesMap = entry.value;
        final stats = delegateStats[delegateId]!;

        for (final dateEntry in datesMap.entries) {
          final dateKey = dateEntry.key;
          final logs = dateEntry.value;

          DateTime? inTime;
          DateTime? outTime;
          double? lat;
          double? lng;
          String? bName;

          for (final log in logs) {
            final type = (log['type'] ?? '').toString();
            final ts = log['timestamp'];
            DateTime? t;
            if (ts is Timestamp) t = ts.toDate();

            if (type == 'check_in') {
              if (inTime == null || (t != null && t.isBefore(inTime))) {
                inTime = t;
                bName = log['branchName']?.toString();
                final loc = log['location'];
                if (loc is Map) {
                  lat = (loc['latitude'] as num?)?.toDouble();
                  lng = (loc['longitude'] as num?)?.toDouble();
                }
              }
            } else if (type == 'check_out') {
              if (outTime == null || (t != null && t.isAfter(outTime))) {
                outTime = t;
              }
            }
          }

          if (inTime != null) {
            (stats['attendedDates'] as Set<String>).add(dateKey);

            if (outTime != null) {
              (stats['departedDates'] as Set<String>).add(dateKey);
              final diff = outTime.difference(inTime).inMinutes;
              if (diff > 0) {
                stats['totalMinutes'] = (stats['totalMinutes'] as int) + diff;
              }
            }

            // التحقق من النطاق الجغرافي
            if (lat != null && lng != null && bName != null) {
              final matched = _branchesByName[bName.toLowerCase().trim()];
              if (matched != null && matched.latitude != 0.0) {
                final dMeters = Geolocator.distanceBetween(
                  lat,
                  lng,
                  matched.latitude,
                  matched.longitude,
                );
                if (dMeters <= matched.geofenceRadius) {
                  stats['insideGeofenceCount'] =
                      (stats['insideGeofenceCount'] as int) + 1;
                } else {
                  stats['geofenceViolations'] =
                      (stats['geofenceViolations'] as int) + 1;
                }
              }
            }
          }
        }
      }

      final now = DateTime.now();
      final isCurrentMonth =
          _selectedDate.year == now.year && _selectedDate.month == now.month;
      final activeDaysInMonth = isCurrentMonth
          ? now.day
          : nextMonth.subtract(const Duration(days: 1)).day;

      final monthStr = DateFormat('yyyy-MM').format(_selectedDate);
      final csvHeader =
          '\uFEFFاسم المندوب,رقم الهاتف,المسمى الوظيفي,الشهر,أيام الحضور الفعلي,أيام الغياب التقريبية,إجمالي ساعات العمل,متوسط الساعات اليومي,مرات الحضور المعتمد داخل النطاق,مخالفات خارج النطاق,مرات عدم تسجيل الانصراف\n';

      final csvRows = delegateStats.values.map((s) {
        final d = s['delegate'] as Delegate;
        final name = d.fullName.replaceAll(',', ' ');
        final phone = d.phoneNumber;
        final pos = d.position == DelegatePosition.supervisor
            ? 'مشرف'
            : 'مندوب / مروج';
        final attendedCount = (s['attendedDates'] as Set<String>).length;
        final departedCount = (s['departedDates'] as Set<String>).length;
        final absentCount =
            (activeDaysInMonth - attendedCount).clamp(0, activeDaysInMonth);
        final missedCheckouts =
            (attendedCount - departedCount).clamp(0, attendedCount);

        final totalMinutes = s['totalMinutes'] as int;
        final totalHours = totalMinutes ~/ 60;
        final remMinutes = totalMinutes % 60;
        final totalDurationStr = '$totalHours س و $remMinutes د';

        final avgHoursPerDay = attendedCount > 0
            ? (totalMinutes / (attendedCount * 60)).toStringAsFixed(1)
            : '0.0';

        final insideCount = s['insideGeofenceCount'] as int;
        final violations = s['geofenceViolations'] as int;

        return '$name,$phone,$pos,$monthStr,$attendedCount,$absentCount,$totalDurationStr,$avgHoursPerDay,$insideCount,$violations,$missedCheckouts';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'hr_monthly_consolidated_${monthStr}_$nowStr.csv';

      await FileDownloadHelper.downloadString(
        content: csvContent,
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        shareText:
            'التقرير التجميعي الشهري لشركة ${widget.hrDelegate.companyName} ($monthStr)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير التقرير الشهري التجميعي بنجاح'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تصدير التقرير الشهري: $e')),
        );
      }
    }
  }

  /// شارة مؤشر النزاهة الرقمية ومكافحة الاحتيال بجانب اسم المندوب
  Widget _buildSecurityBadge(HRAttendanceRecord record, ColorScheme colorScheme) {
    if (record.checkInTime == null) return const SizedBox.shrink();

    final status = record.integrityStatus;
    Color color;
    IconData icon;
    String label;
    String tooltipMsg;

    if (status == 'violation') {
      color = HrStatusColors.of(context).danger;
      icon = Icons.gpp_bad_rounded;
      label = '${record.trustScore}% مخالفة';
      tooltipMsg =
          'مخالفة أمنية خطيرة (${record.trustScore}%): ${record.violationReason ?? 'Fake GPS'} - اضغط لعرض تفاصيل الفحص الأمني';
    } else if (status == 'warning') {
      color = HrStatusColors.of(context).warning;
      icon = Icons.warning_amber_rounded;
      label = '${record.trustScore}% تنبيه';
      tooltipMsg =
          'تنبيه أمني مشبوه (${record.trustScore}%): ${record.violationReason ?? 'خارج النطاق الآمن'} - اضغط لعرض تفاصيل الفحص الأمني';
    } else {
      color = HrStatusColors.of(context).success;
      icon = Icons.verified_user_rounded;
      label = '100% موثوق';
      tooltipMsg =
          'موثوق بالكامل (100%): لا توجد أي تنبيهات احتيال ومسافة التسجيل أقل من 50م - اضغط لعرض تفاصيل الفحص الأمني';
    }

    return Tooltip(
      message: tooltipMsg,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(HrRadius.chip),
          onTap: () => _showTrustScoreDialog(context, record),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HrRadius.chip),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3.5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// نافذة منبثقة تفاعلية لعرض تفاصيل الفحص الأمني ومؤشر النزاهة الرقمية
  void _showTrustScoreDialog(
    BuildContext context,
    HRAttendanceRecord record,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Color statusColor;
    String statusTitle;
    String statusSubtitle;
    IconData statusIcon;

    if (record.integrityStatus == 'violation') {
      statusColor = HrStatusColors.of(context).danger;
      statusTitle = 'مخالفة أمنية خطيرة (Fake GPS)';
      statusSubtitle = 'تم رصد محاولة تلاعب أو تزييف بالموقع الجغرافي';
      statusIcon = Icons.gpp_bad_rounded;
    } else if (record.integrityStatus == 'warning') {
      statusColor = HrStatusColors.of(context).warning;
      statusTitle = 'تنبيه أمني (سجل مشبوه)';
      statusSubtitle = 'تم رصد مؤشرات اشتباه أو تسجيل خارج النطاق الآمن';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = HrStatusColors.of(context).success;
      statusTitle = 'موثوق بنسبة 100%';
      statusSubtitle = 'سجل حضور سليم ومطابق تماماً للنطاق الجغرافي المعتمد';
      statusIcon = Icons.verified_user_rounded;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HrRadius.pill),
          ),
          backgroundColor: colorScheme.surface,
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مؤشر النزاهة الرقمية ومكافحة الاحتيال',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المندوب: ${record.delegate.fullName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Trust Score Hero Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withValues(alpha: isDark ? 0.25 : 0.12),
                          statusColor.withValues(alpha: isDark ? 0.10 : 0.04),
                        ],
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                      ),
                      borderRadius: BorderRadius.circular(HrRadius.card),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Circular percentage score
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor, width: 2.5),
                          ),
                          child: Center(
                            child: Text(
                              '${record.trustScore}%',
                              style: TextStyle(
                                fontSize: HrFont.titleMedium,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusTitle,
                                style: TextStyle(
                                  fontSize: HrFont.titleMedium,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                record.violationReason ?? statusSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'تفاصيل الفحص الأمني لحظة التسجيل',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Security Audit Metrics List
                  _buildAuditMetricRow(
                    icon: (record.isMockLocation || record.hasSecurityViolation)
                        ? Icons.location_off_rounded
                        : Icons.verified_user_rounded,
                    iconColor: (record.isMockLocation || record.hasSecurityViolation)
                        ? HrStatusColors.of(context).danger
                        : HrStatusColors.of(context).success,
                    title: 'تطبيقات تزييف الموقع (Fake GPS)',
                    value: (record.isMockLocation || record.hasSecurityViolation)
                        ? 'تم رصد Fake GPS / Mock Location ⚠️'
                        : 'سليم - لم يُرصد أي تزييف للموقع ✅',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  _buildAuditMetricRow(
                    icon: record.isVpnUsed
                        ? Icons.vpn_lock_rounded
                        : Icons.shield_outlined,
                    iconColor: record.isVpnUsed
                        ? HrStatusColors.of(context).warning
                        : HrStatusColors.of(context).success,
                    title: 'برامج إخفاء الهوية والبروكسي (VPN)',
                    value: record.isVpnUsed
                        ? 'تم رصد استخدام VPN / Proxy ⚠️'
                        : 'سليم - اتصال محلي مباشر بدون VPN ✅',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  _buildAuditMetricRow(
                    icon: Icons.store_rounded,
                    iconColor: (record.distanceMeters != null && record.distanceMeters! <= 50)
                        ? HrStatusColors.of(context).success
                        : HrStatusColors.of(context).warning,
                    title: 'المسافة عن الصيدلية / الفرع',
                    value: record.distanceMeters != null
                        ? '${record.distanceMeters!.toStringAsFixed(1)} متر (${record.distanceMeters! <= 50 ? 'نطاق دقيق < 50م' : 'خارج النطاق الدقيق'})'
                        : 'غير متوفرة',
                    subtitle: 'الفرع المستهدف: ${BranchDisplayCache.instance.displayName(record.branchName, fallback: 'غير محدد')}',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  _buildAuditMetricRow(
                    icon: Icons.phone_android_rounded,
                    iconColor: colorScheme.primary,
                    title: 'معلومات الجهاز ومعرف الـ UUID',
                    value: record.deviceInfo ?? 'غير معروف',
                    subtitle: 'UUID: ${record.deviceUuid ?? record.delegate.boundDeviceId ?? 'غير مسجل'}',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  _buildAuditMetricRow(
                    icon: Icons.network_check_rounded,
                    iconColor: colorScheme.secondary,
                    title: 'بيانات الشبكة وعنوان IP',
                    value: record.ipAddress?.isNotEmpty == true
                        ? record.ipAddress!
                        : 'اتصال محلي معتمد',
                    subtitle: record.ipIsp?.isNotEmpty == true
                        ? 'مزود الخدمة: ${record.ipIsp}'
                        : null,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  _buildAuditMetricRow(
                    icon: Icons.access_time_rounded,
                    iconColor: colorScheme.outline,
                    title: 'توقيت التسجيل الدقيق',
                    value: record.checkInTime != null
                        ? DateFormat('yyyy-MM-dd | hh:mm:ss a', 'ar').format(record.checkInTime!)
                        : 'لم يسجل حضور',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: statusColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HrRadius.card),
                ),
              ),
              icon: const Icon(Icons.security_rounded, size: 18),
              label: const Text('مركز مكافحة الاحتيال'),
              onPressed: () {
                Navigator.pop(dialogCtx);
                if (widget.onNavigateToTab != null) {
                  widget.onNavigateToTab!(5);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AntiFraudAuditScreen(
                        delegate: widget.hrDelegate,
                        showAppBar: true,
                        initialTab: 'violations',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuditMetricRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HrRadius.chip),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: HrFont.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp(String phone) async {
    if (phone.isEmpty) return;
    var cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openGoogleMapsDirections(double lat1, double lng1, double lat2, double lng2) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$lat1,$lng1&destination=$lat2,$lng2');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showGeofenceInspectionDialog(BuildContext context, HRAttendanceRecord record) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final branchName = record.branchName;
    Branch? matchedBranch;
    if (branchName != null && branchName.trim().isNotEmpty) {
      final cleanName = branchName.trim().toLowerCase();
      matchedBranch = _branchesByName[cleanName];
      if (matchedBranch == null) {
        for (final entry in _branchesByName.entries) {
          if (entry.key.contains(cleanName) || cleanName.contains(entry.key)) {
            matchedBranch = entry.value;
            break;
          }
        }
      }
    }

    if (matchedBranch == null && record.latitude != null && record.longitude != null && _branchesByName.isNotEmpty) {
      double minD = double.infinity;
      Branch? closest;
      for (final b in _branchesByName.values) {
        if (b.latitude != 0.0 && b.longitude != 0.0) {
          final d = Geolocator.distanceBetween(record.latitude!, record.longitude!, b.latitude, b.longitude);
          if (d < minD) {
            minD = d;
            closest = b;
          }
        }
      }
      if (closest != null && minD <= 500.0) {
        matchedBranch = closest;
      }
    }

    final Color statusColor;
    final IconData statusIcon;
    final String statusTitle;
    final String statusSubtitle;

    if (record.isInsideGeofence == true) {
      statusColor = HrStatusColors.of(context).success;
      statusIcon = Icons.verified_user_rounded;
      statusTitle = 'داخل النطاق الجغرافي المعتمد ✅';
      statusSubtitle =
          'المندوب سجل حضوره على مسافة ${record.distanceMeters?.toStringAsFixed(1) ?? '—'} متراً من نقطة الفرع، ضمن النطاق المسموح (${matchedBranch?.geofenceRadius.toInt() ?? 100} متر).';
    } else if (record.isInsideGeofence == false) {
      statusColor = HrStatusColors.of(context).danger;
      statusIcon = Icons.warning_amber_rounded;
      statusTitle = 'خارج النطاق الجغرافي المحدد ⚠️';
      statusSubtitle =
          'المندوب سجل حضوره على مسافة ${record.distanceMeters?.toStringAsFixed(1) ?? '—'} متراً من الفرع، متجاوزاً النطاق المحدد (${matchedBranch?.geofenceRadius.toInt() ?? 100} متر).';
    } else if (record.latitude != null && record.longitude != null) {
      statusColor = colorScheme.primary;
      statusIcon = Icons.location_on_rounded;
      statusTitle = 'إحداثيات الموقع مسجلة 📍';
      statusSubtitle =
          'تم تسجيل إحداثيات GPS بدقة، ولم يتم العثور على إحداثيات مطابقة للفرع لمقارنة المسافة.';
    } else {
      statusColor = colorScheme.outline;
      statusIcon = Icons.location_off_outlined;
      statusTitle = 'لم يتم تسجيل إحداثيات الموقع';
      statusSubtitle = record.checkInTime != null
          ? 'سجل المندوب الحضور ولكن لم تتوفر إحداثيات GPS لحظة التسجيل.'
          : 'لم يقم المندوب بتسجيل الحضور اليوم حتى الآن.';
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HrRadius.pill),
          ),
          backgroundColor: colorScheme.surface,
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'فحص النطاق الجغرافي والموقع',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المندوب: ${record.delegate.fullName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withValues(alpha: isDark ? 0.25 : 0.12),
                          statusColor.withValues(alpha: isDark ? 0.10 : 0.04),
                        ],
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                      ),
                      borderRadius: BorderRadius.circular(HrRadius.card),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusTitle,
                          style: TextStyle(
                            fontSize: HrFont.titleMedium,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          statusSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'تفاصيل الموقع والنطاق الجغرافي',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Branch Info
                  _buildAuditMetricRow(
                    icon: Icons.store_rounded,
                    iconColor: colorScheme.primary,
                    title: 'الفرع المستهدف',
                    value: BranchDisplayCache.instance.displayName(branchName, fallback: 'غير محدد'),
                    subtitle: (matchedBranch != null && matchedBranch.latitude != 0.0)
                        ? 'إحداثيات الفرع: ${matchedBranch.latitude.toStringAsFixed(6)}, ${matchedBranch.longitude.toStringAsFixed(6)}\nنصف القطر المعتمد: ${matchedBranch.geofenceRadius.toInt()} متر'
                        : 'لم يتم العثور على إحداثيات مسجلة للفرع',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  // Delegate Location Info
                  _buildAuditMetricRow(
                    icon: Icons.my_location_rounded,
                    iconColor: record.latitude != null ? colorScheme.secondary : colorScheme.outline,
                    title: 'موقع المندوب لحظة الحضور',
                    value: (record.latitude != null && record.longitude != null)
                        ? '${record.latitude!.toStringAsFixed(6)}, ${record.longitude!.toStringAsFixed(6)}'
                        : 'غير متوفر',
                    subtitle: record.distanceMeters != null
                        ? 'المسافة المحسوبة عن الفرع: ${record.distanceMeters!.toStringAsFixed(1)} متر'
                        : null,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  // Check In Time
                  _buildAuditMetricRow(
                    icon: Icons.access_time_rounded,
                    iconColor: colorScheme.outline,
                    title: 'وقت تسجيل الحضور',
                    value: record.checkInTime != null
                        ? DateFormat('yyyy-MM-dd | hh:mm:ss a', 'ar').format(record.checkInTime!)
                        : 'لم يسجل حضور',
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),

                  // Device Info
                  _buildAuditMetricRow(
                    icon: Icons.phone_android_rounded,
                    iconColor: colorScheme.onSurfaceVariant,
                    title: 'معلومات الجهاز',
                    value: record.deviceInfo ?? 'غير معروف',
                    subtitle: record.deviceUuid != null ? 'معرف الجهاز: ${record.deviceUuid}' : null,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
            if (record.latitude != null && record.longitude != null && matchedBranch != null && matchedBranch.latitude != 0.0)
              OutlinedButton.icon(
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('مسار السير للفرع'),
                onPressed: () {
                  _openGoogleMapsDirections(
                    record.latitude!,
                    record.longitude!,
                    matchedBranch!.latitude,
                    matchedBranch.longitude,
                  );
                },
              ),
            if (record.latitude != null && record.longitude != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: statusColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(HrRadius.card),
                  ),
                ),
                icon: const Icon(Icons.map_rounded, size: 18),
                label: const Text('عرض على Google Maps'),
                onPressed: () {
                  _openGoogleMaps(record.latitude!, record.longitude!);
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewBuilder = widget.viewBuilder;
    if (viewBuilder != null) return viewBuilder(context, _viewData());
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 900;
    final isDesktop = screenWidth >= 1050;

    // Base records scoped to selected Chain and Branch for the KPI counts
    final baseRecords = _records.where((record) {
      if (_selectedChain != 'all') {
        final matchesOrg = record.delegate.organizationName == _selectedChain ||
            record.delegate.allOrganizationNames.contains(_selectedChain);
        final branchObj = _branchesByName[(record.branchName ?? '').trim().toLowerCase()];
        final matchesBranchOrg = branchObj?.organizationName == _selectedChain;
        if (!matchesOrg && !matchesBranchOrg) return false;
      }
      if (_selectedBranch != 'all' && record.branchName != _selectedBranch) {
        return false;
      }
      return true;
    }).toList();

    final totalCount = baseRecords.length;
    final presentCount = baseRecords.where((r) => r.isPresent).length;
    final departedCount = baseRecords.where((r) => r.isDeparted).length;
    final absentCount = baseRecords.where((r) => r.isAbsent && !r.isOnLeave).length;
    final onLeaveCount = baseRecords.where((r) => r.isOnLeave).length;
    final violationCount =
        baseRecords.where((r) => r.integrityStatus == 'violation').length;

    final isToday = _isSameDay(_selectedDate, DateTime.now());
    final filtered = _filteredRecords;

    return RefreshIndicator(
      onRefresh: _fetchAttendanceForSelectedDate,
      child: Column(
        children: [
          // ── Top Header Section (KPI Cards + Date Card) ──
          if (isWideScreen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildKpiCard(
                      title: 'إجمالي',
                      count: totalCount,
                      icon: Icons.people_alt_rounded,
                      color: colorScheme.primary,
                      theme: theme,
                      isSelected: _statusFilter == 'all',
                      onTap: () => setState(() => _statusFilter = 'all'),
                      isWide: true,
                      flex: 2,
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      title: 'حاضر الآن',
                      count: presentCount,
                      icon: Icons.check_circle_rounded,
                      color: HrStatusColors.of(context).success,
                      theme: theme,
                      isSelected: _statusFilter == 'present',
                      onTap: () => setState(() => _statusFilter = 'present'),
                      isWide: true,
                      flex: 2,
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      title: 'انصرف',
                      count: departedCount,
                      icon: Icons.timelapse_rounded,
                      color: HrStatusColors.of(context).warning,
                      theme: theme,
                      isSelected: _statusFilter == 'departed',
                      onTap: () => setState(() => _statusFilter = 'departed'),
                      isWide: true,
                      flex: 2,
                    ),
                    if (onLeaveCount > 0) ...[
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        title: 'إجازة معتمدة',
                        count: onLeaveCount,
                        icon: Icons.event_available_rounded,
                        color: const Color(0xFF00796B),
                        theme: theme,
                        isSelected: _statusFilter == 'leave',
                        onTap: () => setState(() => _statusFilter = 'leave'),
                        isWide: true,
                        flex: 2,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      title: 'لم يحضر',
                      count: absentCount,
                      icon: Icons.cancel_outlined,
                      color: colorScheme.outline,
                      theme: theme,
                      isSelected: _statusFilter == 'absent',
                      onTap: () => setState(() => _statusFilter = 'absent'),
                      isWide: true,
                      flex: 2,
                    ),
                    if (violationCount > 0) ...[
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        title: 'مخالفات أمنية',
                        count: violationCount,
                        icon: Icons.gpp_bad_rounded,
                        color: HrStatusColors.of(context).danger,
                        theme: theme,
                        isSelected: _statusFilter == 'violation',
                        onTap: () => setState(() => _statusFilter = 'violation'),
                        isWide: true,
                        flex: 2,
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Date Card (Formatted identically to KPI Cards)
                    _buildDateCard(
                      theme,
                      colorScheme,
                      isToday,
                      isWide: true,
                      flex: 3,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // ── Mobile Header & Controls (Reorganized per User Flow) ──

            // 1. Sleek Compact Date Header Bar (شريط ترويسة التاريخ المدمج النحيف)
            _buildMobileDateHeaderBar(theme, colorScheme, isToday),

            // 2. The Interactive KPI Cards in Row (الأربع/خمس كروت تفاعلية للفلترة)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  _buildKpiCard(
                    title: 'إجمالي',
                    count: totalCount,
                    icon: Icons.people_alt_rounded,
                    color: colorScheme.primary,
                    theme: theme,
                    isSelected: _statusFilter == 'all',
                    onTap: () => setState(() => _statusFilter = 'all'),
                    isWide: false,
                  ),
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'حاضر الآن',
                    count: presentCount,
                    icon: Icons.check_circle_rounded,
                    color: HrStatusColors.of(context).success,
                    theme: theme,
                    isSelected: _statusFilter == 'present',
                    onTap: () => setState(() => _statusFilter = 'present'),
                    isWide: false,
                  ),
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'انصرف',
                    count: departedCount,
                    icon: Icons.timelapse_rounded,
                    color: HrStatusColors.of(context).warning,
                    theme: theme,
                    isSelected: _statusFilter == 'departed',
                    onTap: () => setState(() => _statusFilter = 'departed'),
                    isWide: false,
                  ),
                  if (onLeaveCount > 0) ...[
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: 'إجازات',
                      count: onLeaveCount,
                      icon: Icons.event_available_rounded,
                      color: const Color(0xFF00796B),
                      theme: theme,
                      isSelected: _statusFilter == 'leave',
                      onTap: () => setState(() => _statusFilter = 'leave'),
                      isWide: false,
                    ),
                  ],
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'لم يحضر',
                    count: absentCount,
                    icon: Icons.cancel_outlined,
                    color: colorScheme.outline,
                    theme: theme,
                    isSelected: _statusFilter == 'absent',
                    onTap: () => setState(() => _statusFilter = 'absent'),
                    isWide: false,
                  ),
                  if (violationCount > 0) ...[
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: 'مخالفات',
                      count: violationCount,
                      icon: Icons.gpp_bad_rounded,
                      color: HrStatusColors.of(context).danger,
                      theme: theme,
                      isSelected: _statusFilter == 'violation',
                      onTap: () => setState(() => _statusFilter = 'violation'),
                      isWide: false,
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ── Search, Chain, Branch & Controls ──
          if (isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: _buildSearchBar(colorScheme),
                  ),
                  if (_availableChains.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _buildChainSelector(theme, colorScheme),
                  ],
                  if (_availableBranches.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _buildBranchSelector(theme, colorScheme),
                  ],
                  const Spacer(),
                  _buildExportMenuButton(colorScheme, isWide: true),
                  const SizedBox(width: 8),
                  _buildViewModeToggle(colorScheme),
                ],
              ),
            ),
          ] else ...[
            // Mobile Controls:
            // Row 1: Chain & Branch Selectors (side by side, 50% width each)
            if (_availableChains.isNotEmpty || _availableBranches.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    if (_availableChains.isNotEmpty)
                      Expanded(
                        child: _buildChainSelector(theme, colorScheme, isFullWidth: true),
                      ),
                    if (_availableChains.isNotEmpty && _availableBranches.isNotEmpty)
                      const SizedBox(width: 8),
                    if (_availableBranches.isNotEmpty)
                      Expanded(
                        child: _buildBranchSelector(theme, colorScheme, isFullWidth: true),
                      ),
                  ],
                ),
              ),

            // Row 2: Search Bar + View Mode Toggle + Export Button (Single Row)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSearchBar(colorScheme),
                  ),
                  const SizedBox(width: 8),
                  _buildViewModeToggle(colorScheme),
                  const SizedBox(width: 8),
                  _buildExportMenuButton(colorScheme, isWide: false),
                ],
              ),
            ),
          ],

          const Divider(height: 1),

          // ── Attendance List ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: colorScheme.error),
                            const SizedBox(height: 12),
                            Text(_errorMessage!,
                                style: TextStyle(color: colorScheme.error)),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _loadInitialData,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy_rounded,
                                    size: 56,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد سجلات حضور تطابق البحث في هذا اليوم',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _isTableView
                            ? _buildTableView(filtered, theme, colorScheme)
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth >
                                      kHrAttendanceCardsGridMinWidth) {
                                    // Fixed column count from the width so
                                    // every cell has the same width and the
                                    // rows line up (TAS-147).
                                    final columns = hrAttendanceCardColumns(
                                      constraints.maxWidth -
                                          2 * kHrAttendanceCardsGridPadding,
                                    );
                                    return GridView.builder(
                                      key: const Key('hr_attendance_cards_grid'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: kHrAttendanceCardsGridPadding,
                                        vertical: 12,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisExtent: kHrAttendanceCardHeight,
                                        crossAxisSpacing:
                                            kHrAttendanceCardsGridSpacing,
                                        mainAxisSpacing:
                                            kHrAttendanceCardsGridSpacing,
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        return _buildAttendanceCard(
                                          filtered[index],
                                          theme,
                                          colorScheme,
                                        );
                                      },
                                    );
                                  }

                                  return ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    itemCount: filtered.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      return _buildAttendanceCard(
                                        filtered[index],
                                        theme,
                                        colorScheme,
                                      );
                                    },
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }

  /// Attendance table on the shared HR table (TAS-115): 12px card, 56px
  /// header, 64px rows, status chips; scrolls sideways when narrow.
  Widget _buildTableView(
    List<HRAttendanceRecord> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HrTableCard(
        key: const Key('hr_attendance_table'),
        minWidth: kHrAttendanceTableMinWidth,
        horizontalController: _hScrollCtrl,
        builder: (context, width) => Column(
          children: [
            const HrTableHeader(
              columns: hrAttendanceTableColumns,
              keyPrefix: 'hr_attendance_header_',
            ),
            Expanded(
              child: ListView.separated(
                controller: _vScrollCtrl,
                itemCount: records.length,
                separatorBuilder: (context, index) => const HrTableDivider(),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _HRAttendanceTableRowItem(
                    key: ValueKey('row_${record.delegate.uid}_$index'),
                    record: record,
                    theme: theme,
                    colorScheme: colorScheme,
                    branchesByName: _branchesByName,
                    hrDelegate: widget.hrDelegate,
                    selectedDate: _selectedDate,
                    securityBadgeBuilder: _buildSecurityBadge,
                    onCallPhone: _callPhone,
                    onOpenWhatsApp: _openWhatsApp,
                    onOpenGoogleMaps: _openGoogleMaps,
                    onInspectGeofence: (rec) =>
                        _showGeofenceInspectionDialog(context, rec),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HRDelegateAttendanceDetailScreen(
                            delegate: record.delegate,
                            initialMonth: _selectedDate,
                            branchesByName: _branchesByName,
                            hrDelegate: widget.hrDelegate,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    required bool isSelected,
    required VoidCallback onTap,
    bool isWide = false,
    int flex = 2,
  }) {
    final colorScheme = theme.colorScheme;
    return Expanded(
      flex: flex,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HrRadius.card),
          child: AnimatedContainer(
            duration: AppMotionDurations.short3, // 150ms M3 Token
            curve: AppMotionCurves.standard,
            height: isWide ? 74 : 64,
            padding: EdgeInsets.symmetric(
              vertical: isWide ? 8 : 4,
              horizontal: isWide ? 8 : 4,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.14)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(HrRadius.card),
              border: Border.all(
                color: isSelected
                    ? color
                    : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isSelected ? 0.25 : 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: isWide ? 13 : 11, color: color),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isSelected ? color : colorScheme.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                          fontSize: isWide ? 11.5 : 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '$count',
                    style: (isWide
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontSize: isWide ? 22 : 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileDateHeaderBar(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isToday,
  ) {
    final dateStr = DateFormat('EEEE، d MMMM', 'ar').format(_selectedDate);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // السهم الأيمن: اليوم السابق في RTL
          InkWell(
            onTap: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _fetchAttendanceForSelectedDate();
            },
            borderRadius: BorderRadius.circular(HrRadius.chip),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
                textDirection: TextDirection.ltr,
              ),
            ),
          ),

          const Spacer(),

          // نص وأيقونة التاريخ التفاعلية
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2023),
                lastDate: DateTime.now().add(const Duration(days: 7)),
              );
              if (picked != null && !_isSameDay(picked, _selectedDate)) {
                setState(() => _selectedDate = picked);
                _fetchAttendanceForSelectedDate();
              }
            },
            borderRadius: BorderRadius.circular(HrRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateStr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      fontSize: HrFont.body,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          if (!isToday) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                setState(() => _selectedDate = DateTime.now());
                _fetchAttendanceForSelectedDate();
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'اليوم',
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],

          const Spacer(),

          // السهم الأيسر: اليوم التالي في RTL
          InkWell(
            onTap: isToday
                ? null
                : () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _fetchAttendanceForSelectedDate();
                  },
            borderRadius: BorderRadius.circular(HrRadius.chip),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: isToday
                    ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                    : colorScheme.onSurfaceVariant,
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isToday, {
    bool isWide = true,
    int flex = 3,
    bool isFullWidth = false,
  }) {
    final dateStr = DateFormat('EEEE، d MMMM', 'ar').format(_selectedDate);

    final cardContent = Container(
      height: isWide ? 74 : 64,
      padding: EdgeInsets.symmetric(
        vertical: isWide ? 8 : 4,
        horizontal: isWide ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Top: Icon + Title + Quick 'اليوم' badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: isWide ? 13 : 11,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'التاريخ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  fontSize: isWide ? 11.5 : 10,
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() => _selectedDate = DateTime.now());
                    _fetchAttendanceForSelectedDate();
                  },
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'اليوم',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),

          // Bottom: Navigation Chevrons + Clickable Date text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Chevron Previous Day (Right chevron in RTL)
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  });
                  _fetchAttendanceForSelectedDate();
                },
                borderRadius: BorderRadius.circular(HrRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: isWide ? 20 : 18,
                    color: colorScheme.onSurfaceVariant,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              const SizedBox(width: 2),

              // Date Text (Tap to open DatePicker)
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Tooltip(
                    message: 'اضغط لاختيار تاريخ آخر',
                    child: Text(
                      dateStr,
                      style: (isWide
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                        fontSize: isWide ? 12.5 : 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),

              // Chevron Next Day (Left chevron in RTL)
              InkWell(
                onTap: isToday
                    ? null
                    : () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        });
                        _fetchAttendanceForSelectedDate();
                      },
                borderRadius: BorderRadius.circular(HrRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: isWide ? 20 : 18,
                    color: isToday
                        ? colorScheme.outlineVariant.withValues(alpha: 0.4)
                        : colorScheme.onSurfaceVariant,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // The whole card opens the date picker (TAS-147): it reads as one
    // control, and clicks beside the small date text used to do nothing.
    // The chevrons and «اليوم» keep their own taps.
    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('hr_attendance_date_card'),
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(14),
        child: cardContent,
      ),
    );

    if (isFullWidth) {
      return tappable;
    }
    return Expanded(
      flex: flex,
      child: tappable,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (!mounted) return;
    if (picked != null && !_isSameDay(picked, _selectedDate)) {
      setState(() => _selectedDate = picked);
      _fetchAttendanceForSelectedDate();
    }
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 44,
      child: SearchBar(
        controller: _searchController,
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
        hintText: 'بحث باسم المندوب أو الهاتف أو الفرع...',
        hintStyle: WidgetStateProperty.all(
          TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            fontSize: HrFont.labelMedium,
            fontWeight: FontWeight.normal,
          ),
        ),
        textStyle: WidgetStateProperty.all(
          TextStyle(
            color: colorScheme.onSurface,
            fontSize: HrFont.labelMedium,
          ),
        ),
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(
          colorScheme.surfaceContainerHigh,
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HrRadius.pill),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        leading: Icon(
          Icons.search_rounded,
          size: 19,
          color: colorScheme.primary,
        ),
        trailing: _searchController.text.isNotEmpty
            ? [
                TashilIconButton.close(
                  size: 26,
                  iconSize: 14,
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
              ]
            : null,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildChainSelector(
    ThemeData theme,
    ColorScheme colorScheme, {
    bool isFullWidth = false,
  }) {
    final isSelectedAll = _selectedChain == 'all';
    final displayText = isSelectedAll ? 'جميع السلاسل' : _selectedChain;

    return PopupMenuButton<String>(
      tooltip: 'تصفية حسب السلسلة',
      borderRadius: BorderRadius.circular(HrRadius.pill),
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      onSelected: (val) {
        setState(() {
          _selectedChain = val;
          if (_selectedBranch != 'all') {
            final validBranches = _cascadingAvailableBranches;
            if (!validBranches.contains(_selectedBranch)) {
              _selectedBranch = 'all';
            }
          }
        });
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  isSelectedAll
                      ? Icons.check_circle_rounded
                      : Icons.apartment_outlined,
                  size: 18,
                  color: isSelectedAll
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'جميع السلاسل',
                  style: TextStyle(
                    fontWeight:
                        isSelectedAll ? FontWeight.bold : FontWeight.normal,
                    color: isSelectedAll
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ..._availableChains.map(
            (chain) {
              final isSelected = _selectedChain == chain;
              return PopupMenuItem<String>(
                value: chain,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.apartment_rounded,
                      size: 18,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chain,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ];
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(HrRadius.pill),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: isFullWidth
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.apartment_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: isFullWidth ? 95 : 140),
                  child: Text(
                    displayText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchSelector(
    ThemeData theme,
    ColorScheme colorScheme, {
    bool isFullWidth = false,
  }) {
    final isSelectedAll = _selectedBranch == 'all';
    final displayText = isSelectedAll ? 'جميع الفروع' : BranchDisplayCache.instance.displayName(_selectedBranch);

    return PopupMenuButton<String>(
      tooltip: 'تصفية حسب الفرع',
      borderRadius: BorderRadius.circular(HrRadius.pill),
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      onSelected: (val) {
        setState(() => _selectedBranch = val);
      },
      itemBuilder: (context) {
        final branchesToShow = _cascadingAvailableBranches;
        return [
          PopupMenuItem<String>(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  isSelectedAll
                      ? Icons.check_circle_rounded
                      : Icons.storefront_outlined,
                  size: 18,
                  color: isSelectedAll
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'جميع الفروع',
                  style: TextStyle(
                    fontWeight:
                        isSelectedAll ? FontWeight.bold : FontWeight.normal,
                    color: isSelectedAll
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...branchesToShow.map(
            (b) {
              final isSelected = _selectedBranch == b;
              return PopupMenuItem<String>(
                value: b,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.storefront_rounded,
                      size: 18,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        BranchDisplayCache.instance.displayName(b),
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ];
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(HrRadius.pill),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: isFullWidth
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: isFullWidth ? 95 : 140),
                  child: Text(
                    displayText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildExportMenuButton(ColorScheme colorScheme, {bool isWide = false}) {
    return _ExportMenuButton(
      colorScheme: colorScheme,
      isWide: isWide,
      selectedDate: _selectedDate,
      onExportDaily: _exportDailyToExcel,
      onExportMonthly: _exportMonthlyConsolidatedToExcel,
    );
  }

  Widget _buildViewModeToggle(ColorScheme colorScheme) {
    return TashilConnectedButtonGroup<bool>(
      height: 44,
      selectedValue: _isTableView,
      onSelected: (val) {
        setState(() => _isTableView = val);
      },
      items: const [
        TashilConnectedButtonItem<bool>(
          value: true,
          label: 'جدول',
          icon: Icons.table_chart_rounded,
        ),
        TashilConnectedButtonItem<bool>(
          value: false,
          label: 'بطاقات',
          icon: Icons.grid_view_rounded,
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(
    HRAttendanceRecord record,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isPresent = record.isPresent;
    final isDeparted = record.isDeparted;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isPresent) {
      statusColor = HrStatusColors.of(context).success;
      statusText = 'حاضر الآن';
      statusIcon = Icons.check_circle_rounded;
    } else if (isDeparted) {
      if (record.isAutoCheckOut) {
        statusColor = HrStatusColors.of(context).warning;
        statusText = 'انصرف (تلقائي)';
        statusIcon = Icons.auto_mode_rounded;
      } else {
        statusColor = HrStatusColors.of(context).warning;
        statusText = 'انصرف اليوم';
        statusIcon = Icons.timelapse_rounded;
      }
    } else if (record.isOnLeave) {
      statusColor = const Color(0xFF00796B);
      statusText = record.formattedLeaveType;
      statusIcon = Icons.event_available_rounded;
    } else {
      statusColor = colorScheme.outline;
      statusText = 'لم يسجل';
      statusIcon = Icons.schedule_rounded;
    }

    final posName = record.delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: isPresent
              ? statusColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isPresent ? 1.5 : 1.0,
        ),
      ),
      color: isPresent
          ? statusColor.withValues(alpha: 0.02)
          : colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Delegate Top Header & Status ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(
                  imageUrl: record.delegate.personalPhotoUrl,
                  fallbackText: record.delegate.fullName,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.delegate.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '\u202A${record.delegate.phoneNumber}\u202C • $posName',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (record.checkInTime != null) ...[
                            const SizedBox(width: 6),
                            _buildSecurityBadge(record, colorScheme),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: HrFont.labelSmall,
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

            // ── Attendance Times & Branch ──
            if (record.checkInTime != null || record.branchName != null) ...[
              Row(
                children: [
                  // Branch
                  if (record.branchName != null) ...[
                    Icon(Icons.storefront_rounded,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: BranchNameLabel(
                        branchName: record.branchName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  // Check-in Time
                  if (record.checkInTime != null) ...[
                    Icon(Icons.login_rounded,
                        size: 15, color: HrStatusColors.of(context).success),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        DateFormat('hh:mm a', 'ar').format(record.checkInTime!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: HrStatusColors.of(context).success,
                        ),
                      ),
                    ),
                  ],

                  // Check-out Time
                  if (record.checkOutTime != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      record.isAutoCheckOut ? Icons.auto_mode_rounded : Icons.logout_rounded,
                      size: 15,
                      color: record.isAutoCheckOut ? Colors.amber[800] : HrStatusColors.of(context).warning,
                    ),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        DateFormat('hh:mm a', 'ar').format(record.checkOutTime!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: record.isAutoCheckOut ? Colors.amber[900] : HrStatusColors.of(context).warning,
                        ),
                      ),
                    ),
                    if (record.isAutoCheckOut) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'تم إغلاق الانصراف تلقائياً بعد مرور 11.5 ساعة على بداية الوردية لعدم تسجيل الانصراف يدوياً',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_mode_rounded, size: 12, color: Colors.amber[800]),
                              const SizedBox(width: 3),
                              Text(
                                'إغلاق تلقائي (11.5 س)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.bold,
                                  fontSize: HrFont.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              if (record.checkInTime != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      record.isDeparted
                          ? Icons.timelapse_rounded
                          : Icons.play_arrow_rounded,
                      size: 15,
                      color: record.isDeparted
                          ? colorScheme.secondary
                          : HrStatusColors.of(context).success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'صافي الساعات: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      record.formattedDuration,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: record.isDeparted
                            ? colorScheme.secondary
                            : HrStatusColors.of(context).success,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],

            // ── Anti-Fraud Geofence & Device Details ──
            if (record.latitude != null && record.longitude != null) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showGeofenceInspectionDialog(context, record),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (record.isInsideGeofence == true)
                          ? HrStatusColors.of(context).success.withValues(alpha: 0.08)
                          : (record.isInsideGeofence == false)
                              ? HrStatusColors.of(context).danger.withValues(alpha: 0.08)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(HrRadius.chip),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          record.isInsideGeofence == true
                              ? Icons.verified_user_rounded
                              : record.isInsideGeofence == false
                                  ? Icons.warning_amber_rounded
                                  : Icons.location_on_outlined,
                          size: 16,
                          color: record.isInsideGeofence == true
                              ? HrStatusColors.of(context).success
                              : record.isInsideGeofence == false
                                  ? HrStatusColors.of(context).danger
                                  : colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            record.isInsideGeofence == true
                                ? 'نطاق جغرافي سليم (داخل حدود الفرع: ${record.distanceMeters!.toStringAsFixed(0)}م)'
                                : record.isInsideGeofence == false
                                    ? 'تنبيه: خارج حدود الفرع بمسافة ${record.distanceMeters!.toStringAsFixed(0)}م'
                                    : 'إحداثيات الحضور مسجلة',
                            style: TextStyle(
                              fontSize: HrFont.labelMedium,
                              fontWeight: FontWeight.w600,
                              color: record.isInsideGeofence == true
                                  ? HrStatusColors.of(context).success
                                  : record.isInsideGeofence == false
                                      ? HrStatusColors.of(context).danger
                                      : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // Map Icon Button
                        TashilIconButton.standard(
                          icon: Icons.map_outlined,
                          tooltip: 'عرض الإحداثيات على الخريطة',
                          size: 28,
                          iconSize: 16,
                          onPressed: () => _openGoogleMaps(
                            record.latitude!,
                            record.longitude!,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Device Info & Actions Row ──
            Row(
              children: [
                if (record.deviceInfo != null && record.deviceInfo!.trim().isNotEmpty) ...[
                  Icon(Icons.smartphone_rounded,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      record.deviceInfo!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),

                // Action: Phone Call
                if (record.delegate.phoneNumber.isNotEmpty) ...[
                  TashilIconButton.tonal(
                    icon: Icons.call_outlined,
                    tooltip: 'اتصال بالمندوب',
                    size: 34,
                    iconSize: 17,
                    onPressed: () => _callPhone(record.delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                  TashilIconButton.tonal(
                    icon: Icons.chat_outlined,
                    tooltip: 'مراسلة عبر واتساب',
                    size: 34,
                    iconSize: 17,
                    onPressed: () => _openWhatsApp(record.delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                ],

                // Action: View Monthly History
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HrRadius.card),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('السجل الشهري والتفصيلي'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HRDelegateAttendanceDetailScreen(
                          delegate: record.delegate,
                          initialMonth: _selectedDate,
                          branchesByName: _branchesByName,
                          hrDelegate: widget.hrDelegate,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Below this width the attendance table scrolls sideways.
const double kHrAttendanceTableMinWidth = 1260;

/// Attendance table columns (TAS-115). Header and rows share them.
const List<HrTableColumn> hrAttendanceTableColumns = [
  HrTableColumn('المندوب', 19),
  HrTableColumn('الحالة', 10, center: true),
  HrTableColumn('الفرع', 14),
  HrTableColumn('الحضور • الانصراف • الساعات', 29, center: true),
  HrTableColumn('النطاق الجغرافي', 16),
  HrTableColumn('الإجراءات', 12, center: true),
];

/// Status chip label, tone and icon for an attendance record.
({String label, HrStatusTone tone, IconData icon}) hrAttendanceStatus(
  HRAttendanceRecord record,
) {
  if (record.isPresent) {
    return (
      label: 'حاضر الآن',
      tone: HrStatusTone.success,
      icon: Icons.check_circle_rounded,
    );
  }
  if (record.isDeparted) {
    return record.isAutoCheckOut
        ? (
            label: 'انصرف (تلقائي)',
            tone: HrStatusTone.warning,
            icon: Icons.auto_mode_rounded,
          )
        : (
            label: 'انصرف اليوم',
            tone: HrStatusTone.warning,
            icon: Icons.timelapse_rounded,
          );
  }
  if (record.isOnLeave) {
    return (
      label: record.formattedLeaveType,
      tone: HrStatusTone.neutral,
      icon: Icons.event_available_rounded,
    );
  }
  return (
    label: 'لم يسجل',
    tone: HrStatusTone.neutral,
    icon: Icons.schedule_rounded,
  );
}

class _HRAttendanceTableRowItem extends StatefulWidget {
  final HRAttendanceRecord record;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Map<String, Branch> branchesByName;
  final Delegate hrDelegate;
  final DateTime selectedDate;
  final Widget Function(HRAttendanceRecord, ColorScheme) securityBadgeBuilder;
  final void Function(String) onCallPhone;
  final void Function(String) onOpenWhatsApp;
  final void Function(double, double) onOpenGoogleMaps;
  final void Function(HRAttendanceRecord) onInspectGeofence;
  final VoidCallback onTap;

  const _HRAttendanceTableRowItem({
    super.key,
    required this.record,
    required this.theme,
    required this.colorScheme,
    required this.branchesByName,
    required this.hrDelegate,
    required this.selectedDate,
    required this.securityBadgeBuilder,
    required this.onCallPhone,
    required this.onOpenWhatsApp,
    required this.onOpenGoogleMaps,
    required this.onInspectGeofence,
    required this.onTap,
  });

  @override
  State<_HRAttendanceTableRowItem> createState() => _HRAttendanceTableRowItemState();
}

class _HRAttendanceTableRowItemState extends State<_HRAttendanceTableRowItem> {
  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final theme = widget.theme;
    final colorScheme = widget.colorScheme;
    final statusColors = HrStatusColors.of(context);
    final isPresent = record.isPresent;
    final status = hrAttendanceStatus(record);
    final hasLocation = record.latitude != null && record.longitude != null;

    final checkInStr = record.checkInTime != null
        ? DateFormat('hh:mm a', 'ar').format(record.checkInTime!)
        : '—';

    final checkOutStr = record.checkOutTime != null
        ? DateFormat('hh:mm a', 'ar').format(record.checkOutTime!)
        : '—';

    // 1. Delegate: avatar + name, security badge under it.
    final delegateCell = Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AppAvatar(
              imageUrl: record.delegate.personalPhotoUrl,
              fallbackText: record.delegate.fullName,
              radius: 20,
            ),
            if (isPresent)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: statusColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                record.delegate.fullName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: HrFont.body,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (record.checkInTime != null) ...[
                const SizedBox(height: 4),
                widget.securityBadgeBuilder(record, colorScheme),
              ],
            ],
          ),
        ),
      ],
    );

    // 2. Status chip with icon and semantic color.
    final statusCell = HrStatusChip(
      key: Key('hr_attendance_status_${record.delegate.uid}'),
      label: status.label,
      tone: status.tone,
      icon: status.icon,
    );

    // 3. Branch.
    final branchCell = Tooltip(
      message: record.branchName ?? 'غير محدد',
      child: BranchNameLabel(
        branchName: record.branchName,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: HrFont.body,
          color: colorScheme.onSurface,
        ),
      ),
    );

    // 4. Check-in, check-out and hours.
    final timesCell = _buildTimeHoursGroup(
      record,
      theme,
      colorScheme,
      checkInStr,
      checkOutStr,
    );

    // 5. Geofence and distance, tap to inspect, map button.
    final geoColor = record.isInsideGeofence == true
        ? statusColors.success
        : record.isInsideGeofence == false
            ? statusColors.danger
            : hasLocation
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant;
    final geofenceCell = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(HrRadius.chip),
        onTap: () => widget.onInspectGeofence(record),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(
                record.isInsideGeofence == true
                    ? Icons.verified_user_rounded
                    : record.isInsideGeofence == false
                        ? Icons.warning_amber_rounded
                        : hasLocation
                            ? Icons.location_on_outlined
                            : Icons.location_off_outlined,
                size: 18,
                color: geoColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: 'انقر للاطلاع على تفاصيل النطاق الجغرافي والخريطة',
                  child: Text(
                    record.isInsideGeofence == true
                        ? 'داخل النطاق (${record.distanceMeters!.toStringAsFixed(0)}م)'
                        : record.isInsideGeofence == false
                            ? 'خارج النطاق (${record.distanceMeters!.toStringAsFixed(0)}م)'
                            : hasLocation
                                ? 'موقع مسجل 📍'
                                : (record.checkInTime != null
                                    ? 'غير محدد'
                                    : 'لم يسجل'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: HrFont.body,
                      fontWeight: FontWeight.w500,
                      color: geoColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (hasLocation)
                TashilIconButton.standard(
                  icon: Icons.map_outlined,
                  tooltip: 'عرض الإحداثيات على الخريطة',
                  size: 32,
                  iconSize: 18,
                  onPressed: () => widget.onOpenGoogleMaps(
                    record.latitude!,
                    record.longitude!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // 6. Actions: call, WhatsApp, monthly record.
    Widget action({
      required IconData icon,
      required String tooltip,
      required Color color,
      required VoidCallback onPressed,
    }) =>
        IconButton(
          icon: Icon(icon),
          iconSize: 18,
          color: color,
          tooltip: tooltip,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: onPressed,
        );
    final actionsCell = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.delegate.phoneNumber.isNotEmpty) ...[
            action(
              icon: Icons.call_outlined,
              tooltip: 'اتصال هاتفي',
              color: statusColors.success,
              onPressed: () => widget.onCallPhone(record.delegate.phoneNumber),
            ),
            action(
              icon: Icons.chat_outlined,
              tooltip: 'محادثة واتساب',
              color: statusColors.success,
              onPressed: () =>
                  widget.onOpenWhatsApp(record.delegate.phoneNumber),
            ),
          ],
          action(
            icon: Icons.history_rounded,
            tooltip: 'السجل الشهري والتفصيلي',
            color: colorScheme.primary,
            onPressed: widget.onTap,
          ),
        ],
      ),
    );

    return HrTableRow(
      key: Key('hr_attendance_row_${record.delegate.uid}'),
      columns: hrAttendanceTableColumns,
      cells: [
        delegateCell,
        statusCell,
        branchCell,
        timesCell,
        geofenceCell,
        actionsCell,
      ],
      onTap: widget.onTap,
    );
  }

  Widget _buildTimeHoursGroup(
    HRAttendanceRecord record,
    ThemeData theme,
    ColorScheme colorScheme,
    String checkInStr,
    String checkOutStr,
  ) {
    if (record.checkInTime == null) {
      return Center(
        child: Text(
          '—',
          style: TextStyle(
            color: colorScheme.outlineVariant,
            fontWeight: FontWeight.bold,
            fontSize: HrFont.body,
          ),
        ),
      );
    }

    final isPresent = record.isPresent;
    final isDeparted = record.isDeparted;

    final durationColor = isPresent
        ? HrStatusColors.of(context).success
        : (isDeparted ? HrStatusColors.of(context).warning : colorScheme.onSurfaceVariant);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(HrRadius.chip),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. الحضور (Check-in)
              Tooltip(
                message: 'وقت الحضور: $checkInStr',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.login_rounded,
                      size: 13,
                      color: HrStatusColors.of(context).success,
                    ),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        checkInStr,
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: HrStatusColors.of(context).success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // الفاصل بين الحضور والانصراف
              Container(
                height: 16,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),

              // 2. الانصراف (Check-out)
              Tooltip(
                message: record.isAutoCheckOut
                    ? 'تم إغلاق الانصراف تلقائياً بعد مرور 11.5 ساعة على بداية الوردية لعدم تسجيل الانصراف يدوياً ($checkOutStr)'
                    : (record.checkOutTime != null
                        ? 'وقت الانصراف: $checkOutStr'
                        : 'لم يسجل انصراف بعد'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      record.isAutoCheckOut ? Icons.auto_mode_rounded : Icons.logout_rounded,
                      size: 13,
                      color: record.isAutoCheckOut
                          ? Colors.amber[800]
                          : (record.checkOutTime != null
                              ? HrStatusColors.of(context).warning
                              : colorScheme.outlineVariant),
                    ),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        checkOutStr,
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: record.isAutoCheckOut
                              ? Colors.amber[900]
                              : (record.checkOutTime != null
                                  ? HrStatusColors.of(context).warning
                                  : colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                    if (record.isAutoCheckOut) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'تلقائي (11.5 س)',
                          style: TextStyle(
                            fontSize: HrFont.labelSmall,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // الفاصل بين الانصراف وصافي الساعات
              Container(
                height: 16,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),

              // 3. صافي الساعات (Working Hours)
              Tooltip(
                message: isPresent
                    ? 'صافي ساعات العمل: ${record.formattedDuration}'
                    : 'إجمالي ساعات العمل: ${record.formattedDuration}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: durationColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPresent
                            ? Icons.play_arrow_rounded
                            : Icons.timer_outlined,
                        size: 13,
                        color: durationColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        record.formattedDuration,
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: durationColor,
                        ),
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
  }
}


class _ExportMenuButton extends StatefulWidget {
  final ColorScheme colorScheme;
  final bool isWide;
  final DateTime selectedDate;
  final VoidCallback onExportDaily;
  final VoidCallback onExportMonthly;

  const _ExportMenuButton({
    required this.colorScheme,
    required this.isWide,
    required this.selectedDate,
    required this.onExportDaily,
    required this.onExportMonthly,
  });

  @override
  State<_ExportMenuButton> createState() => _ExportMenuButtonState();
}

class _ExportMenuButtonState extends State<_ExportMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final isWide = widget.isWide;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<String>(
        tooltip: 'خيارات تصدير Excel',
        borderRadius: BorderRadius.circular(HrRadius.pill),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        elevation: 4,
        onSelected: (val) {
          if (val == 'daily') {
            widget.onExportDaily();
          } else if (val == 'monthly') {
            widget.onExportMonthly();
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem<String>(
            value: 'daily',
            child: Row(
              children: [
                Icon(Icons.today_rounded,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'كشف يومي',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: HrFont.body,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        DateFormat('yyyy-MM-dd').format(widget.selectedDate),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: HrFont.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'monthly',
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded,
                    color: HrStatusColors.of(context).success, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'تقرير شهري',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: HrFont.body,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        DateFormat('MMMM yyyy', 'ar').format(widget.selectedDate),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: HrFont.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        child: AnimatedContainer(
          duration: AppMotionDurations.short3,
          curve: AppMotionCurves.standard,
          height: 44,
          padding: isWide ? const EdgeInsets.symmetric(horizontal: 14) : null,
          width: isWide ? null : 44,
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.75)
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(HrRadius.pill),
            border: Border.all(
              color: _isHovered
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: isWide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Excel',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: HrFont.labelMedium,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                )
              : Center(
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
        ),
      ),
    );
  }
}
