import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'dart:async';

import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/datasources/offline_branch_cache.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:delegate_app/features/attendance/domain/monthly_attendance_stats.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_for_month.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_action_lock.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_location_fetcher.dart';
import 'package:delegate_app/features/attendance/presentation/scanner/close_range_lens.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/early_checkout_confirm_sheet.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/location_help_card.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/attendance/domain/geofence_helpers.dart';
import 'package:delegate_app/features/attendance/domain/attendance_branch_chain_guard.dart';
import 'package:delegate_app/features/attendance/domain/branch_auto_locator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/branch_reports/presentation/report_branch_location_sheet.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:io';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/services/security_audit_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';

class AttendanceScreen extends StatefulWidget {
  final Delegate delegate;
  final bool viewOnly;

  /// Every chain/company membership of the delegate (TAS-245). Used to find
  /// the branch they stand in across all their chains.
  final List<Delegate> memberships;

  /// Called when the delegate stands in a branch of another chain. The
  /// owner switches to [target]; null turns automatic switching off.
  final Future<void> Function(Delegate target, String branchLabel)?
  onAutoSwitchChain;

  const AttendanceScreen({
    super.key,
    required this.delegate,
    this.viewOnly = false,
    this.memberships = const [],
    this.onAutoSwitchChain,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  late DateTime _selectedMonth;
  late final AttendanceBloc _attendanceBloc;

  // --- Performance: Cache connectivity state instead of StreamBuilder ---
  bool _isOffline = false;

  /// TAS-363: attendance saved on the phone, waiting for the network.
  final AttendanceOfflineQueue? _offlineQueue =
      sl.isRegistered<AttendanceOfflineQueue>()
      ? sl<AttendanceOfflineQueue>()
      : null;

  int get _pendingOfflineCount => widget.viewOnly
      ? 0
      : (_offlineQueue?.pendingCount(widget.delegate.uid) ?? 0);

  void _onOfflineQueueChanged() {
    if (mounted) setState(() {});
  }

  SyncRequested _syncRequest({bool reloadHistory = false}) => SyncRequested(
    userId: widget.viewOnly ? '' : widget.delegate.uid,
    reloadHistory: reloadHistory,
    nationalityID: widget.delegate.nationalityID,
    phoneNumber: widget.delegate.phoneNumber,
  );

  String _clock(DateTime t) => Bidi.ltr(DateFormat.jm('ar').format(t));
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  List<Attendance> _rawHistory = [];
  List<Attendance> _filteredHistory = [];
  Map<String, List<Attendance>> _groupedByDay = {};
  List<String> _dayKeys = [];
  String _chainFilter = 'all'; // 'all' or normalized chain name
  // TAS-387: second level of the filter (branch inside the chosen chain).
  String _branchFilter = 'all';
  List<String> _availableBranches = [];
  int _allAttendedDaysCount = 0;

  /// All sessions of [_monthSessionsFor] (whole month, not the loaded page).
  /// Month figures and chain chips are computed from this when available.
  List<Attendance>? _monthSessions;
  DateTime? _monthSessionsFor;
  int _monthSessionsRequestId = 0;
  List<String> _availableChains = [];
  Map<String, int> _chainDaysCount = {};
  int _approvedLeavesThisMonth = 0;

  static final Map<String, String> _orgNamesCache = {
    'PiioBFgxaHAeuRdjlDgj': 'فتح الله ماركت',
    '5DE6702w6hFwycJfZyqM': 'جملة ماركت',
    'gOaRsmPocj2xV018m0hY': 'جملة ماركت',
  };

  static String _formatChainName(
    String rawOrgName, {
    String? branchName,
    bool isArabic = true,
  }) {
    final bLower = (branchName ?? '').trim().toLowerCase();
    if (bLower.startsWith('جملة ماركت') ||
        bLower.startsWith('جمله ماركت') ||
        bLower.startsWith('gomla market') ||
        bLower.startsWith('jomla market')) {
      return isArabic ? 'جملة ماركت' : 'Gomla Market';
    }
    if (bLower.startsWith('فتح الله') || bLower.startsWith('fathalla')) {
      return isArabic ? 'فتح الله ماركت' : 'Fathalla Market';
    }
    if (bLower.startsWith('زهران') || bLower.startsWith('zahran')) {
      return isArabic ? 'زهران ماركت' : 'Zahran Market';
    }
    if (bLower.startsWith('كارفور') || bLower.startsWith('carrefour')) {
      return isArabic ? 'كارفور' : 'Carrefour';
    }
    if (bLower.startsWith('بيت الجملة') || bLower.startsWith('beit')) {
      return isArabic ? 'بيت الجملة' : 'Beit El Gomla';
    }

    return chainDisplayName(rawOrgName, isArabic: isArabic);
  }

  static String _cleanBranchName(String rawBranchName) {
    final trimmed = rawBranchName.trim();
    if (trimmed.isEmpty) return trimmed;
    final prefixRegex = RegExp(
      r'^(?:جملة\s*ماركت|جمله\s*ماركت|فتح\s*الله\s*ماركت|فتح\s*الله|زهران\s*ماركت|زهران|كارفور|بيت\s*الجملة|fathalla\s*market|fathallah\s*market|fathalla|gomla\s*market|jomla\s*market|zahran\s*market|carrefour)\s*[-–—:،/]\s*',
      caseSensitive: false,
    );
    final cleaned = trimmed.replaceFirst(prefixRegex, '').trim();
    return cleaned.isNotEmpty ? cleaned : trimmed;
  }

  String _resolveOrgName(
    String orgId, {
    String? branchName,
    bool isArabic = true,
  }) {
    String raw = '';
    if (orgId.isEmpty) {
      raw = widget.delegate.organizationName;
    } else if (_orgNamesCache.containsKey(orgId)) {
      raw = _orgNamesCache[orgId]!;
    } else if (orgId == widget.delegate.organizationUID) {
      raw = widget.delegate.organizationName;
    } else {
      FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .getResilient(forceServer: false)
          .then((doc) {
            if (doc.exists && mounted) {
              final name = (doc.data()?['name'] as String?)?.trim() ?? '';
              if (name.isNotEmpty) {
                setState(() {
                  _orgNamesCache[orgId] = name;
                  _recomputeFilteredHistory();
                });
              }
            }
          })
          .ignore();
      raw = widget.delegate.organizationName;
    }
    return _formatChainName(raw, branchName: branchName, isArabic: isArabic);
  }

  /// The selected month's sessions are still on their way (month switch):
  /// numbers and days show skeletons until they land (TAS-387).
  bool get _monthLoading =>
      sl.isRegistered<GetHistoryForMonth>() && !_hasMonthSessionsForSelected;

  bool get _hasMonthSessionsForSelected =>
      _monthSessions != null &&
      _monthSessionsFor != null &&
      _monthSessionsFor!.year == _selectedMonth.year &&
      _monthSessionsFor!.month == _selectedMonth.month;

  /// Loads every session of the selected month so the month summary and
  /// chain chips never depend on how many history pages were scrolled.
  Future<void> _loadMonthSessions() async {
    if (!sl.isRegistered<GetHistoryForMonth>()) return;
    final month = DateTime(_selectedMonth.year, _selectedMonth.month);
    final requestId = ++_monthSessionsRequestId;
    try {
      final result = await sl<GetHistoryForMonth>()(
        GetHistoryForMonthParams(
          userId: widget.delegate.uid,
          month: month,
          nationalityID: widget.delegate.nationalityID,
          phoneNumber: widget.delegate.phoneNumber,
        ),
      );
      if (!mounted || requestId != _monthSessionsRequestId) return;
      result.fold((_) {}, (sessions) {
        setState(() {
          _monthSessions = sessions;
          _monthSessionsFor = month;
          _recomputeFilteredHistory();
        });
      });
    } catch (_) {}
  }

  Future<void> _loadApprovedLeaves() async {
    unawaited(_loadMonthSessions());
    try {
      final snap = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('delegateUid', isEqualTo: widget.delegate.uid)
          .where('status', isEqualTo: 'approved')
          .getResilient(forceServer: false);

      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isHourly'] == true) continue;
        final start = data['startDate'];
        if (start is Timestamp) {
          final date = start.toDate();
          if (date.year == _selectedMonth.year &&
              date.month == _selectedMonth.month) {
            final days = (data['daysCount'] as num?)?.toInt() ?? 1;
            count += days;
          }
        }
      }
      if (mounted) {
        setState(() {
          _approvedLeavesThisMonth = count;
        });
      }
    } catch (_) {}
  }

  final ScrollController _scrollController = ScrollController();

  /// TAS-352: the check-in FAB is extended at rest and while scrolling up,
  /// an icon-only FAB while the list scrolls down.
  bool _fabExtended = true;

  bool _onFabScroll(UserScrollNotification n) {
    // Only the page's vertical list; the chain chips scroll sideways.
    if (n.metrics.axis != Axis.vertical) return false;
    // Idle (the scroll stopped) keeps the last state.
    if (n.direction == ScrollDirection.idle) return false;
    final extend = n.direction == ScrollDirection.forward;
    if (extend != _fabExtended) setState(() => _fabExtended = extend);
    return false;
  }

  // --- Geofencing & Motion State ---
  late final AnimationController _radarController;
  late final Animation<double> _radarAnimation;

  String? _orgAttendanceMode;
  List<Branch> _orgBranches = [];
  bool _isLoadingBranches = false;
  Position? _currentPosition;
  Branch? _matchedBranch;
  Branch? _nearestBranch;
  double? _distanceToNearest;
  bool _isInsideGeofence = false;
  bool _isCheckingLocation = false;
  final AttendanceActionLock _actionLock = AttendanceActionLock();
  final AttendanceLocationFetcher _locationFetcher =
      AttendanceLocationFetcher();
  String? _locationStatusMessage;

  /// Why the last visible location check failed; null after a good fix.
  /// Drives the open-settings help card (TAS-283).
  LocationFailureKind? _locationFailure;

  bool get _isGeofenceMode => isGeofenceAttendanceMode(
    _orgAttendanceMode,
    widget.delegate.organizationName,
  );

  // --- Automatic chain + branch detection (TAS-245) ---
  /// Branches of the delegate's OTHER chains (null until loaded).
  List<Branch>? _otherChainBranches;
  final Set<String> _otherGeofenceOrgIds = {};
  bool _autoLocateDone = false;
  bool _autoLocateRunning = false;

  Set<String> get _otherChainOrgIds => widget.memberships
      .map((m) => m.organizationUID.trim())
      .where((o) => o.isNotEmpty && o != widget.delegate.organizationUID)
      .toSet();

  bool get _canAutoSwitchChain =>
      !widget.viewOnly &&
      widget.onAutoSwitchChain != null &&
      _otherChainOrgIds.isNotEmpty;

  bool get _hasSeveralChains => _otherChainOrgIds.isNotEmpty;

  /// The open chain plus every other chain the delegate belongs to.
  Set<String> get _memberOrgIds => {
    widget.delegate.organizationUID.trim(),
    ..._otherChainOrgIds,
  };

  /// Refuses a check-in on a branch outside the open chain (TAS-333). The
  /// branch is never swapped for another one: the delegate gets a message
  /// and nothing is written. Returns true when refused.
  bool _refuseBranchOfOtherChain(
    BuildContext context,
    AttendanceBranchRef ref,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (checkBranchChain(
      branchOrganizationUID: ref.branchOrganizationUID,
      currentOrgId: widget.delegate.organizationUID,
      memberOrgIds: _memberOrgIds,
    )) {
      case BranchChainCheck.ok:
        return false;
      case BranchChainCheck.otherOwnChain:
        final org = ref.branchOrganizationUID.trim();
        final chain = widget.memberships
            .where((m) => m.organizationUID.trim() == org)
            .map((m) => m.organizationName.trim())
            .firstWhere((n) => n.isNotEmpty, orElse: () => org);
        AppSnackBar.showError(context, l10n.attBranchOtherChain(chain));
        return true;
      case BranchChainCheck.notMember:
        AppSnackBar.showError(context, l10n.attBranchNotYourChain);
        return true;
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    BranchDisplayCache.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    try {
      _selectedMonth = sl.isRegistered<TrustedTimeService>()
          ? sl<TrustedTimeService>().now
          : DateTime.now();
    } catch (_) {
      _selectedMonth = DateTime.now();
    }

    _loadApprovedLeaves();
    _attendanceBloc = sl<AttendanceBloc>();
    _attendanceBloc.add(
      HistoryRequested(
        userId: widget.delegate.uid,
        organizationId: '', // Cross-org query for unified monthly attendance
        nationalityID: widget.delegate.nationalityID,
        phoneNumber: widget.delegate.phoneNumber,
      ),
    );
    // Delay sync request to allow history to load first (only for active delegate's own session)
    if (!widget.viewOnly) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!_attendanceBloc.isClosed) {
          _attendanceBloc.add(_syncRequest());
        }
      }).ignore();
    }

    // Subscribe to connectivity changes once
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
        // TAS-363: network back: send what was saved on the phone.
        if (!offline && !widget.viewOnly && !_attendanceBloc.isClosed) {
          _attendanceBloc.add(_syncRequest(reloadHistory: true));
        }
      }
    });
    _offlineQueue?.changes.addListener(_onOfflineQueueChanged);
    Connectivity()
        .checkConnectivity()
        .then((results) {
          final offline = results.contains(ConnectivityResult.none);
          if (mounted && offline != _isOffline) {
            setState(() => _isOffline = offline);
          }
        })
        .catchError((_) {});

    _scrollController.addListener(_onScroll);

    // Initialize Material 3 Radar Pulse Animation
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (!widget.viewOnly &&
        !kIsWeb &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      _radarController.repeat();
    }
    _radarAnimation = CurvedAnimation(
      parent: _radarController,
      curve: AppMotionCurves.standardDecelerate,
    );

    // If Geofence mode is expected, load organization settings and branches
    if (!widget.viewOnly &&
        !kIsWeb &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchOrganizationSettings().then((_) {
            if (!mounted) return;
            if (_isGeofenceMode) {
              _loadBranches();
            } else {
              _autoLocateAcrossChains(null);
            }
          });
        }
      });
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    final state = _attendanceBloc.state;
    if (state is AttendanceHistoryLoaded) {
      _rawHistory = state.history;
    }
    _recomputeFilteredHistory();
  }

  void _onScroll() {
    if (_isBottom) {
      final state = _attendanceBloc.state;
      if (state is AttendanceHistoryLoaded &&
          !state.isLoadingMore &&
          !state.hasReachedMax) {
        _attendanceBloc.add(
          LoadMoreHistoryRequested(
            userId: widget.delegate.uid,
            organizationId:
                '', // Cross-org query for unified monthly attendance
            nationalityID: widget.delegate.nationalityID,
            phoneNumber: widget.delegate.phoneNumber,
          ),
        );
      }
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return false;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  void dispose() {
    _radarController.dispose();
    _connectivitySub.cancel();
    _offlineQueue?.changes.removeListener(_onOfflineQueueChanged);
    _scrollController.dispose();
    _attendanceBloc.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID == widget.delegate.organizationUID &&
        oldWidget.memberships.length != widget.memberships.length &&
        !_autoLocateDone &&
        !_isLoadingBranches &&
        (_orgBranches.isNotEmpty || !_isGeofenceMode)) {
      // Memberships arrived after the first scan (TAS-245).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoLocateAcrossChains(null);
      });
    }
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID) {
      _otherChainBranches = null;
      _otherGeofenceOrgIds.clear();
      _autoLocateDone = false;
      setState(() {
        _orgBranches.clear();
        _matchedBranch = null;
        _nearestBranch = null;
        _distanceToNearest = null;
        _isInsideGeofence = false;
        _recomputeFilteredHistory();
      });
      if (!widget.viewOnly) {
        _fetchOrganizationSettings().then((_) {
          if (!mounted) return;
          if (_isGeofenceMode) {
            _loadBranches();
          } else {
            _autoLocateAcrossChains(null);
          }
        });
      }
      _loadApprovedLeaves();
      _attendanceBloc.add(
        HistoryRequested(
          userId: widget.delegate.uid,
          organizationId: '', // Cross-org query
          nationalityID: widget.delegate.nationalityID,
          phoneNumber: widget.delegate.phoneNumber,
        ),
      );
    }
  }

  /// Recomputes filtered/grouped data only when source data or month changes.
  void _recomputeFilteredHistory() {
    final currentOrg = widget.delegate.organizationUID.trim();
    final isArabic =
        true; // Canonical chain keys in Arabic for consistent matching

    final allDaysSet = <String>{};
    final chainDaysSets = <String, Set<String>>{};
    final chainsOrdered = <String>[];

    void registerChain(String name) {
      final norm = _formatChainName(name, isArabic: isArabic).trim();
      if (norm.isNotEmpty && !chainsOrdered.contains(norm)) {
        chainsOrdered.add(norm);
        chainDaysSets.putIfAbsent(norm, () => <String>{});
      }
    }

    if (widget.delegate.organizationName.isNotEmpty) {
      registerChain(widget.delegate.organizationName);
    }
    for (final orgName in widget.delegate.allOrganizationNames) {
      registerChain(orgName);
    }

    // Whole-month sessions when loaded; otherwise the loaded page as a
    // temporary preview until the month query returns.
    final statsSource = _hasMonthSessionsForSelected
        ? _monthSessions!
        : _rawHistory;
    for (final item in statsSource) {
      if (item.checkInTime.month == _selectedMonth.month &&
          item.checkInTime.year == _selectedMonth.year) {
        final dayKey = DateFormat('yyyy-MM-dd').format(item.checkInTime);
        allDaysSet.add(dayKey);
        final itemChain = _resolveOrgName(
          item.organizationId,
          branchName: item.branchName,
          isArabic: isArabic,
        );
        if (itemChain.isNotEmpty) {
          registerChain(itemChain);
          chainDaysSets.putIfAbsent(itemChain, () => <String>{}).add(dayKey);
        }
      }
    }

    _allAttendedDaysCount = allDaysSet.length;
    _availableChains = chainsOrdered;
    _chainDaysCount = {
      for (final entry in chainDaysSets.entries) entry.key: entry.value.length,
    };

    if (_chainFilter != 'all' &&
        _chainFilter != 'active' &&
        !_availableChains.contains(_chainFilter)) {
      _chainFilter = 'all';
    }

    _filteredHistory = _rawHistory.where((attendance) {
      final inMonth =
          attendance.checkInTime.month == _selectedMonth.month &&
          attendance.checkInTime.year == _selectedMonth.year;
      if (!inMonth) return false;

      if (_chainFilter == 'all') return true;
      if (_chainFilter == 'active' && currentOrg.isNotEmpty) {
        return attendance.organizationId.isEmpty ||
            attendance.organizationId == currentOrg;
      }
      final itemChain = _resolveOrgName(
        attendance.organizationId,
        branchName: attendance.branchName,
        isArabic: isArabic,
      );
      return itemChain == _chainFilter;
    }).toList();

    // TAS-387: branches seen in the chosen chain this month, then the
    // branch filter on top of the chain filter.
    final branches = <String>[];
    for (final a in _filteredHistory) {
      final b = _cleanBranchName(a.branchName ?? '');
      if (b.isNotEmpty && !branches.contains(b)) branches.add(b);
    }
    _availableBranches = branches;
    if (_branchFilter != 'all' && !branches.contains(_branchFilter)) {
      _branchFilter = 'all';
    }
    if (_branchFilter != 'all') {
      _filteredHistory = _filteredHistory
          .where((a) => _cleanBranchName(a.branchName ?? '') == _branchFilter)
          .toList();
    }

    _filteredHistory.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

    _groupedByDay = {};
    for (final item in _filteredHistory) {
      final dayKey = DateFormat('yyyy-MM-dd').format(item.checkInTime);
      _groupedByDay.putIfAbsent(dayKey, () => []).add(item);
    }
    _dayKeys = _groupedByDay.keys.toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider.value(
      value: _attendanceBloc,
      child: BlocConsumer<AttendanceBloc, AttendanceState>(
        listener: (context, state) {
          if (state is AttendanceCheckedIn) {
            if (!widget.viewOnly && WebRuntimePolicy.liveTrackingEnabled) {
              DelegateTrackingEngine().startTrackingSession(
                delegateId: widget.delegate.uid,
              );
            }
            if (state.attendance.isSynced) {
              AppSnackBar.showSuccess(context, l10n.checkedInSuccessfully);
            } else {
              // TAS-363, message 3.7.
              AppSnackBar.showInfo(
                context,
                offlineCheckInSavedMessage(
                  _clock(state.attendance.checkInTime),
                ),
              );
            }
            context.read<AttendanceBloc>().add(
              HistoryRequested(
                userId: widget.delegate.uid,
                organizationId: '',
                nationalityID: widget.delegate.nationalityID,
                phoneNumber: widget.delegate.phoneNumber,
              ),
            );
          } else if (state is AttendanceCheckedOut) {
            if (!widget.viewOnly) {
              DelegateTrackingEngine().stopTrackingSession();
            }
            if (state.attendance.isSynced) {
              AppSnackBar.showSuccess(context, l10n.checkedOutSuccessfully);
            } else {
              AppSnackBar.showInfo(
                context,
                offlineCheckOutSavedMessage(
                  _clock(state.attendance.checkOutTime ?? DateTime.now()),
                ),
              );
            }
            context.read<AttendanceBloc>().add(
              HistoryRequested(
                userId: widget.delegate.uid,
                organizationId: '',
                nationalityID: widget.delegate.nationalityID,
                phoneNumber: widget.delegate.phoneNumber,
              ),
            );
          } else if (state is AttendanceError) {
            if (state.outsideGeofence) {
              _showOutsideGeofence(context, state.message);
            } else {
              AppSnackBar.showError(context, state.message);
            }
          } else if (state is AttendanceHistoryLoaded) {
            _rawHistory = state.history;
            _recomputeFilteredHistory();

            if (_filteredHistory.isEmpty &&
                !state.hasReachedMax &&
                !state.isLoadingMore) {
              // Auto-pagination: If current batch doesn't match selected month, load more automatically.
              context.read<AttendanceBloc>().add(
                LoadMoreHistoryRequested(
                  userId: widget.delegate.uid,
                  organizationId:
                      '', // Cross-org query for unified monthly attendance
                  nationalityID: widget.delegate.nationalityID,
                  phoneNumber: widget.delegate.phoneNumber,
                ),
              );
            }
            if (state.syncStatus == SyncStatus.success) {
              AppSnackBar.showSuccess(
                context,
                AppLocalizations.of(context)!.syncDone,
              );
              Future.delayed(const Duration(seconds: 1), () {
                if (context.mounted) {
                  context.read<AttendanceBloc>().add(
                    HistoryRequested(
                      userId: widget.delegate.uid,
                      organizationId:
                          '', // Cross-org query for unified monthly attendance
                      nationalityID: widget.delegate.nationalityID,
                      phoneNumber: widget.delegate.phoneNumber,
                    ),
                  );
                }
              });
            } else if (state.syncStatus == SyncStatus.failure) {
              AppSnackBar.showError(
                context,
                AppLocalizations.of(context)!.syncFailed,
              );
            }
          }
        },
        builder: (context, state) {
          final colorScheme = Theme.of(context).colorScheme;
          bool isCheckedIn = false;
          Attendance? activeAttendance;
          bool isSyncing = false;

          if (state is AttendanceHistoryLoaded) {
            if (!identical(_rawHistory, state.history) ||
                (_rawHistory.isNotEmpty && _availableChains.isEmpty)) {
              _rawHistory = state.history;
              _recomputeFilteredHistory();
            }
            isCheckedIn = state.activeAttendance != null;
            activeAttendance = state.activeAttendance;
            isSyncing = state.syncStatus == SyncStatus.inProgress;
          } else if (_rawHistory.isNotEmpty) {
            if (_availableChains.isEmpty) {
              _recomputeFilteredHistory();
            }
            activeAttendance = _rawHistory.cast<Attendance?>().firstWhere(
              (element) => element?.checkOutTime == null,
              orElse: () => null,
            );
            isCheckedIn = activeAttendance != null;
          }

          if (!widget.viewOnly &&
              WebRuntimePolicy.liveTrackingEnabled &&
              isCheckedIn &&
              !DelegateTrackingEngine().isTracking) {
            DelegateTrackingEngine().startTrackingSession(
              delegateId: widget.delegate.uid,
            );
          }

          return Scaffold(
            backgroundColor: colorScheme.surfaceContainerLowest,
            appBar: widget.viewOnly
                ? AppBar(
                    title: Text(
                      widget.delegate.fullName.isNotEmpty
                          ? widget.delegate.fullName
                          : (widget.delegate.companyName.isNotEmpty
                                ? AppLocalizations.of(
                                    context,
                                  )!.attDelegateOfCompany(
                                    widget.delegate.companyName,
                                  )
                                : AppLocalizations.of(context)!.attendanceLog),
                    ),
                  )
                : null,
            body: SafeArea(
              child: NotificationListener<UserScrollNotification>(
                onNotification: _onFabScroll,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: TashilSpacing.page,
                  ),
                  child: _buildBody(context, state),
                ),
              ),
            ),
            // TAS-352 (C-04): the extended FAB shrinks to an icon while the
            // list scrolls down and comes back on scroll up. Colours are
            // the container roles with their on colours; shape, elevation
            // and press feedback come from the theme.
            floatingActionButton: widget.viewOnly
                ? null
                : Builder(
                    builder: (context) {
                      final cs = Theme.of(context).colorScheme;
                      final secondary =
                          !isCheckedIn && _isGeofenceMode && !_isInsideGeofence;
                      final fabBg = secondary
                          ? cs.secondaryContainer
                          : cs.primaryContainer;
                      final fabFg = secondary
                          ? cs.onSecondaryContainer
                          : cs.onPrimaryContainer;
                      final label = _actionLock.isBusy
                          ? l10n.attLocatingShort
                          : _buildFabLabel(
                              context,
                              isCheckedIn: isCheckedIn,
                              activeAttendance: activeAttendance,
                              l10n: l10n,
                            );
                      return FloatingActionButton.extended(
                        key: const Key('attendanceFab'),
                        isExtended: _fabExtended,
                        tooltip: label,
                        backgroundColor: fabBg,
                        foregroundColor: fabFg,
                        onPressed:
                            (_actionLock.isBusy ||
                                state is AttendanceLoading ||
                                isSyncing)
                            ? null
                            : () {
                                _actionLock.run(
                                  bloc: _attendanceBloc,
                                  onChanged: () {
                                    if (mounted) setState(() {});
                                  },
                                  action: () {
                                    if (!WebRuntimePolicy.checkInEnabled) {
                                      AppSnackBar.showInfo(
                                        context,
                                        WebRuntimePolicy.checkInWebMessage,
                                      );
                                      return Future<void>.value();
                                    }
                                    return _isGeofenceMode
                                        ? _handleGeofenceAction(
                                            isCheckedIn: isCheckedIn,
                                            activeAttendance: activeAttendance,
                                          )
                                        : _showQRScanner(
                                            context,
                                            isCheckedIn,
                                            activeAttendance,
                                          );
                                  },
                                );
                              },
                        icon: _actionLock.isBusy
                            ? SizedBox.square(
                                key: const Key('attendanceFabBusy'),
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: fabFg,
                                ),
                              )
                            : Icon(
                                isCheckedIn
                                    ? Symbols.logout_rounded
                                    : (_isGeofenceMode
                                          ? (_isCheckingLocation
                                                ? Symbols.radar_rounded
                                                : (_isInsideGeofence
                                                      ? Symbols
                                                            .how_to_reg_rounded
                                                      : Symbols
                                                            .location_searching_rounded))
                                          : Symbols.qr_code_scanner_rounded),
                              ),
                        label: Text(label),
                      );
                    },
                  ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          );
        },
      ),
    );
  }

  DateTime _getTrustedNow() {
    try {
      if (sl.isRegistered<TrustedTimeService>()) {
        return sl<TrustedTimeService>().now;
      }
    } catch (_) {}
    return DateTime.now();
  }

  int _calculateAbsentDays() {
    // Earliest registration date across all chains (new delegates).
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

    final sessions = _hasMonthSessionsForSelected
        ? _monthSessions!
        : _rawHistory;
    return MonthlyAttendanceStats.compute(
      sessions: sessions,
      month: _selectedMonth,
      now: _getTrustedNow(),
      approvedLeaveDays: _approvedLeavesThisMonth,
      createdAt: earliestCreatedAt,
    ).absentDays;
  }

  /// Unified Material Design 3 Header Card consolidating:
  /// 1. Month / Date navigation
  /// 2. Attendance & Absence statistics (condensed with Google Icons)
  /// 3. Geofence & Location status with M3 radar animation
  Widget _buildUnifiedAttendanceCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final l10n = AppLocalizations.of(context)!;
    final trustedNow = _getTrustedNow();
    final isCurrentMonth =
        _selectedMonth.year == trustedNow.year &&
        _selectedMonth.month == trustedNow.month;

    final attendedDays = _allAttendedDaysCount;
    final absentDays = _calculateAbsentDays();
    final isBusy = _isCheckingLocation || _isLoadingBranches;

    // Semantic status for geofence section
    final Color statusColor;
    final IconData headerIcon;
    final String statusTitle;
    final String statusSubtitle;
    final activeBranch = _matchedBranch ?? _nearestBranch;

    // TAS-352 (F-04): outside the zone is a warning, not an error; inside
    // is success. Pairs come from TashilSemanticColors, never an alpha tint.
    final semantic = theme.extension<TashilSemanticColors>();
    final Color onStatusColor;
    final Color statusContainer;
    final Color onStatusContainer;
    if (isBusy) {
      statusColor = colorScheme.primary;
      onStatusColor = colorScheme.onPrimary;
      statusContainer = colorScheme.surfaceContainerHighest;
      onStatusContainer = colorScheme.onSurface;
      headerIcon = Symbols.radar_rounded;
      statusTitle = AppLocalizations.of(context)!.attCheckingZone;
      statusSubtitle = AppLocalizations.of(context)!.attVerifyingCoords;
    } else if (_isInsideGeofence) {
      statusColor = semantic?.success ?? colorScheme.primary;
      onStatusColor = semantic?.onSuccess ?? colorScheme.onPrimary;
      statusContainer =
          semantic?.successContainer ?? colorScheme.primaryContainer;
      onStatusContainer =
          semantic?.onSuccessContainer ?? colorScheme.onPrimaryContainer;
      headerIcon = Symbols.verified_rounded;
      statusTitle = AppLocalizations.of(context)!.attInsideZone;
      statusSubtitle = activeBranch != null
          ? AppLocalizations.of(context)!.attWithinBranchRange(
              BranchDisplayCache.instance.displayName(activeBranch.branchName),
            )
          : AppLocalizations.of(context)!.attInsideZone;
    } else {
      // TAS-387: outside the zone blocks check-in, so it is an error state
      // (user decision 27 Nov; F-04 updated: a state that blocks an action).
      statusColor = colorScheme.error;
      onStatusColor = colorScheme.onError;
      statusContainer = colorScheme.errorContainer;
      onStatusContainer = colorScheme.onErrorContainer;
      headerIcon = Symbols.wrong_location_rounded;
      statusTitle = AppLocalizations.of(context)!.attOutsideZone;
      statusSubtitle = activeBranch != null
          ? AppLocalizations.of(context)!.attMoveCloserTo(
              BranchDisplayCache.instance.displayName(activeBranch.branchName),
            )
          : AppLocalizations.of(context)!.attOutsideApprovedBranches;
    }

    // Smart distance formatting
    String? formattedDistance;
    if (_distanceToNearest != null && _distanceToNearest!.isFinite) {
      final meters = _distanceToNearest!.toInt();
      if (meters < 1000) {
        formattedDistance = AppLocalizations.of(
          context,
        )!.distanceMeters(meters);
      } else {
        final km = (_distanceToNearest! / 1000).toStringAsFixed(1);
        formattedDistance = AppLocalizations.of(
          context,
        )!.distanceKmM(km, meters);
      }
    }

    final allowedRadius = activeBranch != null
        ? (activeBranch.geofenceRadius > 0
              ? (activeBranch.geofenceRadius + 50.0).toInt()
              : 150)
        : null;

    void goToMonth(DateTime month) {
      setState(() {
        _selectedMonth = month;
        _recomputeFilteredHistory();
        _loadApprovedLeaves();
      });
    }

    // TAS-352: same stat style as the home card (TAS-384): HR web icon, the
    // number, one word under it. Absence is neutral (F-04).
    Widget stat(IconData icon, int value, String label) {
      return Expanded(
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            vertical: TashilSpacing.md,
            horizontal: TashilSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(TashilRadius.medium),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: TashilSpacing.xs),
              SkeletonSwitcher(
                loading: _monthLoading,
                skeleton: const Padding(
                  padding: EdgeInsets.symmetric(vertical: TashilSpacing.xs),
                  child: Skeleton(width: 40, height: 24),
                ),
                child: Text(
                  '$value',
                  key: ValueKey(value),
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // A compact read-only label (icon + text) on the zone section.
    Widget infoLabel(IconData icon, String text, {Color? color}) {
      final fg = color ?? colorScheme.onSurfaceVariant;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: TashilSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: textTheme.labelMedium?.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Card.filled(
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Month selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filled(
                  tooltip: AppLocalizations.of(context)!.previousMonth,
                  onPressed: () => goToMonth(
                    DateTime(_selectedMonth.year, _selectedMonth.month - 1),
                  ),
                  // TAS-387: Symbols chevrons mirror by themselves in RTL; the
                  // extra swap here pointed both arrows inward.
                  icon: const Icon(Symbols.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotionDurations.medium2,
                        child: Text(
                          DateFormat('MMMM yyyy', locale)
                              .format(_selectedMonth),
                          key: ValueKey(_selectedMonth),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (!isCurrentMonth)
                        TextButton.icon(
                          onPressed: () => goToMonth(trustedNow),
                          icon: const Icon(Symbols.restore_rounded),
                          label: Text(
                            AppLocalizations.of(context)!.currentMonth,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: AppLocalizations.of(context)!.nextMonth,
                  onPressed: () => goToMonth(
                    DateTime(_selectedMonth.year, _selectedMonth.month + 1),
                  ),
                  icon: const Icon(Symbols.chevron_right_rounded),
                ),
              ],
            ),
            if (_isOffline || _pendingOfflineCount > 0) ...[
              const SizedBox(height: TashilSpacing.sm),
              Wrap(
                spacing: TashilSpacing.sm,
                runSpacing: TashilSpacing.xs,
                children: [
                  if (_isOffline) _buildConnectivityBadge(context, l10n),
                  if (_pendingOfflineCount > 0)
                    KeyedSubtree(
                      key: const Key('attendance_pending_offline_count'),
                      child: _statusLabel(
                        context,
                        l10n.attPendingOfflineCount(_pendingOfflineCount),
                        Theme.of(context).colorScheme.secondaryContainer,
                        Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: TashilSpacing.md),

            // 2. Attendance and absence
            Row(
              children: [
                stat(
                  Symbols.how_to_reg_rounded,
                  attendedDays,
                  AppLocalizations.of(context)!.statAttended,
                ),
                const SizedBox(width: TashilSpacing.sm),
                stat(
                  Symbols.person_off_rounded,
                  absentDays,
                  AppLocalizations.of(context)!.statAbsent,
                ),
              ],
            ),
            // TAS-387 (playground: progress indicators): how far into the
            // month's work days the delegate is.
            const SizedBox(height: TashilSpacing.md),
            Semantics(
              label: AppLocalizations.of(context)!.attMonthProgress(
                attendedDays,
                MonthlyAttendanceStats.workDaysPerMonth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.attMonthProgressTitle,
                          style: textTheme.labelLarge,
                        ),
                      ),
                      SkeletonSwitcher(
                        loading: _monthLoading,
                        skeleton: const Skeleton(width: 40, height: 14),
                        child: Text(
                          Bidi.ltr(
                            '$attendedDays / ${MonthlyAttendanceStats.workDaysPerMonth}',
                          ),
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  if (_monthLoading)
                    const Skeleton(height: 4)
                  else
                    LinearProgressIndicator(
                      key: const Key('attendance_month_progress'),
                      value: (attendedDays /
                              MonthlyAttendanceStats.workDaysPerMonth)
                          .clamp(0.0, 1.0),
                    ),
                ],
              ),
            ),
            const SizedBox(height: TashilSpacing.sm),
            infoLabel(
              Symbols.info_rounded,
              AppLocalizations.of(context)!.attWorkPolicyNote,
            ),

            // 3. Geofence zone status
            if (_isGeofenceMode) ...[
              const SizedBox(height: TashilSpacing.md),
              AnimatedContainer(
                duration: AppMotionDurations.medium3,
                curve: AppMotionCurves.emphasized,
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: statusContainer,
                  borderRadius: BorderRadius.circular(TashilRadius.large),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Looking for the location: the kit loading
                        // indicator (unknown wait, playground «مؤشر
                        // التحميل», TAS-387); the radar shows the result.
                        if (isBusy)
                          const SizedBox.square(
                            dimension: 72,
                            child: Center(
                              child: LoadingIndicator(
                                key: Key('attendance_locating'),
                                size: 56,
                                contained: true,
                              ),
                            ),
                          )
                        else
                          _GeofenceRadarWidget(
                            animation: _radarAnimation,
                            isInside: _isInsideGeofence,
                            isChecking: false,
                            statusColor: statusColor,
                            onStatusColor: onStatusColor,
                          ),
                        const SizedBox(width: TashilSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    headerIcon,
                                    size: 18,
                                    color: onStatusContainer,
                                  ),
                                  const SizedBox(width: TashilSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      statusTitle,
                                      style: textTheme.titleSmall?.copyWith(
                                        color: onStatusContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: TashilSpacing.xs),
                              Text(
                                _locationStatusMessage ?? statusSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: onStatusContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    Wrap(
                      spacing: TashilSpacing.lg,
                      runSpacing: TashilSpacing.xs,
                      children: [
                        if (formattedDistance != null)
                          infoLabel(
                            _isInsideGeofence
                                ? Symbols.near_me_rounded
                                : Symbols.straighten_rounded,
                            AppLocalizations.of(
                              context,
                            )!.distanceLabel(formattedDistance),
                            color: onStatusContainer,
                          ),
                        if (activeBranch != null)
                          infoLabel(
                            Symbols.storefront_rounded,
                            activeBranch.branchName,
                            color: onStatusContainer,
                          ),
                        if (allowedRadius != null)
                          infoLabel(
                            Symbols.radar_rounded,
                            AppLocalizations.of(
                              context,
                            )!.radiusLabel(allowedRadius),
                            color: onStatusContainer,
                          ),
                      ],
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    // TAS-387: an action, so a full-width tonal button.
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const Key('attendance_recheck_button'),
                        onPressed: isBusy
                            ? null
                            : () => _detectNearestBranch(
                                showSnackBar: true,
                                silent: false,
                              ),
                        icon: isBusy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Symbols.refresh_rounded),
                        label: Text(
                          AppLocalizations.of(context)!.recheckLocation,
                        ),
                      ),
                    ),
                    // Open-settings help when the location check failed
                    // (TAS-283).
                    if (_locationFailure != null && !isBusy) ...[
                      const SizedBox(height: TashilSpacing.sm),
                      LocationHelpCard(
                        kind: _locationFailure!,
                        onRetry: () => _detectNearestBranch(
                          showSnackBar: true,
                          silent: false,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectivityBadge(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!_isOffline) return const SizedBox.shrink();
    // Offline is a state, not an error: a compact neutral label.
    return _statusLabel(
      context,
      l10n.networkStatusOffline,
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildChainFilterBar(BuildContext context) {
    final isArabic = Localizations.localeOf(
      context,
    ).languageCode.startsWith('ar');
    final chains = _availableChains.isNotEmpty
        ? _availableChains
        : [
            _formatChainName(
              widget.delegate.organizationName.isNotEmpty
                  ? widget.delegate.organizationName
                  : AppLocalizations.of(context)!.activeChain,
              isArabic: isArabic,
            ),
          ];

    // TAS-387: chain then branch, as two DropdownMenus (the chain one can be
    // typed into to search). A delegate can work in many chains, so a row of
    // chips did not scale. Hidden when there is nothing to choose.
    final l10n = AppLocalizations.of(context)!;
    if (chains.length <= 1 && _availableBranches.length <= 1) {
      return const SizedBox(height: TashilSpacing.sm);
    }
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: TashilSpacing.sm,
      ),
      // TAS-387: chain above branch, each across the width. Side by side
      // they were half wide and «كل السلاسل · 1» was cut (M31, 27 Nov).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            child: DropdownMenu<String>(
              key: const Key('attendance_chain_menu'),
              initialSelection: _chainFilter,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: chains.length > 6,
              leadingIcon: const Icon(Symbols.storefront_rounded),
              label: Text(l10n.attChainLabel),
              dropdownMenuEntries: [
                DropdownMenuEntry(
                  value: 'all',
                  label: '${l10n.allChains} · $_allAttendedDaysCount',
                ),
                for (final c in chains)
                  DropdownMenuEntry(
                    value: c,
                    label:
                        '${_formatChainName(c, isArabic: isArabic)} · ${_chainDaysCount[c] ?? 0}',
                  ),
              ],
              onSelected: (v) {
                if (v == null || v == _chainFilter) return;
                setState(() {
                  _chainFilter = v;
                  _branchFilter = 'all';
                  _recomputeFilteredHistory();
                });
              },
            ),
          ),
          const SizedBox(height: TashilSpacing.sm),
          SizedBox(
            child: DropdownMenu<String>(
              key: ValueKey('attendance_branch_menu_$_chainFilter'),
              initialSelection: _branchFilter,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              leadingIcon: const Icon(Symbols.location_on_rounded),
              label: Text(l10n.attBranchLabel),
              dropdownMenuEntries: [
                DropdownMenuEntry(value: 'all', label: l10n.attAllBranches),
                for (final b in _availableBranches)
                  DropdownMenuEntry(value: b, label: b),
              ],
              onSelected: (v) {
                if (v == null || v == _branchFilter) return;
                setState(() {
                  _branchFilter = v;
                  _recomputeFilteredHistory();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AttendanceState state) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    if (state is AttendanceLoading ||
        state is AttendanceInitial ||
        (state is AttendanceHistoryLoaded &&
            state.syncStatus == SyncStatus.inProgress)) {
      return _buildShimmerSkeleton();
    } else if (state is AttendanceError) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: TashilSpacing.lg),
            Text(
              state.message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TashilSpacing.lg),
            FilledButton(
              onPressed: () {
                _attendanceBloc.add(
                  HistoryRequested(
                    userId: widget.delegate.uid,
                    organizationId: '',
                    nationalityID: widget.delegate.nationalityID,
                    phoneNumber: widget.delegate.phoneNumber,
                  ),
                );
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    } else if (state is AttendanceHistoryLoaded) {
      final colorScheme = Theme.of(context).colorScheme;
      final isArabic = locale.startsWith('ar');
      final selectedChainLabel =
          _chainFilter != 'all' && _chainFilter != 'active'
          ? _formatChainName(_chainFilter, isArabic: isArabic)
          : _formatChainName(
              widget.delegate.organizationName.isNotEmpty
                  ? widget.delegate.organizationName
                  : AppLocalizations.of(context)!.activeChain,
              isArabic: isArabic,
            );

      if (_dayKeys.isEmpty && !_monthLoading) {
        return M3Refresh(
          onRefresh: () async {
            if (_isGeofenceMode) {
              _detectNearestBranch(showSnackBar: false);
            }
            _attendanceBloc.add(_syncRequest());
            _attendanceBloc.add(
              HistoryRequested(
                userId: widget.delegate.uid,
                organizationId: '',
                nationalityID: widget.delegate.nationalityID,
                phoneNumber: widget.delegate.phoneNumber,
              ),
            );
            _loadApprovedLeaves();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.only(
              top: TashilSpacing.md,
              bottom: 80,
            ),
            child: Column(
              children: [
                _buildUnifiedAttendanceCard(context),
                _buildChainFilterBar(context),
                const SizedBox(height: TashilSpacing.xl),
                // TAS-352: empty states use the text roles and one tonal
                // button, no tinted panels or hand-sized text.
                if (_chainFilter != 'all' && _allAttendedDaysCount > 0) ...[
                  Icon(
                    Symbols.storefront_rounded,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.attNoSessionsInChain(selectedChainLabel),
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.sm),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.attDaysInOtherChains(_allAttendedDaysCount),
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.lg),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _chainFilter = 'all';
                        _recomputeFilteredHistory();
                      });
                    },
                    icon: const Icon(Symbols.hub_rounded),
                    label: Text(AppLocalizations.of(context)!.allChains),
                  ),
                ] else ...[
                  Icon(
                    Symbols.event_note_rounded,
                    size: 56,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: TashilSpacing.lg),
                  Text(
                    l10n.noHistoryAvailable,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(height: TashilSpacing.md),
                if (!_isGeofenceMode)
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: TashilSpacing.xl,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.qr_code_scanner_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: TashilSpacing.sm),
                        Flexible(
                          child: Text(
                            l10n.scanQrInstruction,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
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

      return M3Refresh(
        onRefresh: () async {
          if (_isGeofenceMode) {
            _detectNearestBranch(showSnackBar: false);
          }
          _attendanceBloc.add(_syncRequest());
          _attendanceBloc.add(
            HistoryRequested(
              userId: widget.delegate.uid,
              organizationId: '',
              nationalityID: widget.delegate.nationalityID,
              phoneNumber: widget.delegate.phoneNumber,
            ),
          );
          _loadApprovedLeaves();
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsetsDirectional.only(
            top: TashilSpacing.md,
            bottom: 80,
          ),
          itemCount: _monthLoading
              ? 2 + 3
              : _dayKeys.length + 2 + (state.hasReachedMax ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildUnifiedAttendanceCard(context);
            }
            if (index == 1) {
              return _buildChainFilterBar(context);
            }
            if (_monthLoading) {
              return const Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: TashilSpacing.page,
                ),
                child: SummaryCardSkeleton(),
              );
            }
            final dayIndex = index - 2;
            if (dayIndex >= _dayKeys.length) {
              return state.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsetsDirectional.symmetric(
                        vertical: TashilSpacing.xxl,
                      ),
                      child: Center(child: LoadingIndicator()),
                    )
                  : const SizedBox(height: 100);
            }
            final dayKey = _dayKeys[dayIndex];
            final records = _groupedByDay[dayKey] ?? [];
            final dayDate = records.first.checkInTime;
            final fullDateStr = DateFormat(
              'EEEE، d MMMM yyyy',
              locale,
            ).format(dayDate);

            final colorScheme = Theme.of(context).colorScheme;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TAS-352: day header. The icon on the page follows the
                // card-icon rule (primary + onPrimary), the date is a title,
                // the count a compact label.
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    vertical: TashilSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(TashilSpacing.xs + 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.calendar_today_rounded,
                          size: 18,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: TashilSpacing.sm),
                      Expanded(
                        child: Text(
                          fullDateStr,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: colorScheme.onSurface),
                        ),
                      ),
                      _statusLabel(
                        context,
                        '${records.length}',
                        colorScheme.secondaryContainer,
                        colorScheme.onSecondaryContainer,
                      ),
                    ],
                  ),
                ),
                ...records.map((item) {
                  final isArabic = locale.startsWith('ar');
                  final inTime = DateFormat(
                    'hh:mm a',
                    locale,
                  ).format(item.checkInTime);
                  final effectiveOut = item.effectiveCheckOutTime;
                  final outTime = effectiveOut != null
                      ? DateFormat('hh:mm a', locale).format(effectiveOut)
                      : '--:--';
                  final rawBranchName =
                      item.branchName ?? l10n.unspecifiedBranch;
                  final cleanBranchName = _cleanBranchName(rawBranchName);
                  final chainName = _resolveOrgName(
                    item.organizationId,
                    branchName: item.branchName,
                    isArabic: isArabic,
                  );
                  String durationStr;
                  if (effectiveOut != null) {
                    final diff = effectiveOut.difference(item.checkInTime);
                    final hours = diff.inHours;
                    final minutes = diff.inMinutes.remainder(60);
                    // TAS-387: hh:mm, digits only, kept LTR in Arabic.
                    durationStr = Bidi.ltr(
                      '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}',
                    );
                  } else if (item.isMissingCheckOut) {
                    // TAS-362: zero hours until HR sets the check-out.
                    durationStr = l10n.missingCheckOut;
                  } else {
                    durationStr = l10n.inProgress;
                  }

                  // TAS-387: the session as a SummaryCard (P-07): branch and
                  // chain, the duration large on the end side, then check-in
                  // and check-out across the card.
                  final warn = Theme.of(
                    context,
                  ).extension<TashilSemanticColors>();
                  return SummaryCard(
                    icon: Symbols.storefront_rounded,
                    title: cleanBranchName,
                    subtitle: chainName,
                    trailingValue: durationStr,
                    trailingCaption: l10n.attDurationLabel,
                    trailingIcon: Symbols.timer_rounded,
                    trailingMuted: effectiveOut == null,
                    labels: [
                      if (item.isActive)
                        SummaryLabel(
                          l10n.active,
                          container: colorScheme.tertiaryContainer,
                          onContainer: colorScheme.onTertiaryContainer,
                        ),
                      if (item.isEffectiveAutoCheckOut)
                        Tooltip(
                          message: l10n.attAutoClosedNote,
                          child: SummaryLabel(
                            l10n.autoClosedAuto,
                            container: colorScheme.tertiaryContainer,
                            onContainer: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      if (!item.isSynced)
                        SummaryLabel(
                          l10n.pendingSync,
                          container: warn?.warningContainer ??
                              colorScheme.surfaceContainerHighest,
                          onContainer: warn?.onWarningContainer ??
                              colorScheme.onSurfaceVariant,
                        ),
                    ],
                    facts: [
                      SummaryFact(
                        icon: Symbols.login_rounded,
                        label: l10n.attCheckInLabel,
                        value: inTime,
                      ),
                      SummaryFact(
                        icon: item.isEffectiveAutoCheckOut
                            ? Symbols.auto_mode_rounded
                            : Symbols.logout_rounded,
                        label: l10n.attCheckOutLabel,
                        value: outTime,
                      ),
                    ],
                  );
                }),
                if (dayIndex < _dayKeys.length - 1) const Divider(height: 24),
              ],
            );
          },
        ),
      );
    }
    return Center(child: Text(l10n.somethingWentWrong));
  }

  /// Compact status label (TAS-352): a container role with its `on`
  /// colour, never a tinted card or an alpha border.
  Widget _statusLabel(
    BuildContext context,
    String text,
    Color container,
    Color onContainer,
  ) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: TashilSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: onContainer),
      ),
    );
  }

  String _buildFabLabel(
    BuildContext context, {
    required bool isCheckedIn,
    required Attendance? activeAttendance,
    required AppLocalizations l10n,
  }) {
    if (isCheckedIn) {
      return AppLocalizations.of(context)!.checkOut2;
    }

    if (_isCheckingLocation) {
      return AppLocalizations.of(context)!.attCheckingLocation;
    }

    return AppLocalizations.of(context)!.checkIn2;
  }

  Future<void> _fetchOrganizationSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.delegate.organizationUID)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _orgAttendanceMode = doc.data()?['attendanceMode'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBranches() async {
    if (!_isGeofenceMode) return;
    if (_isLoadingBranches) return;
    setState(() => _isLoadingBranches = true);
    try {
      final orgId = widget.delegate.organizationUID;
      final nested = <Branch>[];
      final root = <Branch>[];

      // 1. Fetch from organizations/{orgId}/branches
      try {
        final snap = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .collection('branches')
            .get();
        for (final doc in snap.docs) {
          // The path is the chain: a stale organizationUID in the doc
          // must not attribute the branch to another chain (TAS-333).
          nested.add(
            BranchModel.fromMap({
              ...doc.data(),
              'organizationUID': orgId,
            }, id: doc.id),
          );
        }
      } catch (e, st) {
        debugPrint('Attendance: nested branches fetch failed: $e\n$st');
      }

      // 2. Always also fetch root branches. A stub nested doc (name
      // only, no coordinates) must not hide the geo-enabled root
      // branches (M31 ce97cb3: outside message had no name/distance).
      try {
        final snap = await FirebaseFirestore.instance
            .collection('branches')
            .where('organizationUID', isEqualTo: orgId)
            .get();
        for (final doc in snap.docs) {
          root.add(BranchModel.fromMap(doc.data(), id: doc.id));
        }
      } catch (e, st) {
        debugPrint('Attendance: root branches fetch failed: $e\n$st');
      }

      var branchesList = keepMemberChainBranches(
        mergeOrgBranches(nested, root),
        {orgId},
      );
      // TAS-363: keep the coordinates for a check-in without network, and
      // fall back to them when nothing could be read.
      final branchCache = sl.isRegistered<OfflineBranchCache>()
          ? sl<OfflineBranchCache>()
          : null;
      if (branchesList.isNotEmpty) {
        branchCache?.saveAll(orgId, branchesList).ignore();
      } else if (_isOffline && branchCache != null) {
        branchesList = branchCache.branchesOf(orgId);
      }
      for (final b in branchesList) {
        BranchDisplayCache.instance.registerFromMap({
          'branchName': b.branchName,
          'displayNameAr': b.branchName,
          'organizationUID': b.organizationUID ?? orgId,
        }, docId: b.id);
      }

      if (mounted) {
        setState(() {
          _orgBranches = branchesList;
          _isLoadingBranches = false;
          if (branchesList.isEmpty) {
            _locationStatusMessage = AppLocalizations.of(
              context,
            )!.noBranchesForOrg;
            _isInsideGeofence = false;
          }
        });

        // Only scan GPS if branches exist; otherwise look in the other
        // chains straight away (TAS-245).
        if (branchesList.isNotEmpty) {
          _detectNearestBranch(
            showSnackBar: false,
            silent: true,
            allowChainSwitch: true,
          );
        } else {
          _autoLocateAcrossChains(null);
        }
      }
    } catch (e, st) {
      debugPrint('Attendance: _loadBranches failed: $e\n$st');
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _detectNearestBranch({
    bool showSnackBar = false,
    bool silent = false,
    bool allowChainSwitch = false,
  }) async {
    if (!mounted || _isCheckingLocation) return;
    if (_orgBranches.isEmpty) {
      setState(() {
        _isCheckingLocation = false;
        _locationStatusMessage = AppLocalizations.of(context)!.noBranchesForOrg;
      });
      if (allowChainSwitch) {
        _autoLocateAcrossChains(null, force: true);
      }
      return;
    }

    setState(() {
      _isCheckingLocation = true;
      _locationStatusMessage = AppLocalizations.of(context)!.attLocatingYou;
    });

    final position = await _getCurrentLocation(
      context,
      actionType: 'فحص النطاق الجغرافي',
      silent: silent,
    );

    if (!mounted) return;

    if (position == null) {
      setState(() {
        _isCheckingLocation = false;
        _locationStatusMessage = AppLocalizations.of(
          context,
        )!.attLocationUnavailable;
      });
      return;
    }

    _currentPosition = position;

    Branch? closest;
    double minDistance = double.infinity;
    Branch? matched;

    for (final branch in _orgBranches) {
      if (branch.latitude == 0.0 && branch.longitude == 0.0) continue;

      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branch.latitude,
        branch.longitude,
      );

      if (dist < minDistance) {
        minDistance = dist;
        closest = branch;
      }

      if (dist <= allowedGeofenceRadius(branch)) {
        matched = branch;
      }
    }

    final weakSignal =
        matched == null &&
        closest != null &&
        minDistance.isFinite &&
        isOutsideBecauseOfWeakSignal(
          distanceMeters: minDistance,
          accuracyMeters: position.accuracy,
          radiusMeters: allowedGeofenceRadius(closest),
        );

    setState(() {
      _isCheckingLocation = false;
      _nearestBranch = closest;
      _distanceToNearest = minDistance.isFinite ? minDistance : null;
      _matchedBranch = matched;
      _isInsideGeofence = matched != null;

      if (matched != null) {
        final branchLabel = BranchDisplayCache.instance.displayName(
          matched.branchName,
        );
        _locationStatusMessage =
            _hasSeveralChains &&
                widget.delegate.organizationName.trim().isNotEmpty
            ? AppLocalizations.of(context)!.attYouAreAtChainBranch(
                widget.delegate.organizationName.trim(),
                branchLabel,
              )
            : AppLocalizations.of(context)!.attYouAreWithinBranch(branchLabel);
      } else if (closest != null && minDistance.isFinite) {
        // TAS-396: an imprecise fix whose error circle reaches the branch is
        // a weak signal, not "move closer". The geofence decision is
        // unchanged.
        _locationStatusMessage = weakSignal
            ? AppLocalizations.of(context)!.attWeakSignalNearBranch
            : AppLocalizations.of(context)!.attMoveCloser;
        if (weakSignal && !silent) {
          _locationFailure = LocationFailureKind.weakSignal;
        }
      } else {
        _locationStatusMessage = AppLocalizations.of(
          context,
        )!.attOutsideApprovedBranches;
      }
    });

    if (matched == null && (allowChainSwitch || showSnackBar)) {
      // Outside every branch of this chain: maybe inside another chain's
      // branch. The refresh button (showSnackBar) always re-checks.
      _autoLocateAcrossChains(position, force: showSnackBar);
    }

    if (showSnackBar && mounted) {
      if (_isInsideGeofence && matched != null) {
        AppSnackBar.showSuccess(
          context,
          AppLocalizations.of(context)!.attInsideBranchWithDistance(
            BranchDisplayCache.instance.displayName(matched.branchName),
            minDistance.toInt(),
          ),
        );
      } else if (weakSignal) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationWeakSignal,
        );
      } else if (closest != null) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.attOutsideBranchWithRadius(
            minDistance.toInt(),
            allowedGeofenceRadius(closest).toInt(),
          ),
        );
      }
    }
  }

  /// Loads branches and attendance mode of the delegate's other chains,
  /// once per open chain (TAS-245).
  Future<void> _loadOtherChainBranches() async {
    if (_otherChainBranches != null) return;
    final db = FirebaseFirestore.instance;
    final orgIds = _otherChainOrgIds.toList();
    final geofenced = <String>{};
    final byOrg = <String, List<Branch>>{};

    for (final org in orgIds) {
      try {
        final doc = await db.collection('organizations').doc(org).get();
        final data = doc.data() ?? const <String, dynamic>{};
        final name = (data['name'] ?? '').toString().trim();
        final fallbackName = widget.memberships
            .firstWhere((m) => m.organizationUID == org)
            .organizationName;
        if (isGeofenceAttendanceMode(
          data['attendanceMode'] as String?,
          name.isNotEmpty ? name : fallbackName,
        )) {
          geofenced.add(org);
        }
      } catch (e, st) {
        debugPrint('Attendance: org settings for $org failed: $e\n$st');
      }
    }

    // Root `branches` hold the coordinates; whereIn takes up to 10 values.
    for (var i = 0; i < orgIds.length; i += 10) {
      final chunk = orgIds.sublist(i, (i + 10).clamp(0, orgIds.length));
      try {
        final snap = await db
            .collection('branches')
            .where('organizationUID', whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          final b = BranchModel.fromMap(d.data(), id: d.id);
          final org = (b.organizationUID ?? '').trim();
          if (org.isEmpty) continue;
          (byOrg[org] ??= []).add(b);
        }
      } catch (e, st) {
        debugPrint('Attendance: other-chain branches fetch failed: $e\n$st');
      }
    }

    final all = <Branch>[];
    for (final org in orgIds) {
      all.addAll(mergeOrgBranches(const [], byOrg[org] ?? const []));
    }
    _otherGeofenceOrgIds
      ..clear()
      ..addAll(geofenced);
    // Only branches of the delegate's own chains (TAS-333).
    _otherChainBranches = keepMemberChainBranches(all, _memberOrgIds);
  }

  /// True when the delegate has an open check-in in any chain, or when that
  /// cannot be known yet (then we do not switch).
  Future<bool> _hasOpenSession() async {
    AttendanceState s = _attendanceBloc.state;
    if (s is! AttendanceHistoryLoaded) {
      try {
        s = await _attendanceBloc.stream
            .firstWhere((e) => e is AttendanceHistoryLoaded)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        return true;
      }
    }
    return (s as AttendanceHistoryLoaded).activeAttendance != null;
  }

  /// Looks for the branch the delegate stands in across all their chains
  /// and switches chain when it belongs to another one (TAS-245).
  /// Runs once per open chain unless [force] (the refresh button).
  Future<void> _autoLocateAcrossChains(
    Position? position, {
    bool force = false,
  }) async {
    if (!_canAutoSwitchChain || _autoLocateRunning) return;
    if (_autoLocateDone && !force) return;
    _autoLocateDone = true;
    _autoLocateRunning = true;
    try {
      position ??= await _getCurrentLocation(
        context,
        actionType: 'تحديد الفرع تلقائياً',
        silent: true,
      );
      if (position == null || !mounted) return;
      await _loadOtherChainBranches();
      if (!mounted) return;

      final result = locateBranchAcrossChains<Delegate>(
        latitude: position.latitude,
        longitude: position.longitude,
        branches: [..._orgBranches, ...?_otherChainBranches],
        currentOrgId: widget.delegate.organizationUID,
        memberships: widget.memberships,
        orgIdOf: (d) => d.organizationUID,
        geofenceOrgIds: _otherGeofenceOrgIds,
      );
      if (result.outcome == AutoBranchOutcome.currentChain ||
          result.outcome == AutoBranchOutcome.none) {
        return;
      }

      final branch = result.branch!;
      final branchLabel = BranchDisplayCache.instance.displayName(
        branch.branchName,
      );
      final chainLabel = result.memberships.first.organizationName.trim();
      final l10n = AppLocalizations.of(context)!;

      if (await _hasOpenSession()) {
        if (mounted) {
          AppSnackBar.showInfo(
            context,
            l10n.autoSwitchBlockedActiveSession(branchLabel, chainLabel),
          );
        }
        return;
      }
      if (!mounted) return;

      Delegate? target;
      if (result.outcome == AutoBranchOutcome.switchChain) {
        target = result.memberships.first;
      } else {
        target = await _pickCompany(
          result.memberships,
          l10n.autoSwitchPickCompany(branchLabel, chainLabel),
        );
      }
      if (target == null || !mounted) return;
      await widget.onAutoSwitchChain?.call(target, branchLabel);
    } catch (e, st) {
      debugPrint('Attendance: auto chain locate failed: $e\n$st');
    } finally {
      _autoLocateRunning = false;
    }
  }

  /// Lets the delegate pick the company when they have several in the
  /// chain of the branch they stand in (branches carry no company).
  Future<Delegate?> _pickCompany(List<Delegate> options, String title) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<Delegate>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TashilSpacing.xl,
                0,
                TashilSpacing.xl,
                TashilSpacing.md,
              ),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final d in options)
              ListTile(
                leading: Icon(Symbols.business_rounded, color: cs.primary),
                title: Text(
                  d.companyName.isNotEmpty ? d.companyName : d.organizationName,
                ),
                onTap: () => Navigator.of(sheetContext).pop(d),
              ),
            const SizedBox(height: TashilSpacing.md),
          ],
        ),
      ),
    );
  }

  /// TAS-397: a delegate refused outside the geofence can report that the
  /// branch's position is wrong. The supervisor reviews the report; nothing
  /// moves the branch by itself.
  bool get _canReportBranchLocation =>
      !widget.viewOnly &&
      widget.delegate.role == UserRole.delegate &&
      widget.delegate.companyUID.trim().isNotEmpty &&
      _currentPosition != null &&
      _orgBranches.isNotEmpty;

  void _showOutsideGeofence(BuildContext ctx, String message) =>
      showGeofenceRefusalSnackBar(
        ctx,
        message,
        onReport: _canReportBranchLocation ? _openBranchLocationReport : null,
      );

  Future<void> _openBranchLocationReport() async {
    final position = _currentPosition;
    if (position == null || !mounted) return;
    await showReportBranchLocationSheet(
      context: context,
      delegate: widget.delegate,
      branches: _orgBranches,
      at: ReportPosition.fromPosition(position),
      suggestedBranchId: _nearestBranch?.id,
    );
  }

  Future<void> _handleGeofenceAction({
    required bool isCheckedIn,
    required Attendance? activeAttendance,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final parentContext = context;
    final attendanceBloc = _attendanceBloc;

    await _detectNearestBranch(showSnackBar: false, silent: false);

    if (!parentContext.mounted) return;

    if (_currentPosition == null) {
      AppSnackBar.showError(parentContext, l10n.attEnsureGps);
      return;
    }

    final branchToUse = _matchedBranch ?? _nearestBranch;
    if (!_isInsideGeofence || branchToUse == null) {
      final nearestName = BranchDisplayCache.instance
          .displayName((_nearestBranch ?? _matchedBranch)?.branchName)
          .trim();
      final distStr =
          (_distanceToNearest != null && _distanceToNearest!.isFinite)
          ? l10n.distanceMeters(_distanceToNearest!.toInt())
          : '';
      final action = isCheckedIn
          ? l10n.attActionCheckOut
          : l10n.attActionCheckIn;
      final message = switch (classifyGeofenceOutside(
        branchName: nearestName,
        distanceMeters: _distanceToNearest,
      )) {
        GeofenceOutsideKind.atBranch => l10n.attCannotActOutsideAtBranch(
          action,
          nearestName,
          distStr,
        ),
        GeofenceOutsideKind.branchOnly => l10n.attCannotActOutsideBranchOnly(
          action,
          nearestName,
        ),
        GeofenceOutsideKind.distanceOnly => l10n.attCannotActOutside(
          action,
          distStr,
        ),
        GeofenceOutsideKind.noDetails => l10n.attCannotActOutsideNoDistance(
          action,
        ),
      };
      _showOutsideGeofence(parentContext, message);
      return;
    }

    final branchRef = AttendanceBranchRef.fromBranch(
      branchToUse,
      fallbackOrganizationUID: widget.delegate.organizationUID,
    );
    if (_refuseBranchOfOtherChain(parentContext, branchRef)) return;
    final branchName = branchRef.branchName;
    final position = _currentPosition!;

    // Dynamically resolve latest active attendance to prevent stale closure state
    Attendance? currentActive = activeAttendance;
    final currentState = attendanceBloc.state;
    if (currentState is AttendanceHistoryLoaded &&
        currentState.activeAttendance != null) {
      currentActive = currentState.activeAttendance;
    } else if (_rawHistory.isNotEmpty) {
      currentActive = _rawHistory.cast<Attendance?>().firstWhere(
        (a) => a?.checkOutTime == null,
        orElse: () => null,
      );
    }
    final bool currentlyCheckedIn = isCheckedIn || currentActive != null;

    if (currentlyCheckedIn && currentActive != null) {
      final now = _getTrustedNow();
      final isPreviousDay =
          currentActive.checkInTime.year != now.year ||
          currentActive.checkInTime.month != now.month ||
          currentActive.checkInTime.day != now.day;

      if (isPreviousDay) {
        _showPreviousDayCheckoutDialog(
          parentContext,
          currentActive,
          branchRef,
          position,
          attendanceBloc,
          l10n,
        );
      } else if (_isSameBranchAsActive(currentActive, branchRef)) {
        if (!await confirmEarlyCheckOutIfNeeded(
          parentContext,
          checkInTime: currentActive.checkInTime,
          now: now,
        )) {
          return;
        }
        attendanceBloc.add(
          CheckOutRequested(
            attendanceId: currentActive.id,
            userId: widget.delegate.uid,
            organizationId: widget.delegate.organizationUID,
            lat: position.latitude,
            long: position.longitude,
          ),
        );
      } else {
        _showForgotCheckoutDialog(
          parentContext,
          currentActive,
          branchRef,
          position,
          attendanceBloc,
          l10n,
        );
      }
    } else {
      await _checkIn(attendanceBloc, branchRef, position);
      if (parentContext.mounted) {
        AppSnackBar.showInfo(parentContext, l10n.attCheckingInAt(branchName));
      }
    }
  }

  Future<void> _showQRScanner(
    BuildContext context,
    bool isCheckedIn,
    Attendance? activeAttendance,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final attendanceBloc = _attendanceBloc;
    final parentContext = context;
    final action = isCheckedIn ? l10n.checkOut : l10n.checkIn;

    return showModalBottomSheet<AttendanceBranchRef?>(
      context: context,
      sheetAnimationStyle: m3SheetAnimation,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScannerModal(
        action: action,
        delegateOrganizationUID: widget.delegate.organizationUID,
      ),
    ).then((scannedRef) async {
      if (scannedRef != null && scannedRef.branchName.isNotEmpty) {
        final scannedBranch = scannedRef.branchName;
        if (!parentContext.mounted) return;
        // The scanned branch is the one recorded and checked; a code of
        // another chain is refused, never swapped for a nearby branch.
        if (_refuseBranchOfOtherChain(parentContext, scannedRef)) return;
        AppSnackBar.showInfo(
          parentContext,
          AppLocalizations.of(parentContext)!.attFetchingLocation,
        );

        final position = await _getCurrentLocation(
          parentContext,
          branchName: scannedBranch,
          actionType: isCheckedIn ? 'تسجيل انصراف' : 'تسجيل حضور',
        );
        if (position != null && parentContext.mounted) {
          // Dynamically resolve latest active attendance to prevent stale closure state
          Attendance? currentActive = activeAttendance;
          final currentState = attendanceBloc.state;
          if (currentState is AttendanceHistoryLoaded &&
              currentState.activeAttendance != null) {
            currentActive = currentState.activeAttendance;
          } else if (_rawHistory.isNotEmpty) {
            currentActive = _rawHistory.cast<Attendance?>().firstWhere(
              (a) => a?.checkOutTime == null,
              orElse: () => null,
            );
          }
          final bool currentlyCheckedIn = isCheckedIn || currentActive != null;

          if (currentlyCheckedIn && currentActive != null) {
            final now = _getTrustedNow();
            final isPreviousDay =
                currentActive.checkInTime.year != now.year ||
                currentActive.checkInTime.month != now.month ||
                currentActive.checkInTime.day != now.day;

            if (isPreviousDay) {
              _showPreviousDayCheckoutDialog(
                parentContext,
                currentActive,
                scannedRef,
                position,
                attendanceBloc,
                l10n,
              );
            } else if (_isSameBranchAsActive(currentActive, scannedRef)) {
              if (!await confirmEarlyCheckOutIfNeeded(
                parentContext,
                checkInTime: currentActive.checkInTime,
                now: now,
              )) {
                return;
              }
              attendanceBloc.add(
                CheckOutRequested(
                  attendanceId: currentActive.id,
                  userId: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                  lat: position.latitude,
                  long: position.longitude,
                ),
              );
            } else {
              _showForgotCheckoutDialog(
                parentContext,
                currentActive,
                scannedRef,
                position,
                attendanceBloc,
                l10n,
              );
            }
          } else {
            await _checkIn(attendanceBloc, scannedRef, position);
            if (parentContext.mounted) {
              AppSnackBar.showInfo(
                parentContext,
                AppLocalizations.of(context)!.attCheckingInAt(scannedBranch),
              );
            }
          }
        }
      } else if (scannedRef != null && scannedRef.branchName.isEmpty) {
        if (!parentContext.mounted) return;
        AppSnackBar.showError(parentContext, l10n.invalidQRCode);
      }
    });
  }

  bool _isSameBranchAsActive(Attendance active, AttendanceBranchRef target) {
    if (active.branchName == null || active.branchName!.trim().isEmpty) {
      return true;
    }
    final activeRef = AttendanceBranchRef.fromAttendanceLog({
      'branchId': active.branchId,
      'branchOrganizationUID': active.branchOrganizationUID,
      'organizationId': active.organizationId,
      'branchName': active.branchName,
    });
    return attendanceSameBranch(activeRef, target);
  }

  Future<void> _checkIn(
    AttendanceBloc bloc,
    AttendanceBranchRef branchRef,
    Position position,
  ) async {
    final deviceInfo = await _getDeviceInfo();

    bloc.add(
      CheckInRequested(
        userId: widget.delegate.uid,
        companyId: widget.delegate.companyUID,
        organizationId: widget.delegate.organizationUID,
        deviceInfo: deviceInfo,
        lat: position.latitude,
        long: position.longitude,
        branchName: branchRef.branchName,
        branchId: branchRef.branchId,
        branchOrganizationUID: branchRef.branchOrganizationUID,
        delegateName: widget.delegate.fullName.isNotEmpty
            ? widget.delegate.fullName
            : null,
        phoneNumber: widget.delegate.phoneNumber.isNotEmpty
            ? widget.delegate.phoneNumber
            : null,
        companyName: widget.delegate.companyName.isNotEmpty
            ? widget.delegate.companyName
            : null,
        personalPhotoURL: widget.delegate.personalPhotoForCopy,
        qrProof: branchRef.qrProof,
      ),
    );
  }

  Future<Position?> _getCurrentLocation(
    BuildContext context, {
    String? branchName,
    String? actionType,
    bool silent = false,
  }) async {
    if (!WebRuntimePolicy.checkInEnabled) {
      if (!silent && context.mounted) {
        AppSnackBar.showInfo(context, WebRuntimePolicy.checkInWebMessage);
      }
      return null;
    }
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return null;
      if (!silent) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationServicesOff,
        );
        _reportLocationFailure(context, LocationFailureKind.serviceOff);
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        if (!silent) {
          AppSnackBar.showError(
            context,
            AppLocalizations.of(context)!.locationPermissionDenied2,
          );
          _reportLocationFailure(context, LocationFailureKind.permissionDenied);
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      if (!silent) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationPermissionDeniedForever,
        );
        _reportLocationFailure(
          context,
          LocationFailureKind.permissionDeniedForever,
        );
      }
      return null;
    }

    try {
      // High then medium accuracy, then a recent last known position only
      // (TAS-278, TAS-279, TAS-280).
      final fix = await _locationFetcher.fetch();
      if (fix == null) {
        if (context.mounted && !silent) {
          // TAS-396: weak signal (imprecise position) vs no position at all.
          final weak = _locationFetcher.lastFailure?.reason ==
              LocationFetchFailureReason.weakSignal;
          AppSnackBar.showError(
            context,
            locationFailureMessage(
              AppLocalizations.of(context)!,
              _locationFetcher.lastFailure,
            ),
          );
          _reportLocationFailure(
            context,
            weak ? LocationFailureKind.weakSignal : LocationFailureKind.noFix,
          );
        }
        return null;
      }
      final position = fix.position;
      if (!silent && _locationFailure != null && mounted) {
        setState(() => _locationFailure = null);
      }

      // --- Anti-Fraud: Fake GPS / Mock Location Detection ---
      if (position.isMocked) {
        _logMockViolation(
          position,
          branchName: branchName,
          actionType: actionType,
        );
        if (context.mounted && !silent) {
          AppSnackBar.showError(
            context,
            AppLocalizations.of(context)!.fakeGpsDetected,
          );
        }
        return null;
      }

      return position;
    } catch (e) {
      if (context.mounted && !silent) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationError,
        );
        _reportLocationFailure(context, LocationFailureKind.error);
      }
      return null;
    }
  }

  /// Shows the open-settings help after a failed location check (TAS-283).
  /// Geofence mode shows it inside the zone status card; the QR flow has no
  /// such card, so it gets a bottom sheet instead.
  void _reportLocationFailure(BuildContext context, LocationFailureKind kind) {
    if (!mounted) return;
    setState(() => _locationFailure = kind);
    if (_isGeofenceMode || !context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: m3SheetAnimation,
      isScrollControlled: true,
      useSafeArea: true,
      // TAS-352: shape and drag handle come from the theme (C-28).
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.lg,
            0,
            TashilSpacing.lg,
            TashilSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LocationHelpCard(kind: kind),
            ],
          ),
        );
      },
    );
  }

  Future<String> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        return 'Web Browser';
      }
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        return '${iosInfo.name} ${iosInfo.systemName} ${iosInfo.systemVersion}';
      }
    } catch (_) {}
    return 'Unknown Device';
  }

  void _logMockViolation(
    Position position, {
    String? branchName,
    String? actionType,
  }) {
    _getDeviceInfo()
        .then((device) {
          SecurityAuditService.logMockLocationViolation(
            delegate: widget.delegate,
            position: position,
            deviceModel: device,
            branchName: branchName,
            actionType: actionType,
          );
        })
        .catchError((_) {});
  }

  void _showForgotCheckoutDialog(
    BuildContext context,
    Attendance activeAttendance,
    AttendanceBranchRef newBranch,
    Position position,
    AttendanceBloc bloc,
    AppLocalizations l10n,
  ) {
    // TAS-352 (C-27): kit dialog, text buttons, confirm last.
    showTashilDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.forgotCheckoutTitle),
          content: Text(
            l10n.forgotCheckoutMessage(
              activeAttendance.branchName ?? l10n.unspecifiedBranch,
              newBranch.branchName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final deviceInfo = await _getDeviceInfo();
                bloc.add(
                  CheckOutAndCheckInRequested(
                    oldAttendanceId: activeAttendance.id,
                    userId: widget.delegate.uid,
                    companyId: widget.delegate.companyUID,
                    organizationId: widget.delegate.organizationUID,
                    deviceInfo: deviceInfo,
                    lat: position.latitude,
                    long: position.longitude,
                    branchName: newBranch.branchName,
                    branchId: newBranch.branchId,
                    branchOrganizationUID: newBranch.branchOrganizationUID,
                    delegateName: widget.delegate.fullName.isNotEmpty
                        ? widget.delegate.fullName
                        : null,
                    phoneNumber: widget.delegate.phoneNumber.isNotEmpty
                        ? widget.delegate.phoneNumber
                        : null,
                    companyName: widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : null,
                    personalPhotoURL: widget.delegate.personalPhotoForCopy,
                    qrProof: newBranch.qrProof,
                  ),
                );
              },
              child: Text(l10n.confirmAction),
            ),
          ],
        );
      },
    );
  }

  void _showPreviousDayCheckoutDialog(
    BuildContext context,
    Attendance activeAttendance,
    AttendanceBranchRef newBranch,
    Position position,
    AttendanceBloc bloc,
    AppLocalizations l10n,
  ) {
    // TAS-352 (C-27): kit dialog, text buttons, confirm last.
    showTashilDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.forgotCheckoutTitle),
          content: Text(
            l10n.previousDayCheckoutMessage(
              activeAttendance.branchName ?? l10n.unspecifiedBranch,
              newBranch.branchName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final deviceInfo = await _getDeviceInfo();
                bloc.add(
                  CheckOutAndCheckInRequested(
                    oldAttendanceId: activeAttendance.id,
                    userId: widget.delegate.uid,
                    companyId: widget.delegate.companyUID,
                    organizationId: widget.delegate.organizationUID,
                    deviceInfo: deviceInfo,
                    lat: position.latitude,
                    long: position.longitude,
                    branchName: newBranch.branchName,
                    branchId: newBranch.branchId,
                    branchOrganizationUID: newBranch.branchOrganizationUID,
                    delegateName: widget.delegate.fullName.isNotEmpty
                        ? widget.delegate.fullName
                        : null,
                    phoneNumber: widget.delegate.phoneNumber.isNotEmpty
                        ? widget.delegate.phoneNumber
                        : null,
                    companyName: widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : null,
                    personalPhotoURL: widget.delegate.personalPhotoForCopy,
                    qrProof: newBranch.qrProof,
                  ),
                );
              },
              child: Text(l10n.confirmAction),
            ),
          ],
        );
      },
    );
  }

  /// First load: skeletons of the session cards (kit SummaryCardSkeleton,
  /// playground «هيكل التحميل», TAS-387).
  Widget _buildShimmerSkeleton() {
    return ListView.builder(
      key: const Key('attendance_skeleton'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.page,
        TashilSpacing.lg,
        TashilSpacing.page,
        80,
      ),
      itemCount: 5,
      itemBuilder: (context, index) => const SummaryCardSkeleton(),
    );
  }
}

