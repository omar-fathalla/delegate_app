import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/services/security_audit_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
    _attendanceBloc = sl<AttendanceBloc>();
    _attendanceBloc.add(
      HistoryRequested(
        userId: widget.delegate.uid,
        organizationId: widget.delegate.organizationUID,
        nationalityID: widget.delegate.nationalityID,
        phoneNumber: widget.delegate.phoneNumber,
      ),
    );
    // Delay sync request to allow history to load first
    Future.delayed(const Duration(seconds: 2), () {
      if (!_attendanceBloc.isClosed) {
        _attendanceBloc.add(const SyncRequested());
      }
    }).ignore();

    try {
      _selectedMonth = sl.isRegistered<TrustedTimeService>()
          ? sl<TrustedTimeService>().now
          : DateTime.now();
    } catch (_) {
      _selectedMonth = DateTime.now();
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
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _radarController.repeat();
    }
    _radarAnimation = CurvedAnimation(
      parent: _radarController,
      curve: AppMotionCurves.standardDecelerate,
    );

    // If Geofence mode is expected, load organization settings and branches
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
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

  void _onScroll() {
    if (_isBottom) {
      final state = _attendanceBloc.state;
      if (state is AttendanceHistoryLoaded &&
          !state.isLoadingMore &&
          !state.hasReachedMax) {
        _attendanceBloc.add(
          LoadMoreHistoryRequested(
            userId: widget.delegate.uid,
            organizationId: widget.delegate.organizationUID,
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
        _rawHistory.clear();
        _filteredHistory.clear();
        _groupedByDay.clear();
        _dayKeys.clear();
        _orgBranches.clear();
        _matchedBranch = null;
        _nearestBranch = null;
        _distanceToNearest = null;
        _isInsideGeofence = false;
      });
      _fetchOrganizationSettings().then((_) {
        if (mounted && _isGeofenceMode) {
          _loadBranches();
        }
      });
      _attendanceBloc.add(
        HistoryRequested(
          userId: widget.delegate.uid,
          organizationId: widget.delegate.organizationUID,
          nationalityID: widget.delegate.nationalityID,
          phoneNumber: widget.delegate.phoneNumber,
        ),
      );
    }
  }

  /// Recomputes filtered/grouped data only when source data or month changes.
  void _recomputeFilteredHistory() {
    _filteredHistory = _rawHistory.where((attendance) {
      return attendance.checkInTime.month == _selectedMonth.month &&
          attendance.checkInTime.year == _selectedMonth.year;
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
            if (state.attendance.isSynced) {
              AppSnackBar.showSuccess(context, l10n.checkedInSuccessfully);
            } else {
              AppSnackBar.showInfo(
                context,
                'تم تسجيل الدخول محلياً. ستتم المزامنة لاحقاً عند الاتصال بالشبكة.',
              );
            }
            context.read<AttendanceBloc>().add(
              HistoryRequested(
                userId: widget.delegate.uid,
                organizationId: widget.delegate.organizationUID,
                nationalityID: widget.delegate.nationalityID,
                phoneNumber: widget.delegate.phoneNumber,
              ),
            );
          } else if (state is AttendanceCheckedOut) {
            if (state.attendance.isSynced) {
              AppSnackBar.showSuccess(context, l10n.checkedOutSuccessfully);
            } else {
              AppSnackBar.showInfo(
                context,
                'تم تسجيل الانصراف محلياً. ستتم المزامنة لاحقاً عند الاتصال بالشبكة.',
              );
            }
            context.read<AttendanceBloc>().add(
              HistoryRequested(
                userId: widget.delegate.uid,
                organizationId: widget.delegate.organizationUID,
                nationalityID: widget.delegate.nationalityID,
                phoneNumber: widget.delegate.phoneNumber,
              ),
            );
          } else if (state is AttendanceError) {
            AppSnackBar.showError(context, state.message);
          } else if (state is AttendanceHistoryLoaded) {
            // --- Performance: cache + compute only when data changes ---
            _rawHistory = state.history;
            _recomputeFilteredHistory();

            if (_filteredHistory.isEmpty &&
                !state.hasReachedMax &&
                !state.isLoadingMore) {
              // Auto-pagination: If current batch doesn't match selected month, load more automatically.
              context.read<AttendanceBloc>().add(
                LoadMoreHistoryRequested(
                  userId: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                  nationalityID: widget.delegate.nationalityID,
                  phoneNumber: widget.delegate.phoneNumber,
                ),
              );
            }
            if (state.syncStatus == SyncStatus.success) {
              AppSnackBar.showSuccess(
                context,
                'تمت مزامنة البيانات المحفوظة بنجاح',
              );
              Future.delayed(const Duration(seconds: 1), () {
                if (context.mounted) {
                  context.read<AttendanceBloc>().add(
                    HistoryRequested(
                      userId: widget.delegate.uid,
                      organizationId: widget.delegate.organizationUID,
                      nationalityID: widget.delegate.nationalityID,
                      phoneNumber: widget.delegate.phoneNumber,
                    ),
                  );
                }
              });
            } else if (state.syncStatus == SyncStatus.failure) {
              AppSnackBar.showError(context, 'فشلت المزامنة');
            }
          }
        },
        builder: (context, state) {
          bool isCheckedIn = false;
          Attendance? activeAttendance;
          bool isSyncing = false;

          if (state is AttendanceHistoryLoaded) {
            isCheckedIn = state.activeAttendance != null;
            activeAttendance = state.activeAttendance;
            isSyncing = state.syncStatus == SyncStatus.inProgress;
          }

          return Scaffold(
            appBar: widget.viewOnly
                ? AppBar(
                    title: Text(
                      widget.delegate.fullName.isNotEmpty
                          ? widget.delegate.fullName
                          : (widget.delegate.companyName.isNotEmpty
                              ? 'مندوب - ${widget.delegate.companyName}'
                              : 'سجل الحضور'),
                    ),
                  )
                : null,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildHeader(context),

                    Expanded(child: _buildBody(context, state)),
                  ],
                ),
              ),
            ),
            floatingActionButton: widget.viewOnly
                ? null
                : FloatingActionButton.extended(
                    onPressed: (state is AttendanceLoading || isSyncing)
                        ? null
                        : () {
                            if (_isGeofenceMode) {
                              _handleGeofenceAction(
                                isCheckedIn: isCheckedIn,
                                activeAttendance: activeAttendance,
                              );
                            } else {
                              _showQRScanner(
                                context,
                                isCheckedIn,
                                activeAttendance,
                              );
                            }
                          },
                    backgroundColor: isCheckedIn
                        ? Theme.of(context).colorScheme.errorContainer
                        : (_isGeofenceMode
                            ? (_isInsideGeofence
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.secondaryContainer)
                            : Theme.of(context).colorScheme.primaryContainer),
                    icon: Icon(
                      isCheckedIn
                          ? Icons.logout_rounded
                          : (_isGeofenceMode
                              ? (_isCheckingLocation
                                  ? Icons.radar_rounded
                                  : (_isInsideGeofence
                                      ? Icons.how_to_reg_rounded
                                      : Icons.location_searching_rounded))
                              : Icons.qr_code_scanner),
                      color: isCheckedIn
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : (_isGeofenceMode
                              ? (_isInsideGeofence
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSecondaryContainer)
                              : Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    label: Text(
                      _buildFabLabel(
                        context,
                        isCheckedIn: isCheckedIn,
                        activeAttendance: activeAttendance,
                        l10n: l10n,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCheckedIn
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : (_isGeofenceMode
                                ? (_isInsideGeofence
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : Theme.of(context).colorScheme.onSecondaryContainer)
                                : Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                    ),
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

  Widget _buildHeader(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final trustedNow = _getTrustedNow();
    final isCurrentMonth = _selectedMonth.year == trustedNow.year &&
        _selectedMonth.month == trustedNow.month;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                    backgroundColor: colorScheme.surface.withValues(alpha: 0.5),
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                      _recomputeFilteredHistory();
                    });
                  },
                  child: const Icon(Icons.chevron_left_rounded, size: 26),
                ),
                Column(
                  children: [
                    Text(
                      DateFormat('MMMM yyyy', locale).format(_selectedMonth),
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!isCurrentMonth) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedMonth = trustedNow;
                            _recomputeFilteredHistory();
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'العودة للشهر الحالي ↩',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                    backgroundColor: colorScheme.surface.withValues(alpha: 0.5),
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month + 1,
                      );
                      _recomputeFilteredHistory();
                    });
                  },
                  child: const Icon(Icons.chevron_right_rounded, size: 26),
                ),
              ],
            ),
            if (_isOffline) ...[
              const SizedBox(height: 14),
              _buildConnectivityBadge(context, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyStatsBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final totalDaysInMonth = DateUtils.getDaysInMonth(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    final trustedNow = _getTrustedNow();
    final isCurrentMonth = _selectedMonth.year == trustedNow.year &&
        _selectedMonth.month == trustedNow.month;
    final isPastMonth = _selectedMonth.isBefore(
      DateTime(trustedNow.year, trustedNow.month, 1),
    );
    final isFutureMonth = _selectedMonth.isAfter(
      DateTime(trustedNow.year, trustedNow.month, 1),
    );

    final attendedDays = _dayKeys.length;
    int absentDays = 0;

    if (isPastMonth) {
      // For a completed past month, 26 work days standard (4 off days excluded)
      absentDays = (26 - attendedDays).clamp(0, 26);
    } else if (isCurrentMonth) {
      final currentDay = trustedNow.day;
      int activeDays = currentDay;
      if (widget.delegate.createdAt.year == _selectedMonth.year &&
          widget.delegate.createdAt.month == _selectedMonth.month &&
          widget.delegate.createdAt.day > 1) {
        activeDays = (currentDay - widget.delegate.createdAt.day + 1)
            .clamp(1, totalDaysInMonth);
      }
      // 4 off days per month (~1 off day every 7 days)
      final offDaysSoFar = (activeDays / 7).floor().clamp(0, 4);
      final elapsedWorkDays = (activeDays - offDaysSoFar).clamp(0, 26);
      absentDays = (elapsedWorkDays - attendedDays).clamp(0, 26);
    } else if (isFutureMonth) {
      absentDays = 0;
    }

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. أيام الحضور
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic ? 'أيام الحضور' : 'Attendance Days',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        isArabic ? '$attendedDays يوم' : '$attendedDays days',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(width: 1, height: 28, color: colorScheme.outlineVariant),
              // 2. أيام الغياب
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.event_busy_rounded,
                      size: 18,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic ? 'أيام الغياب' : 'Absence Days',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        isArabic ? '$absentDays يوم' : '$absentDays days',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: absentDays > 0
                              ? colorScheme.error
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  isArabic
                      ? 'نظام 26 يوم عمل شهرياً • 4 أيام إجازة مستبعدة من الغياب'
                      : '26 work days/month • 4 off days excluded from absence',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            Icons.cloud_off_rounded,
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
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
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
                    organizationId: widget.delegate.organizationUID,
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
      // --- Performance: Use pre-computed cached data ---
      if (_filteredHistory.isEmpty && state.hasReachedMax) {
        final colorScheme = Theme.of(context).colorScheme;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 64,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.noHistoryAvailable,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              if (_isGeofenceMode)
                _buildGeofenceCard(context)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          l10n.scanQrInstruction,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
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
        );
      }

      return RefreshIndicator(
        onRefresh: () async {
          if (_isGeofenceMode) {
            _detectNearestBranch(showSnackBar: false);
          }
          _attendanceBloc.add(const SyncRequested());
          _attendanceBloc.add(
            HistoryRequested(
              userId: widget.delegate.uid,
              organizationId: widget.delegate.organizationUID,
              nationalityID: widget.delegate.nationalityID,
              phoneNumber: widget.delegate.phoneNumber,
            ),
          );
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsetsDirectional.only(top: 12, bottom: 80),
          itemCount: _dayKeys.length + (state.hasReachedMax ? 1 : 2),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  _buildMonthlyStatsBanner(context),
                  if (_isGeofenceMode) _buildGeofenceCard(context),
                ],
              );
            }
            final dayIndex = index - 1;
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
                          Icons.calendar_today_rounded,
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
                  final inTime = DateFormat(
                    'hh:mm a',
                    locale,
                  ).format(item.checkInTime);
                  final outTime = item.checkOutTime != null
                      ? DateFormat('hh:mm a', locale).format(item.checkOutTime!)
                      : '--:--';
                  final branchName = item.branchName ?? l10n.unspecifiedBranch;

                  String durationStr;
                  if (item.checkOutTime != null) {
                    final diff = item.checkOutTime!.difference(
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
                                    Icon(
                                      Icons.location_on_rounded,
                                      size: 14,
                                      color: colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      branchName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.login,
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
                                      Icons.logout,
                                      size: 16,
                                      color: colorScheme.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.outLabel(outTime),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color: item.checkOutTime != null
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      durationStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: item.checkOutTime != null
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
                                  Icons.cloud_off,
                                  color: colorScheme.error,
                                  size: 20,
                                ),
                              ),
                            ),
                          if (item.checkOutTime == null)
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
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (!_isGeofenceMode) {
      return isCheckedIn ? l10n.scanToCheckOut : l10n.scanToCheckIn;
    }

    if (isCheckedIn) {
      final bName = activeAttendance?.branchName ?? _matchedBranch?.branchName;
      if (bName != null && bName.isNotEmpty) {
        return isArabic ? 'تسجيل انصراف ($bName)' : 'Check Out ($bName)';
      }
      return isArabic ? 'تسجيل الانصراف' : 'Check Out';
    }

    if (_isCheckingLocation) {
      return isArabic ? 'جاري فحص الموقع...' : 'Checking location...';
    }

    if (_isInsideGeofence && _matchedBranch != null) {
      return isArabic
          ? 'تسجيل حضور (${_matchedBranch!.branchName})'
          : 'Check In (${_matchedBranch!.branchName})';
    }

    return isArabic ? 'فحص الموقع وتسجيل الحضور' : 'Verify & Check In';
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
        final isArabic = Localizations.localeOf(context).languageCode == 'ar';
        setState(() {
          _orgBranches = branchesList;
          _isLoadingBranches = false;
          if (branchesList.isEmpty) {
            _locationStatusMessage = isArabic
                ? 'لا توجد فروع مسجلة لهذه المؤسسة حالياً.'
                : 'No branches registered for this organization yet.';
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
      final isArabic = Localizations.localeOf(context).languageCode == 'ar';
      setState(() {
        _isCheckingLocation = false;
        _locationStatusMessage = isArabic
            ? 'لا توجد فروع مسجلة لهذه المؤسسة.'
            : 'No branches registered for this organization.';
      });
      return;
    }

    setState(() {
      _isCheckingLocation = true;
      _locationStatusMessage = 'جاري تحديد موقعك الجغرافي والتحقق من الفروع...';
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
            'تعذر الحصول على الموقع الجغرافي. يرجى تفعيل الـ GPS.';
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
        _locationStatusMessage =
            'أنت متواجد داخل نطاق فرع ${matched.branchName} (${minDistance.toInt()} م)';
      } else if (closest != null && minDistance.isFinite) {
        _locationStatusMessage =
            'أنت خارج نطاق العمل - أقرب فرع: ${closest.branchName} (يبعد ${minDistance.toInt()} م)';
      } else {
        _locationStatusMessage = 'أنت خارج نطاق الفروع المعتمدة.';
      }
    });

    if (showSnackBar && mounted) {
      if (_isInsideGeofence && matched != null) {
        AppSnackBar.showSuccess(
          context,
          'أنت داخل نطاق فرع ${matched.branchName} (${minDistance.toInt()} متر) ✅',
        );
      } else if (closest != null) {
        AppSnackBar.showError(
          context,
          'أنت خارج نطاق الفرع (${minDistance.toInt()} متر). النطاق المسموح: ${(closest.geofenceRadius + 50).toInt()} متر.',
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
        'يرجى التأكد من تشغيل الـ GPS والانتظار حتى يتم تحديد موقعك.',
      );
      return;
    }

    final branchToUse = _matchedBranch ?? _nearestBranch;
    if (!_isInsideGeofence || branchToUse == null) {
      final distStr = _distanceToNearest != null
          ? '${_distanceToNearest!.toInt()} متر'
          : '';
      AppSnackBar.showError(
        parentContext,
        'عفواً، لا يمكنك تسجيل ${isCheckedIn ? "الانصراف" : "الحضور"} وأنت خارج نطاق الفرع ($distStr). يرجى التواجد داخل الفرع.',
      );
      return;
    }

    final branchName = branchToUse.branchName;
    final position = _currentPosition!;

    if (isCheckedIn && activeAttendance != null) {
      final now = _getTrustedNow();
      final isPreviousDay =
          activeAttendance.checkInTime.year != now.year ||
          activeAttendance.checkInTime.month != now.month ||
          activeAttendance.checkInTime.day != now.day;

      if (isPreviousDay) {
        _showPreviousDayCheckoutDialog(
          parentContext,
          activeAttendance,
          branchName,
          position,
          attendanceBloc,
          l10n,
        );
      } else if (activeAttendance.branchName == branchName ||
          activeAttendance.branchName == null) {
        attendanceBloc.add(
          CheckOutRequested(
            attendanceId: activeAttendance.id,
            userId: widget.delegate.uid,
            organizationId: widget.delegate.organizationUID,
            lat: position.latitude,
            long: position.longitude,
          ),
        );
      } else {
        _showForgotCheckoutDialog(
          parentContext,
          activeAttendance,
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
          'تسجيل حضور في $branchName...',
        );
      }
    }
  }

  Widget _buildGeofenceCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final isBusy = _isCheckingLocation || _isLoadingBranches;

    final containerColor = isBusy
        ? colorScheme.surfaceContainer
        : (_isInsideGeofence
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : colorScheme.errorContainer.withValues(alpha: 0.4));

    final borderColor = isBusy
        ? colorScheme.outlineVariant
        : (_isInsideGeofence
            ? colorScheme.primary.withValues(alpha: 0.3)
            : colorScheme.error.withValues(alpha: 0.3));

    return AnimatedContainer(
      duration: AppMotionDurations.medium2,
      curve: AppMotionCurves.standardDecelerate,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _GeofenceRadarWidget(
                animation: _radarAnimation,
                isInside: _isInsideGeofence,
                isChecking: isBusy,
                primaryColor: colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBusy
                          ? (isArabic ? 'جاري فحص الموقع والفرع...' : 'Checking location & branch...')
                          : (_isInsideGeofence
                              ? (isArabic ? 'أنت داخل نطاق العمل ✅' : 'Inside Work Zone ✅')
                              : (isArabic ? 'خارج نطاق الفرع 📍' : 'Outside Branch Zone 📍')),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isBusy
                            ? colorScheme.onSurface
                            : (_isInsideGeofence
                                ? colorScheme.primary
                                : colorScheme.error),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _locationStatusMessage ??
                          (isArabic
                              ? 'قم بالاقتراب من فرعك المعتمد لتسجيل الحضور'
                              : 'Move closer to your branch to check in'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_matchedBranch != null || _nearestBranch != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.store_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        (_matchedBranch ?? _nearestBranch)!.branchName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
              TextButton.icon(
                onPressed: isBusy
                    ? null
                    : () => _detectNearestBranch(showSnackBar: true, silent: false),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                icon: isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  isArabic ? 'إعادة فحص الموقع' : 'Recheck Location',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQRScanner(
    BuildContext context,
    bool isCheckedIn,
    Attendance? activeAttendance,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final attendanceBloc = _attendanceBloc;
    final parentContext = context;
    final action = isCheckedIn ? l10n.checkOut : l10n.checkIn;

    showModalBottomSheet<String>(
      context: context,
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
          if (isCheckedIn && activeAttendance != null) {
            final now = _getTrustedNow();
            final isPreviousDay =
                activeAttendance.checkInTime.year != now.year ||
                activeAttendance.checkInTime.month != now.month ||
                activeAttendance.checkInTime.day != now.day;

            if (isPreviousDay) {
              _showPreviousDayCheckoutDialog(
                parentContext,
                activeAttendance,
                scannedBranch,
                position,
                attendanceBloc,
                l10n,
              );
            } else if (activeAttendance.branchName == scannedBranch ||
                activeAttendance.branchName == null) {
              attendanceBloc.add(
                CheckOutRequested(
                  attendanceId: activeAttendance.id,
                  userId: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                  lat: position.latitude,
                  long: position.longitude,
                ),
              );
            } else {
              _showForgotCheckoutDialog(
                parentContext,
                activeAttendance,
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
                'تسجيل حضور في $scannedBranch...',
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
        AppSnackBar.showError(context, 'خدمات الموقع معطلة. يرجى تفعيلها.');
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        if (!silent) {
          AppSnackBar.showError(context, 'تم رفض إذن الوصول للموقع');
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      if (!silent) {
        AppSnackBar.showError(context, 'إذن الموقع مرفوض بشكل دائم.');
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
            'تم اكتشاف استخدام برنامج لتزييف الموقع الجغرافي (Fake GPS). يرجى إيقاف التطبيق لتسجيل الحضور والانصراف.',
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
              'تم اكتشاف استخدام برنامج لتزييف الموقع الجغرافي (Fake GPS). يرجى إيقاف التطبيق لتسجيل الحضور والانصراف.',
            );
          }
          return null;
        }
        return lastPosition;
      }
      if (context.mounted && !silent) {
        AppSnackBar.showError(
          context,
          'انتهى الوقت ولم نتمكن من تحديد الموقع. يرجى التأكد من تفعيل الـ GPS وأنت في مكان مفتوح.',
        );
      }
      return null;
    } catch (e) {
      if (context.mounted && !silent) {
        AppSnackBar.showError(context, 'حدث خطأ أثناء تحديد الموقع.');
      }
      return null;
    }
  }

  Future<String> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    try {
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
    final baseColor = colorScheme.surfaceContainerHighest;
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
                                  child: const Text(
                                    'وقت موثوق 🔒',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
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
                              ? Icons.logout_rounded
                              : Icons.login_rounded,
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
                icon: const Icon(Icons.close_rounded, color: Colors.white),
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
/// Features concentric pulsing circles with monotonic opacity decay (zero overshoot).
class _GeofenceRadarWidget extends StatelessWidget {
  final Animation<double> animation;
  final bool isInside;
  final bool isChecking;
  final Color primaryColor;

  const _GeofenceRadarWidget({
    required this.animation,
    required this.isInside,
    required this.isChecking,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isChecking
        ? primaryColor
        : (isInside ? const Color(0xFF10B981) : const Color(0xFFEF4444));

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final rippleVal = animation.value;
        return SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple
              Transform.scale(
                scale: 0.6 + (0.4 * rippleVal),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withValues(
                        alpha: (0.45 * (1.0 - rippleVal)).clamp(0.0, 0.45),
                      ),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // Inner ripple
              Transform.scale(
                scale: 0.3 + (0.45 * rippleVal),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(
                      alpha: (0.25 * (1.0 - rippleVal)).clamp(0.0, 0.25),
                    ),
                  ),
                ),
              ),
              // Center Core Button/Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  isChecking
                      ? Icons.radar_rounded
                      : (isInside
                          ? Icons.check_rounded
                          : Icons.location_off_rounded),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

