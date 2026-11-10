import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'dart:async';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/monthly_attendance_stats.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_for_month.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_action_lock.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/early_checkout_confirm_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/services/security_audit_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';

class AttendanceScreen extends StatefulWidget {
  final Delegate delegate;
  final bool viewOnly;

  const AttendanceScreen({
    super.key,
    required this.delegate,
    this.viewOnly = false,
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
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  List<Attendance> _rawHistory = [];
  List<Attendance> _filteredHistory = [];
  Map<String, List<Attendance>> _groupedByDay = {};
  List<String> _dayKeys = [];
  String _chainFilter = 'all'; // 'all' or normalized chain name
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

    final clean = rawOrgName.trim();
    final lower = clean.toLowerCase();
    if (lower.contains('fathalla') ||
        clean.contains('فتح الله') ||
        clean.contains('فتح_الله')) {
      return isArabic ? 'فتح الله ماركت' : 'Fathalla Market';
    }
    if (lower.contains('gomla') ||
        lower.contains('jomla') ||
        clean.contains('جملة') ||
        clean.contains('جمله')) {
      return isArabic ? 'جملة ماركت' : 'Gomla Market';
    }
    if (lower.contains('zahran') || clean.contains('زهران')) {
      return isArabic ? 'زهران ماركت' : 'Zahran Market';
    }
    if (lower.contains('carrefour') || clean.contains('كارفور')) {
      return isArabic ? 'كارفور' : 'Carrefour';
    }
    if (lower.contains('beit') || clean.contains('بيت الجملة')) {
      return isArabic ? 'بيت الجملة' : 'Beit El Gomla';
    }
    return clean;
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

  static (Color bg, Color fg, Color border) _getChainBadgeColors(
    BuildContext context,
    String chainName,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lower = chainName.toLowerCase().trim();

    // Gomla Market (Emerald Green)
    if (lower.contains('جملة') ||
        lower.contains('جمله') ||
        lower.contains('gomla') ||
        lower.contains('jomla')) {
      return isDark
          ? (
              const Color(0xFF143823),
              const Color(0xFF81C784),
              Theme.of(context).colorScheme.primary,
            )
          : (
              const Color(0xFFE8F5E9),
              const Color(0xFF1B5E20),
              const Color(0xFF81C784),
            );
    }

    // Fathalla Market (Royal Blue)
    if (lower.contains('فتح الله') || lower.contains('fathalla')) {
      return isDark
          ? (
              const Color(0xFF102844),
              const Color(0xFF90CAF9),
              const Color(0xFF1976D2),
            )
          : (
              const Color(0xFFE3F2FD),
              const Color(0xFF0D47A1),
              const Color(0xFF64B5F6),
            );
    }

    // Zahran Market (Warm Amber / Orange)
    if (lower.contains('زهران') || lower.contains('zahran')) {
      return isDark
          ? (
              const Color(0xFF3E240D),
              const Color(0xFFFFB74D),
              const Color(0xFFF57C00),
            )
          : (
              const Color(0xFFFFF3E0),
              const Color(0xFFE65100),
              const Color(0xFFFFB74D),
            );
    }

    // Carrefour (Sky Blue)
    if (lower.contains('كارفور') || lower.contains('carrefour')) {
      return isDark
          ? (
              const Color(0xFF0C2D48),
              const Color(0xFF38BDF8),
              const Color(0xFF0284C7),
            )
          : (
              const Color(0xFFE0F2FE),
              const Color(0xFF0369A1),
              const Color(0xFF7DD3FC),
            );
    }

    final cs = theme.colorScheme;
    return (
      cs.secondaryContainer.withValues(alpha: 0.6),
      cs.onSecondaryContainer,
      cs.secondary.withValues(alpha: 0.35),
    );
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
      }).ignore();
      raw = widget.delegate.organizationName;
    }
    return _formatChainName(raw, branchName: branchName, isArabic: isArabic);
  }

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
          if (date.year == _selectedMonth.year && date.month == _selectedMonth.month) {
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
  String? _locationStatusMessage;

  bool get _isGeofenceMode {
    if (_orgAttendanceMode != null) {
      return _orgAttendanceMode == 'geofence' || _orgAttendanceMode == 'gps';
    }
    final orgName = widget.delegate.organizationName.toLowerCase();
    if (orgName.contains('فتح الله') || orgName.contains('fathalla')) {
      return false;
    }
    return true; // Default for Gomla Market and all other retail chains
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
          _attendanceBloc.add(const SyncRequested());
        }
      }).ignore();
    }

    // Subscribe to connectivity changes once
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });

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
            if (mounted && _isGeofenceMode) {
              _loadBranches();
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
            organizationId: '', // Cross-org query for unified monthly attendance
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
    _scrollController.dispose();
    _attendanceBloc.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID) {
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
          if (mounted && _isGeofenceMode) {
            _loadBranches();
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
    final isArabic = true; // Canonical chain keys in Arabic for consistent matching

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
    final statsSource =
        _hasMonthSessionsForSelected ? _monthSessions! : _rawHistory;
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
      final inMonth = attendance.checkInTime.month == _selectedMonth.month &&
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
            if (!widget.viewOnly) {
              DelegateTrackingEngine().startTrackingSession(delegateId: widget.delegate.uid);
            }
            if (state.attendance.isSynced) {
              AppSnackBar.showSuccess(context, l10n.checkedInSuccessfully);
            } else {
              AppSnackBar.showInfo(
                context,
                AppLocalizations.of(context)!.attCheckInSavedOffline,
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
                AppLocalizations.of(context)!.attCheckOutSavedOffline,
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
            AppSnackBar.showError(context, state.message);
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
                  organizationId: '', // Cross-org query for unified monthly attendance
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
                      organizationId: '', // Cross-org query for unified monthly attendance
                      nationalityID: widget.delegate.nationalityID,
                      phoneNumber: widget.delegate.phoneNumber,
                    ),
                  );
                }
              });
            } else if (state.syncStatus == SyncStatus.failure) {
              AppSnackBar.showError(context, AppLocalizations.of(context)!.syncFailed);
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
              isCheckedIn &&
              !DelegateTrackingEngine().isTracking) {
            DelegateTrackingEngine()
                .startTrackingSession(delegateId: widget.delegate.uid);
          }

          return Scaffold(
            backgroundColor: colorScheme.surfaceContainerLowest,
            appBar: widget.viewOnly
                ? AppBar(
                    title: Text(
                      widget.delegate.fullName.isNotEmpty
                          ? widget.delegate.fullName
                          : (widget.delegate.companyName.isNotEmpty
                              ? AppLocalizations.of(context)!.attDelegateOfCompany(widget.delegate.companyName)
                              : AppLocalizations.of(context)!.attendanceLog),
                    ),
                  )
                : null,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildBody(context, state),
              ),
            ),
            floatingActionButton: widget.viewOnly
                ? null
                : M3PressScale(child: FloatingActionButton.extended(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    extendedPadding:
                        const EdgeInsetsDirectional.only(start: 16, end: 20),
                    onPressed: (_actionLock.isBusy ||
                            state is AttendanceLoading ||
                            isSyncing)
                        ? null
                        : () {
                            _actionLock.run(
                              bloc: _attendanceBloc,
                              onChanged: () {
                                if (mounted) setState(() {});
                              },
                              action: () => _isGeofenceMode
                                  ? _handleGeofenceAction(
                                      isCheckedIn: isCheckedIn,
                                      activeAttendance: activeAttendance,
                                    )
                                  : _showQRScanner(
                                      context,
                                      isCheckedIn,
                                      activeAttendance,
                                    ),
                            );
                          },
                    backgroundColor: isCheckedIn
                        ? Theme.of(context).colorScheme.primaryContainer
                        : (_isGeofenceMode
                            ? (_isInsideGeofence
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.secondaryContainer)
                            : Theme.of(context).colorScheme.primaryContainer),
                    icon: _actionLock.isBusy
                        ? SizedBox.square(
                            key: const Key('attendanceFabBusy'),
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: isCheckedIn || !_isGeofenceMode || _isInsideGeofence
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          )
                        : Icon(
                      isCheckedIn
                          ? Symbols.logout_rounded
                          : (_isGeofenceMode
                              ? (_isCheckingLocation
                                  ? Symbols.radar_rounded
                                  : (_isInsideGeofence
                                      ? Symbols.how_to_reg_rounded
                                      : Symbols.location_searching_rounded))
                              : Symbols.qr_code_scanner_rounded),
                      color: isCheckedIn
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : (_isGeofenceMode
                              ? (_isInsideGeofence
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSecondaryContainer)
                              : Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    label: Text(
                      _actionLock.isBusy
                          ? l10n.attLocatingShort
                          : _buildFabLabel(
                              context,
                              isCheckedIn: isCheckedIn,
                              activeAttendance: activeAttendance,
                              l10n: l10n,
                            ),
                      style: m3ButtonLabel(context).copyWith(
                        color: isCheckedIn
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : (_isGeofenceMode
                                ? (_isInsideGeofence
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : Theme.of(context).colorScheme.onSecondaryContainer)
                                : Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                    ),
                  )),
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

    final sessions =
        _hasMonthSessionsForSelected ? _monthSessions! : _rawHistory;
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
    final isCurrentMonth = _selectedMonth.year == trustedNow.year &&
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

    if (isBusy) {
      statusColor = colorScheme.primary;
      headerIcon = Symbols.radar_rounded;
      statusTitle = AppLocalizations.of(context)!.attCheckingZone;
      statusSubtitle = AppLocalizations.of(context)!.attVerifyingCoords;
    } else if (_isInsideGeofence) {
      statusColor = Theme.of(context).colorScheme.primary; // Emerald M3 Success
      headerIcon = Symbols.verified_rounded;
      statusTitle = AppLocalizations.of(context)!.attInsideZone;
      statusSubtitle = activeBranch != null
          ? AppLocalizations.of(context)!.attWithinBranchRange(BranchDisplayCache.instance.displayName(activeBranch.branchName))
          : AppLocalizations.of(context)!.attInsideZone;
    } else {
      statusColor = colorScheme.error;
      headerIcon = Symbols.wrong_location_rounded;
      statusTitle = AppLocalizations.of(context)!.attOutsideZone;
      statusSubtitle = activeBranch != null
          ? AppLocalizations.of(context)!.attMoveCloserTo(BranchDisplayCache.instance.displayName(activeBranch.branchName))
          : AppLocalizations.of(context)!.attOutsideApprovedBranches;
    }

    // Smart distance formatting
    String? formattedDistance;
    if (_distanceToNearest != null && _distanceToNearest!.isFinite) {
      final meters = _distanceToNearest!.toInt();
      if (meters < 1000) {
        formattedDistance = AppLocalizations.of(context)!.distanceMeters(meters);
      } else {
        final km = (_distanceToNearest! / 1000).toStringAsFixed(1);
        formattedDistance = AppLocalizations.of(context)!.distanceKmM(km, meters);
      }
    }

    final allowedRadius = activeBranch != null
        ? (activeBranch.geofenceRadius > 0
            ? (activeBranch.geofenceRadius + 50.0).toInt()
            : 150)
        : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ================= 1. MONTH SELECTOR =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    foregroundColor: colorScheme.onSurface,
                  ),
                  iconSize: 22,
                  tooltip: AppLocalizations.of(context)!.previousMonth,
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                      _recomputeFilteredHistory();
                      _loadApprovedLeaves();
                    });
                  },
                  icon: Icon(
                    Directionality.of(context) == TextDirection.rtl ? Symbols.chevron_right_rounded : Symbols.chevron_left_rounded,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotionDurations.medium2,
                        child: Text(
                          DateFormat('MMMM yyyy', locale).format(_selectedMonth),
                          key: ValueKey(_selectedMonth),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (!isCurrentMonth) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedMonth = trustedNow;
                              _recomputeFilteredHistory();
                              _loadApprovedLeaves();
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Symbols.restore_rounded, size: 12, color: colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(AppLocalizations.of(context)!.currentMonth,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    foregroundColor: colorScheme.onSurface,
                  ),
                  iconSize: 22,
                  tooltip: AppLocalizations.of(context)!.nextMonth,
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month + 1,
                      );
                      _recomputeFilteredHistory();
                      _loadApprovedLeaves();
                    });
                  },
                  icon: Icon(
                    Directionality.of(context) == TextDirection.rtl ? Symbols.chevron_left_rounded : Symbols.chevron_right_rounded,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
            if (_isOffline) ...[
              const SizedBox(height: 8),
              _buildConnectivityBadge(context, l10n),
            ],

            const SizedBox(height: 12),
            Divider(height: 1, thickness: 0.8, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),

            // ================= 2. ATTENDANCE & ABSENCE STATS =================
            Row(
              children: [
                // Attendance Stat (Condensed with Google Icon)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Symbols.check_circle_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppLocalizations.of(context)!.statAttended,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: AppMotionDurations.short4,
                                child: Text(AppLocalizations.of(context)!.daysCount(attendedDays),
                                  key: ValueKey(attendedDays),
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Absence Stat (Condensed with Google Icon)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Symbols.event_busy_rounded,
                            size: 18,
                            color: colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppLocalizations.of(context)!.statAbsent,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: AppMotionDurations.short4,
                                child: Text(AppLocalizations.of(context)!.daysCount(absentDays),
                                  key: ValueKey(absentDays),
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: absentDays > 0 ? colorScheme.error : colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Work days policy badge (condensed)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(AppLocalizations.of(context)!.attWorkPolicyNote,
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // ================= 3. GEOFENCE ZONE STATUS =================
            if (_isGeofenceMode) ...[
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 0.8, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),

              AnimatedContainer(
                duration: AppMotionDurations.medium3,
                curve: AppMotionCurves.emphasized,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isInsideGeofence
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                      : (isBusy
                          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                          : colorScheme.error.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _GeofenceRadarWidget(
                          animation: _radarAnimation,
                          isInside: _isInsideGeofence,
                          isChecking: isBusy,
                          statusColor: statusColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    headerIcon,
                                    size: 18,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      statusTitle,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _locationStatusMessage ?? statusSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 1. Distance Chip (Top, if available)
                    if (formattedDistance != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isInsideGeofence
                                    ? Symbols.near_me_rounded
                                    : Symbols.straighten_rounded,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 5),
                              Text(AppLocalizations.of(context)!.distanceLabel(formattedDistance),
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // 2. Branch Name Chip (Under Distance)
                    if (activeBranch != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.storefront_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 5),
                              Text(
                                activeBranch.branchName,
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // 3. Allowed Radius & Recheck Location on the same row
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (allowedRadius != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Symbols.radar_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 5),
                                Text(AppLocalizations.of(context)!.radiusLabel(allowedRadius),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _detectNearestBranch(showSnackBar: true, silent: false),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            backgroundColor: colorScheme.surface.withValues(alpha: 0.7),
                          ),
                          icon: isBusy
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : Icon(Symbols.refresh_rounded, size: 16, color: colorScheme.primary),
                          label: Text(AppLocalizations.of(context)!.recheckLocation,
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isBusy ? colorScheme.onSurfaceVariant : colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildConnectivityBadge(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!_isOffline) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.cloud_off_rounded,
            color: colorScheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.networkStatusOffline,
            style: TextStyle(
              color: colorScheme.onErrorContainer,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode.startsWith('ar');
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

    Widget buildTab({
      required String filterKey,
      required String label,
      required int count,
      required IconData icon,
      Color? accentFg,
      Color? accentBg,
    }) {
      final isSelected = _chainFilter == filterKey;
      final activeFg = accentFg ?? colorScheme.primary;
      final activeBg = accentBg ?? colorScheme.primaryContainer;

      return InkWell(
        onTap: () {
          if (_chainFilter != filterKey) {
            setState(() {
              _chainFilter = filterKey;
              _recomputeFilteredHistory();
            });
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotionDurations.short4,
          curve: AppMotionCurves.standard,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected && accentFg != null
                ? Border.all(color: accentFg.withValues(alpha: 0.35), width: 1)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? activeFg
                    : (accentFg?.withValues(alpha: 0.8) ??
                        colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? activeFg : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeBg
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? activeFg
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allTab = buildTab(
      filterKey: 'all',
      label: AppLocalizations.of(context)!.allChains,
      count: _allAttendedDaysCount,
      icon: Symbols.hub_rounded,
    );

    final chainTabs = chains.map((chainKey) {
      final displayLabel = _formatChainName(chainKey, isArabic: isArabic);
      final (bg, fg, _) = _getChainBadgeColors(context, chainKey);
      final count = _chainDaysCount[chainKey] ?? 0;
      return buildTab(
        filterKey: chainKey,
        label: displayLabel,
        count: count,
        icon: Symbols.storefront_rounded,
        accentFg: fg,
        accentBg: bg,
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: chains.length <= 2
          ? Row(
              children: [
                Expanded(child: allTab),
                for (final tab in chainTabs) ...[
                  const SizedBox(width: 4),
                  Expanded(child: tab),
                ],
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  allTab,
                  for (final tab in chainTabs) ...[
                    const SizedBox(width: 4),
                    tab,
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, AttendanceState state) {
    final l10n = AppLocalizations.of(context)!;
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
            Icon(Symbols.error_outline_rounded, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              state.message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
      final selectedChainLabel = _chainFilter != 'all' && _chainFilter != 'active'
          ? _formatChainName(_chainFilter, isArabic: isArabic)
          : _formatChainName(
              widget.delegate.organizationName.isNotEmpty
                  ? widget.delegate.organizationName
                  : AppLocalizations.of(context)!.activeChain,
              isArabic: isArabic,
            );

      if (_dayKeys.isEmpty) {
        return M3Refresh(
          onRefresh: () async {
            if (_isGeofenceMode) {
              _detectNearestBranch(showSnackBar: false);
            }
            _attendanceBloc.add(const SyncRequested());
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
            padding: const EdgeInsetsDirectional.only(top: 12, bottom: 80),
            child: Column(
              children: [
                _buildUnifiedAttendanceCard(context),
                _buildChainFilterBar(context),
                const SizedBox(height: 24),
                if (_chainFilter != 'all' && _allAttendedDaysCount > 0) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Symbols.storefront_rounded,
                          size: 44,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(AppLocalizations.of(context)!.attNoSessionsInChain(selectedChainLabel),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.attDaysInOtherChains(_allAttendedDaysCount),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _chainFilter = 'all';
                              _recomputeFilteredHistory();
                            });
                          },
                          icon: const Icon(Symbols.hub_rounded, size: 18),
                          label: Text(AppLocalizations.of(context)!.allChains,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.verified_user_rounded,
                      size: 56,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.noHistoryAvailable,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!_isGeofenceMode)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.qr_code_scanner_rounded,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            l10n.scanQrInstruction,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
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
          _attendanceBloc.add(const SyncRequested());
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
          padding: const EdgeInsetsDirectional.only(top: 12, bottom: 80),
          itemCount: _dayKeys.length + 2 + (state.hasReachedMax ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildUnifiedAttendanceCard(context);
            }
            if (index == 1) {
              return _buildChainFilterBar(context);
            }
            final dayIndex = index - 2;
            if (dayIndex >= _dayKeys.length) {
              return state.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
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
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8, top: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Symbols.calendar_today_rounded,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fullDateStr,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${records.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
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
                  final rawBranchName = item.branchName ?? l10n.unspecifiedBranch;
                  final cleanBranchName = _cleanBranchName(rawBranchName);
                  final chainName = _resolveOrgName(
                    item.organizationId,
                    branchName: item.branchName,
                    isArabic: isArabic,
                  );
                  final (chipBg, chipFg, chipBorder) = _getChainBadgeColors(
                    context,
                    chainName,
                  );

                  String durationStr;
                  if (effectiveOut != null) {
                    final diff = effectiveOut.difference(
                      item.checkInTime,
                    );
                    final hours = diff.inHours;
                    final minutes = diff.inMinutes.remainder(60);
                    durationStr = l10n.duration('$hours', '$minutes');
                  } else {
                    durationStr = l10n.inProgress;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (chainName.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: chipBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: chipBorder,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Symbols.storefront_rounded,
                                              size: 13,
                                              color: chipFg,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              chainName,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: chipFg,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Icon(
                                      Symbols.location_on_rounded,
                                      size: 15,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(AppLocalizations.of(context)!.branchLabel(cleanBranchName),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Symbols.login_rounded,
                                      size: 16,
                                      color: colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.inLabel(inTime),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      item.isEffectiveAutoCheckOut
                                          ? Symbols.auto_mode_rounded
                                          : Symbols.logout_rounded,
                                      size: 16,
                                      color: item.isEffectiveAutoCheckOut
                                          ? Theme.of(context).colorScheme.onTertiaryContainer
                                          : colorScheme.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.outLabel(outTime),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: item.isEffectiveAutoCheckOut
                                            ? Theme.of(context).colorScheme.onTertiaryContainer
                                            : null,
                                      ),
                                    ),
                                    if (item.isEffectiveAutoCheckOut) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Tooltip(
                                          message: AppLocalizations.of(context)!.attAutoClosedNote,
                                          child: Text(AppLocalizations.of(context)!.autoClosedAuto,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onTertiaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Symbols.timer_rounded,
                                      size: 14,
                                      color: effectiveOut != null
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      durationStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: effectiveOut != null
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!item.isSynced)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 8.0,
                              ),
                              child: Tooltip(
                                message: l10n.pendingSync,
                                child: Icon(
                                  Symbols.cloud_off_rounded,
                                  color: colorScheme.error,
                                  size: 20,
                                ),
                              ),
                            ),
                          if (item.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l10n.active,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onTertiaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
      final branchesList = <Branch>[];

      // 1. Fetch from organizations/{orgId}/branches
      try {
        final snap = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .collection('branches')
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          branchesList.add(BranchModel.fromMap({...data, 'id': doc.id}));
        }
      } catch (_) {}

      // 2. Fetch from root branches where organizationUID == orgId
      if (branchesList.isEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('branches')
              .where('organizationUID', isEqualTo: orgId)
              .get();
          for (final doc in snap.docs) {
            final data = doc.data();
            branchesList.add(BranchModel.fromMap({...data, 'id': doc.id}));
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _orgBranches = branchesList;
          _isLoadingBranches = false;
          if (branchesList.isEmpty) {
            _locationStatusMessage = AppLocalizations.of(context)!.noBranchesForOrg;
            _isInsideGeofence = false;
          }
        });

        // Only scan GPS if branches exist
        if (branchesList.isNotEmpty) {
          _detectNearestBranch(showSnackBar: false, silent: true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _detectNearestBranch({
    bool showSnackBar = false,
    bool silent = false,
  }) async {
    if (!mounted || _isCheckingLocation) return;
    if (_orgBranches.isEmpty) {
      setState(() {
        _isCheckingLocation = false;
        _locationStatusMessage = AppLocalizations.of(context)!.noBranchesForOrg;
      });
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
        _locationStatusMessage =
            AppLocalizations.of(context)!.attLocationUnavailable;
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

      final allowedRadius = branch.geofenceRadius > 0
          ? (branch.geofenceRadius + 50.0)
          : 150.0;

      if (dist <= allowedRadius) {
        matched = branch;
      }
    }


    setState(() {
      _isCheckingLocation = false;
      _nearestBranch = closest;
      _distanceToNearest = minDistance.isFinite ? minDistance : null;
      _matchedBranch = matched;
      _isInsideGeofence = matched != null;

      if (matched != null) {
        _locationStatusMessage = AppLocalizations.of(context)!.attYouAreWithinBranch(BranchDisplayCache.instance.displayName(matched.branchName));
      } else if (closest != null && minDistance.isFinite) {
        _locationStatusMessage = AppLocalizations.of(context)!.attMoveCloser;
      } else {
        _locationStatusMessage = AppLocalizations.of(context)!.attOutsideApprovedBranches;
      }
    });

    if (showSnackBar && mounted) {
      if (_isInsideGeofence && matched != null) {
        AppSnackBar.showSuccess(
          context,
          AppLocalizations.of(context)!.attInsideBranchWithDistance(BranchDisplayCache.instance.displayName(matched.branchName), minDistance.toInt()),
        );
      } else if (closest != null) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.attOutsideBranchWithRadius(minDistance.toInt(), (closest.geofenceRadius + 50).toInt()),
        );
      }
    }
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
      AppSnackBar.showError(
        parentContext,
        l10n.attEnsureGps,
      );
      return;
    }

    final branchToUse = _matchedBranch ?? _nearestBranch;
    if (!_isInsideGeofence || branchToUse == null) {
      final nearestName = (_nearestBranch?.branchName ?? '').trim();
      final distStr = _distanceToNearest != null
          ? l10n.distanceMeters(_distanceToNearest!.toInt())
          : nearestName;
      AppSnackBar.showError(
        parentContext,
        l10n.attCannotActOutside(isCheckedIn ? l10n.attActionCheckOut : l10n.attActionCheckIn, distStr),
      );
      return;
    }

    final branchName = branchToUse.branchName;
    final position = _currentPosition!;

    // Dynamically resolve latest active attendance to prevent stale closure state
    Attendance? currentActive = activeAttendance;
    final currentState = attendanceBloc.state;
    if (currentState is AttendanceHistoryLoaded && currentState.activeAttendance != null) {
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
          branchName,
          position,
          attendanceBloc,
          l10n,
        );
      } else if (currentActive.branchName == branchName ||
          currentActive.branchName == null) {
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
          branchName,
          position,
          attendanceBloc,
          l10n,
        );
      }
    } else {
      await _checkIn(attendanceBloc, branchName, position);
      if (parentContext.mounted) {
        AppSnackBar.showInfo(
          parentContext,
          l10n.attCheckingInAt(branchName),
        );
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

    return showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: m3SheetAnimation,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScannerModal(action: action),
    ).then((scannedBranch) async {
      if (scannedBranch != null && scannedBranch.isNotEmpty) {
        if (!parentContext.mounted) return;
        AppSnackBar.showInfo(parentContext, 'Fetching location...');

        final position = await _getCurrentLocation(
          parentContext,
          branchName: scannedBranch,
          actionType: isCheckedIn ? 'تسجيل انصراف' : 'تسجيل حضور',
        );
        if (position != null && parentContext.mounted) {
          // Dynamically resolve latest active attendance to prevent stale closure state
          Attendance? currentActive = activeAttendance;
          final currentState = attendanceBloc.state;
          if (currentState is AttendanceHistoryLoaded && currentState.activeAttendance != null) {
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
                scannedBranch,
                position,
                attendanceBloc,
                l10n,
              );
            } else if (currentActive.branchName == scannedBranch ||
                currentActive.branchName == null) {
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
                scannedBranch,
                position,
                attendanceBloc,
                l10n,
              );
            }
          } else {
            await _checkIn(attendanceBloc, scannedBranch, position);
            if (parentContext.mounted) {
              AppSnackBar.showInfo(
                parentContext,
                AppLocalizations.of(context)!.attCheckingInAt(scannedBranch),
              );
            }
          }
        }
      } else if (scannedBranch == "") {
        if (!parentContext.mounted) return;
        AppSnackBar.showError(parentContext, l10n.invalidQRCode);
      }
    });
  }

  Future<void> _checkIn(
    AttendanceBloc bloc,
    String branchName,
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
        branchName: branchName,
        delegateName: widget.delegate.fullName.isNotEmpty
            ? widget.delegate.fullName
            : null,
        phoneNumber: widget.delegate.phoneNumber.isNotEmpty
            ? widget.delegate.phoneNumber
            : null,
        companyName: widget.delegate.companyName.isNotEmpty
            ? widget.delegate.companyName
            : null,
        personalPhotoURL: widget.delegate.personalPhotoUrl,
      ),
    );
  }

  Future<Position?> _getCurrentLocation(
    BuildContext context, {
    String? branchName,
    String? actionType,
    bool silent = false,
  }) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return null;
      if (!silent) {
        AppSnackBar.showError(context, AppLocalizations.of(context)!.locationServicesOff);
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        if (!silent) {
          AppSnackBar.showError(context, AppLocalizations.of(context)!.locationPermissionDenied2);
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      if (!silent) {
        AppSnackBar.showError(context, AppLocalizations.of(context)!.locationPermissionDeniedForever);
      }
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );

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
    } on TimeoutException catch (_) {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        if (lastPosition.isMocked) {
          _logMockViolation(
            lastPosition,
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
        return lastPosition;
      }
      if (context.mounted && !silent) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationTimeout,
        );
      }
      return null;
    } catch (e) {
      if (context.mounted && !silent) {
        AppSnackBar.showError(context, AppLocalizations.of(context)!.locationError);
      }
      return null;
    }
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
    _getDeviceInfo().then((device) {
      SecurityAuditService.logMockLocationViolation(
        delegate: widget.delegate,
        position: position,
        deviceModel: device,
        branchName: branchName,
        actionType: actionType,
      );
    }).catchError((_) {});
  }

  void _showForgotCheckoutDialog(
    BuildContext context,
    Attendance activeAttendance,
    String newBranch,
    Position position,
    AttendanceBloc bloc,
    AppLocalizations l10n,
  ) {
    showM3Dialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.forgotCheckoutTitle),
          content: Text(
            l10n.forgotCheckoutMessage(activeAttendance.branchName ?? l10n.unspecifiedBranch, newBranch),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
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
                    branchName: newBranch,
                    delegateName: widget.delegate.fullName.isNotEmpty
                        ? widget.delegate.fullName
                        : null,
                    phoneNumber: widget.delegate.phoneNumber.isNotEmpty
                        ? widget.delegate.phoneNumber
                        : null,
                    companyName: widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : null,
                    personalPhotoURL: widget.delegate.personalPhotoUrl,
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
    String newBranch,
    Position position,
    AttendanceBloc bloc,
    AppLocalizations l10n,
  ) {
    showM3Dialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.forgotCheckoutTitle),
          content: Text(
            l10n.previousDayCheckoutMessage(activeAttendance.branchName ?? l10n.unspecifiedBranch, newBranch),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
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
                    branchName: newBranch,
                    delegateName: widget.delegate.fullName.isNotEmpty
                        ? widget.delegate.fullName
                        : null,
                    phoneNumber: widget.delegate.phoneNumber.isNotEmpty
                        ? widget.delegate.phoneNumber
                        : null,
                    companyName: widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : null,
                    personalPhotoURL: widget.delegate.personalPhotoUrl,
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

  /// Shimmer skeleton that mimics the attendance history cards while loading.
  Widget _buildShimmerSkeleton() {
    return ListView.builder(
      padding: const EdgeInsetsDirectional.only(
        top: 16,
        bottom: 80,
        start: 16,
        end: 16,
      ),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ShimmerCard(),
        );
      },
    );
  }

}

/// Animated shimmer card that mimics attendance history card layout.
class _ShimmerCard extends StatefulWidget {
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBar(width: 120, height: 12),
                const SizedBox(height: 12),
                _buildShimmerBar(width: 180, height: 14),
                const SizedBox(height: 8),
                _buildShimmerBar(width: 160, height: 14),
                const SizedBox(height: 8),
                _buildShimmerBar(width: 100, height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBar({required double width, required double height}) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHigh;
    final highlightColor = colorScheme.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        );
      },
    );
  }
}

class _ScannerModal extends StatefulWidget {
  final String action;

  const _ScannerModal({required this.action});

  @override
  State<_ScannerModal> createState() => _ScannerModalState();
}

class _ScannerModalState extends State<_ScannerModal>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final AnimationController _laserController;
  bool _isProcessing = false;
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

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isCheckedIn = widget.action == l10n.checkOut;
    final color = isCheckedIn ? colorScheme.secondary : colorScheme.primary;
    final locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (!mounted || _isProcessing) return;
              _isProcessing = true;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                HapticFeedback.mediumImpact();
                final String rawValue = barcodes.first.rawValue ?? '';
                String? scannedBranch;
                try {
                  final dynamic decoded = jsonDecode(rawValue);

                  if (decoded is Map<String, dynamic> &&
                      decoded['type'] == 'attendance') {
                    if (decoded.containsKey('branch') &&
                        decoded['branch'] is String) {
                      scannedBranch = decoded['branch'] as String;
                    }
                  }
                } catch (_) {
                  if (rawValue.isNotEmpty && !rawValue.startsWith('{')) {
                    scannedBranch = rawValue.trim();
                  }
                }

                if (mounted) {
                  _scannerController.stop();
                  Navigator.pop(context, scannedBranch ?? "");
                }
              } else {
                _isProcessing = false;
              }
            },
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
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(24),
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
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.1),
                                color,
                                color.withValues(alpha: 0.1),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
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
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black87,
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.scanForAction(widget.action),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.pointCameraToQR(widget.action),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
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
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
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
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                DateFormat(
                                  'hh:mm:ss a',
                                  locale,
                                ).format(currentTime),
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              if (_timeService.isSynced) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context)!.trustedTime,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCheckedIn
                              ? Symbols.logout_rounded
                              : Symbols.login_rounded,
                          color: color,
                          size: 30,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Close Button
          Positioned(
            top: 45,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                tooltip: 'Close Scanner',
                icon: const Icon(Symbols.close_rounded, color: Colors.white),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
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

  const _GeofenceRadarWidget({
    required this.animation,
    required this.isInside,
    required this.isChecking,
    required this.statusColor,
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
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                    color: Colors.white,
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


