import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AttendanceScreen extends StatefulWidget {
  final Delegate delegate;

  const AttendanceScreen({super.key, required this.delegate});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedMonth = DateTime.now();

  bool _isProcessing = false; // Guard against multiple scans

  // --- Performance: Cache connectivity state instead of StreamBuilder ---
  bool _isOffline = false;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  // --- Performance: Cache filtered/grouped history ---
  List<Attendance> _rawHistory = [];
  List<Attendance> _filteredHistory = [];
  Map<String, List<Attendance>> _groupedByDay = {};
  List<String> _dayKeys = [];

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
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
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
      create: (context) => sl<AttendanceBloc>()
        ..add(HistoryRequested(userId: widget.delegate.uid))
        ..add(const SyncRequested()),
      child: BlocConsumer<AttendanceBloc, AttendanceState>(
        listener: (context, state) {
          if (state is AttendanceCheckedIn) {
            final theme = Theme.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.checkedInSuccessfully),
                backgroundColor: theme.colorScheme.tertiary,
              ),
            );
            context.read<AttendanceBloc>().add(
              HistoryRequested(userId: widget.delegate.uid),
            );
          } else if (state is AttendanceCheckedOut) {
            final theme = Theme.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.checkedOutSuccessfully),
                backgroundColor: theme.colorScheme.secondary,
              ),
            );
            context.read<AttendanceBloc>().add(
              HistoryRequested(userId: widget.delegate.uid),
            );
          } else if (state is AttendanceError) {
            final theme = Theme.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: theme.colorScheme.error,
              ),
            );
          } else if (state is AttendanceHistoryLoaded) {
            // --- Performance: cache + compute only when data changes ---
            _rawHistory = state.history;
            _recomputeFilteredHistory();

            if (state.syncStatus == SyncStatus.success) {
              final theme = Theme.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('تمت مزامنة البيانات المحفوظة بنجاح'),
                  backgroundColor: theme.colorScheme.tertiary,
                ),
              );
              Future.delayed(const Duration(seconds: 1), () {
                if (context.mounted) {
                  context.read<AttendanceBloc>().add(
                    HistoryRequested(userId: widget.delegate.uid),
                  );
                }
              });
            } else if (state.syncStatus == SyncStatus.failure) {
              final theme = Theme.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('فشلت المزامنة'),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
            }
          }
        },
        builder: (context, state) {
          bool isCheckedIn = false;
          String? activeAttendanceId;
          bool isSyncing = false;

          if (state is AttendanceHistoryLoaded) {
            isCheckedIn = state.activeAttendanceId != null;
            activeAttendanceId = state.activeAttendanceId;
            isSyncing = state.syncStatus == SyncStatus.inProgress;
          }

          return Scaffold(
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
            floatingActionButton: FloatingActionButton.extended(
              onPressed: (state is AttendanceLoading || isSyncing)
                  ? null
                  : () => _showQRScanner(
                      context,
                      isCheckedIn,
                      activeAttendanceId,
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
                  HistoryRequested(userId: widget.delegate.uid),
                );
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    } else if (state is AttendanceHistoryLoaded) {
      // --- Performance: Use pre-computed cached data ---
      if (_filteredHistory.isEmpty) {
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
            HistoryRequested(userId: widget.delegate.uid),
          );
        },
        child: ListView.builder(
          padding: const EdgeInsetsDirectional.only(top: 16, bottom: 80),
          itemCount: _dayKeys.length,
          itemBuilder: (context, dayIndex) {
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
    String? activeAttendanceId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final attendanceBloc = BlocProvider.of<AttendanceBloc>(context);
    final parentContext = context;
    final action = isCheckedIn ? l10n.checkOut : l10n.checkIn;
    final color = isCheckedIn ? colorScheme.secondary : colorScheme.primary;
    _isProcessing = false;

    final scannerController = MobileScannerController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Scaffold(
        body: Stack(
          children: [
            MobileScanner(
              controller: scannerController,
              onDetect: (capture) async {
                if (_isProcessing) return;
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
                  } catch (_) {
                  }

                  scannerController.stop();
                  Navigator.pop(parentContext);

                  if (scannedBranch != null) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text('Fetching location...'),
                        duration: Duration(seconds: 1),
                      ),
                    );

                    final position = await _getCurrentLocation(parentContext);
                    if (position != null && parentContext.mounted) {
                      if (isCheckedIn && activeAttendanceId != null) {
                        attendanceBloc.add(
                          CheckOutRequested(
                            attendanceId: activeAttendanceId,
                            userId: widget.delegate.uid,
                            lat: position.latitude,
                            long: position.longitude,
                          ),
                        );
                      } else {
                        await _checkIn(attendanceBloc, scannedBranch, position);
                        if (parentContext.mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text('تسجيل حضور في $scannedBranch...'),
                            ),
                          );
                        }
                      }
                    }
                  } else {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text(l10n.invalidQRCode),
                        backgroundColor: colorScheme.error,
                      ),
                    );
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
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
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
                      l10n.scanForAction(action),
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
                                Localizations.localeOf(
                                  parentContext,
                                ).languageCode,
                              ).format(DateTime.now()),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              DateFormat(
                                'hh:mm a',
                                Localizations.localeOf(
                                  parentContext,
                                ).languageCode,
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
                      l10n.pointCameraToQR(action),
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
                  tooltip: 'Close Scanner',
                  icon: Icon(Icons.close, color: colorScheme.surface),
                  onPressed: () {
                    scannerController.stop();
                    Navigator.pop(parentContext);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      scannerController.dispose();
      _isProcessing = false;
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location services are disabled. Please enable them.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permissions are denied'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location permissions are permanently denied, we cannot request permissions.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
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
    } catch (_) {
    }
    return 'Unknown Device';
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