class _ScannerModal extends StatefulWidget {
  final String action;
  final String delegateOrganizationUID;

  const _ScannerModal({
    required this.action,
    required this.delegateOrganizationUID,
  });

  @override
  State<_ScannerModal> createState() => _ScannerModalState();
}

class _ScannerModalState extends State<_ScannerModal>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final AnimationController _laserController;
  bool _isProcessing = false;
  bool _lensChecked = false;
  late final TrustedTimeService _timeService;

  @override
  void initState() {
    super.initState();
    try {
      _timeService = sl.isRegistered<TrustedTimeService>()
          ? sl<TrustedTimeService>()
          : TrustedTimeService();
    } catch (_) {
      _timeService = TrustedTimeService();
    }

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
      facing: CameraFacing.back,
    );
    // TAS-290: once the camera runs, move to the close-focus lens (iOS).
    _scannerController.addListener(_onScannerState);

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  void _onScannerState() {
    if (_lensChecked || !_scannerController.value.isRunning) return;
    _lensChecked = true;
    preferCloseRangeLens(_scannerController);
  }

  @override
  void dispose() {
    _scannerController.removeListener(_onScannerState);
    _laserController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TAS-352: the scanner sits over the camera, so it always uses the dark
    // theme's roles (scrim, onSurface) instead of Colors.black / white.
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark
        ? base
        : AppTheme.darkTheme();
    return Theme(data: dark, child: Builder(builder: _buildScanner));
  }

  Widget _buildScanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final isCheckedIn = widget.action == l10n.checkOut;
    final color = isCheckedIn ? colorScheme.secondary : colorScheme.primary;
    final locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: colorScheme.scrim,
      body: Stack(
        children: [
          // TAS-290: tap the preview to focus there.
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                _scannerController
                    .setFocusPoint(
                      focusPointFor(d.localPosition, constraints.biggest),
                    )
                    .catchError((Object _) {});
              },
              child: MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  if (!mounted || _isProcessing) return;
                  _isProcessing = true;

                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    HapticFeedback.mediumImpact();
                    final String rawValue = barcodes.first.rawValue ?? '';
                    AttendanceBranchRef? scannedRef;
                    try {
                      final dynamic decoded = jsonDecode(rawValue);

                      if (decoded is Map<String, dynamic> &&
                          decoded['type'] == 'attendance') {
                        scannedRef = AttendanceBranchRef.fromQrMap(
                          decoded,
                          delegateOrganizationUID:
                              widget.delegateOrganizationUID,
                        );
                        if (scannedRef.branchName.isEmpty &&
                            decoded['branch'] is String) {
                          scannedRef = AttendanceBranchRef.legacyNameOnly(
                            branchName: decoded['branch'] as String,
                            delegateOrganizationUID:
                                widget.delegateOrganizationUID,
                          );
                        }
                        // TAS-372: the server checks the signature/version.
                        scannedRef = scannedRef.withQrProof(
                          attendanceQrProof(decoded),
                        );
                      }
                    } catch (_) {
                      if (rawValue.isNotEmpty && !rawValue.startsWith('{')) {
                        scannedRef = AttendanceBranchRef.legacyNameOnly(
                          branchName: rawValue.trim(),
                          delegateOrganizationUID:
                              widget.delegateOrganizationUID,
                        ).withQrProof(attendanceQrProof(null));
                      }
                    }

                    if (mounted) {
                      _scannerController.stop();
                      Navigator.pop(context, scannedRef);
                    }
                  } else {
                    _isProcessing = false;
                  }
                },
              ),
            ),
          ),

          // Central Scan Target Overlay with glowing corners and laser line
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outline,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(
                        TashilRadius.extraLarge,
                      ),
                    ),
                  ),
                  // Animated Scanner Laser Line
                  AnimatedBuilder(
                    animation: _laserController,
                    builder: (context, child) {
                      return Positioned(
                        top: 20 + (_laserController.value * 220),
                        left: 15,
                        right: 15,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(
                              TashilRadius.full,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Top Header Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TashilSpacing.xl,
                TashilSpacing.xxl + TashilSpacing.lg,
                TashilSpacing.xl,
                TashilSpacing.xl,
              ),
              color: colorScheme.scrim,
              child: Column(
                children: [
                  Text(
                    l10n.scanForAction(widget.action),
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  Text(
                    l10n.pointCameraToQR(widget.action),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  // TAS-290: hint for phones that cannot focus very close.
                  Text(
                    locale == 'ar'
                        ? 'لو الصورة مش واضحة، بعّد الموبايل شوية أو المس الكود'
                        : 'If the image is blurry, move the phone back a little or tap the code',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Bar with Live Ticking Time & Date
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TashilSpacing.xl,
                TashilSpacing.xl,
                TashilSpacing.xl,
                TashilSpacing.xxl,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(TashilRadius.extraLarge),
                ),
              ),
              child: StreamBuilder<DateTime>(
                stream: _timeService.liveClockStream,
                initialData: _timeService.now,
                builder: (context, snapshot) {
                  final currentTime = snapshot.data ?? _timeService.now;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE، d MMMM yyyy',
                              locale,
                            ).format(currentTime),
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: TashilSpacing.xs / 2),
                          Row(
                            children: [
                              Text(
                                DateFormat(
                                  'hh:mm:ss a',
                                  locale,
                                ).format(currentTime),
                                style: textTheme.headlineSmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_timeService.isSynced) ...[
                                  const SizedBox(width: TashilSpacing.sm),
                                Builder(
                                  builder: (context) {
                                    final sem = Theme.of(
                                      context,
                                    ).extension<TashilSemanticColors>();
                                    return Container(
                                      padding:
                                          const EdgeInsetsDirectional.symmetric(
                                            horizontal: TashilSpacing.sm,
                                            vertical: 2,
                                          ),
                                      decoration: BoxDecoration(
                                        color: sem?.successContainer ??
                                            colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          TashilRadius.small,
                                        ),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.trustedTime,
                                        style: textTheme.labelSmall?.copyWith(
                                          color: sem?.onSuccessContainer ??
                                              colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(TashilSpacing.md),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCheckedIn
                              ? Symbols.logout_rounded
                              : Symbols.login_rounded,
                          color: colorScheme.onPrimary,
                          size: 28,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Close Button
          PositionedDirectional(
            top: TashilSpacing.xxl + TashilSpacing.md,
            end: TashilSpacing.lg,
            child: IconButton.filledTonal(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Symbols.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Material Design 3 Expressive Radar Wave Widget
/// Features dual concentric pulsing ripples with monotonic opacity decay (zero overshoot)
/// and an animated core container with spring transitions.
class _GeofenceRadarWidget extends StatelessWidget {
  final Animation<double> animation;
  final bool isInside;
  final bool isChecking;
  final Color statusColor;

  /// The `on` colour paired with [statusColor] (TAS-352: was Colors.white).
  final Color onStatusColor;

  const _GeofenceRadarWidget({
    required this.animation,
    required this.isInside,
    required this.isChecking,
    required this.statusColor,
    required this.onStatusColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final ripple1 = animation.value;
        final ripple2 = (animation.value + 0.5) % 1.0;

        return SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer wave (Ripple 1)
              Transform.scale(
                scale: 0.55 + (0.45 * ripple1),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withValues(
                        alpha: (0.45 * (1.0 - ripple1)).clamp(0.0, 0.45),
                      ),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // Staggered secondary wave (Ripple 2)
              Transform.scale(
                scale: 0.4 + (0.45 * ripple2),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withValues(
                        alpha: (0.35 * (1.0 - ripple2)).clamp(0.0, 0.35),
                      ),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              // Breathing ambient glow
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(
                    alpha: isChecking ? 0.12 : (isInside ? 0.16 : 0.14),
                  ),
                ),
              ),
              // Center Core Button/Icon with M3 Elevation Shadow
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
                child: AnimatedSwitcher(
                  duration: AppMotionDurations.short4,
                  switchInCurve: AppMotionCurves.expressiveFastSpatial,
                  switchOutCurve: AppMotionCurves.standardAccelerate,
                  child: Icon(
                    isChecking
                        ? Symbols.radar_rounded
                        : (isInside
                              ? Symbols.check_rounded
                              : Symbols.location_off_rounded),
                    key: ValueKey('${isChecking}_$isInside'),
                    color: onStatusColor,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
