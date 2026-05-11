import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedMonth = DateTime.now();

  // --- Performance: Cache connectivity state instead of StreamBuilder ---
  bool _isOffline = false;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  List<Attendance> _rawHistory = [];
  List<Attendance> _filteredHistory = [];
  Map<String, List<Attendance>> _groupedByDay = {};
  List<String> _dayKeys = [];

  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Subscribe to connectivity changes once
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_isBottom) {
      final bloc = context.read<AttendanceBloc>();
      final state = bloc.state;
      if (state is AttendanceHistoryLoaded &&
          !state.isLoadingMore &&
          !state.hasReachedMax) {
        bloc.add(
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
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _scrollController.dispose();
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
      });
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
    return BlocProvider(
      key: ValueKey(widget.delegate.organizationUID),
      create: (context) {
        final bloc = sl<AttendanceBloc>();
        bloc.add(
          HistoryRequested(
            userId: widget.delegate.uid,
            organizationId: widget.delegate.organizationUID,
            nationalityID: widget.delegate.nationalityID,
            phoneNumber: widget.delegate.phoneNumber,
          ),
        );
        // Delay sync request to allow history to load first
        Future.delayed(const Duration(seconds: 2), () {
          if (!bloc.isClosed) {
            bloc.add(const SyncRequested());
          }
        }).ignore();
        return bloc;
      },
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
                ? AppBar(title: Text(widget.delegate.fullName))
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
                        : () => _showQRScanner(
                            context,
                            isCheckedIn,
                            activeAttendance,
                          ),
                    backgroundColor: isCheckedIn
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    icon: Icon(
                      Icons.qr_code_scanner,
                      color: isCheckedIn
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    label: Text(
                      isCheckedIn ? l10n.scanToCheckOut : l10n.scanToCheckIn,
                      style: TextStyle(
                        color: isCheckedIn
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onPrimaryContainer,
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

  Widget _buildHeader(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
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
                  child: const Icon(Icons.chevron_left_rounded, size: 28),
                ),
                Text(
                  DateFormat('MMMM yyyy', locale).format(_selectedMonth),
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
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
                  child: const Icon(Icons.chevron_right_rounded, size: 28),
                ),
              ],
            ),
            if (_isOffline) ...[
              const SizedBox(height: 20),
              _buildConnectivityBadge(context, l10n),
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
                context.read<AttendanceBloc>().add(
                  HistoryRequested(
                    userId: widget.delegate.uid,
                    organizationId: widget.delegate.organizationUID,
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
          context.read<AttendanceBloc>().add(const SyncRequested());
          context.read<AttendanceBloc>().add(
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
          padding: const EdgeInsetsDirectional.only(top: 16, bottom: 80),
          itemCount: _dayKeys.length + (state.hasReachedMax ? 0 : 1),
          itemBuilder: (context, dayIndex) {
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

  void _showQRScanner(
    BuildContext context,
    bool isCheckedIn,
    Attendance? activeAttendance,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final attendanceBloc = BlocProvider.of<AttendanceBloc>(context);
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

        final position = await _getCurrentLocation(parentContext);
        if (position != null && parentContext.mounted) {
          if (isCheckedIn && activeAttendance != null) {
            final now = DateTime.now();
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

  Future<Position?> _getCurrentLocation(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return null;
      AppSnackBar.showError(context, 'خدمات الموقع معطلة. يرجى تفعيلها.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        AppSnackBar.showError(context, 'تم رفض إذن الوصول للموقع');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      AppSnackBar.showError(context, 'إذن الموقع مرفوض بشكل دائم.');
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on TimeoutException catch (_) {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        return lastPosition;
      }
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          'انتهى الوقت ولم نتمكن من تحديد الموقع. يرجى التأكد من تفعيل الـ GPS وأنت في مكان مفتوح.',
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
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

  void _showForgotCheckoutDialog(
    BuildContext context,
    Attendance activeAttendance,
    String newBranch,
    Position position,
    AttendanceBloc bloc,
    AppLocalizations l10n,
  ) {
    showDialog(
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
    showDialog(
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

class _ScannerModalState extends State<_ScannerModal> {
  late final MobileScannerController _scannerController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isCheckedIn = widget.action == l10n.checkOut;
    final color = isCheckedIn ? colorScheme.secondary : colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (!mounted || _isProcessing) return;
              _isProcessing = true;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
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
                } catch (_) {}

                if (mounted) {
                  // Wait for stop to finish, or just call it.
                  _scannerController.stop();
                  Navigator.pop(context, scannedBranch ?? "");
                }
              } else {
                _isProcessing = false;
              }
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.scrim.withValues(alpha: 0.7),
                    colorScheme.scrim.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.scanForAction(widget.action),
                    style: TextStyle(
                      color: colorScheme.surface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, d MMMM',
                              Localizations.localeOf(context).languageCode,
                            ).format(DateTime.now()),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            DateFormat(
                              'hh:mm a',
                              Localizations.localeOf(context).languageCode,
                            ).format(DateTime.now()),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCheckedIn ? Icons.logout : Icons.login,
                          color: color,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.pointCameraToQR(widget.action),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: colorScheme.surface.withValues(alpha: 0.3),
              child: IconButton(
                tooltip: l10n.close,
                icon: Icon(Icons.close, color: colorScheme.surface),
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
