import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart'; // تم الاحتفاظ بها
import 'package:geolocator/geolocator.dart'; // تم الاحتفاظ بها
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

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedMonth = DateTime.now();

  bool isCheckedIn = false;
  bool _isProcessing = false; // Guard against multiple scans

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider(
      create: (context) => sl<AttendanceBloc>()
        ..add(HistoryRequested(userId: widget.delegate.uid))
        ..add(const SyncRequested()),
      child: BlocConsumer<AttendanceBloc, AttendanceState>(
        listener: (context, state) {
          if (state is AttendanceCheckedIn) {
            setState(() => isCheckedIn = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.checkedInSuccessfully),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is AttendanceCheckedOut) {
            setState(() => isCheckedIn = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.checkedOutSuccessfully),
                backgroundColor: Colors.orange,
              ),
            );
          } else if (state is AttendanceError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is AttendanceHistoryLoaded) {
            final hasActiveCheckIn = state.history.any(
              (element) => element.checkOutTime == null,
            );
            setState(() {
              isCheckedIn = hasActiveCheckIn;
            });
          } else if (state is AttendanceSyncSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تمت مزامنة البيانات المحفوظة بنجاح'),
                backgroundColor: Colors.green,
              ),
            );
            context.read<AttendanceBloc>().add(
              HistoryRequested(userId: widget.delegate.uid),
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            body: Column(
              children: [
                _buildHeader(context),
                Expanded(child: _buildBody(context, state)),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed:
                  (state is AttendanceLoading ||
                      state is AttendanceSyncInProgress)
                  ? null
                  : () => _showQRScanner(context),
              backgroundColor: isCheckedIn
                  ? Colors.orange
                  : const Color(0xFF0D47A1),
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: Text(
                isCheckedIn ? l10n.scanToCheckOut : l10n.scanToCheckIn,
                style: const TextStyle(color: Colors.white),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF42A5F5),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous Month',
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy', locale).format(_selectedMonth),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                tooltip: 'Next Month',
                icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snapshot) {
              final isOffline =
                  snapshot.data?.contains(ConnectivityResult.none) ?? false;

              if (isOffline) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.networkStatusOffline,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_done_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.networkStatusOnline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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
  }

  Widget _buildBody(BuildContext context, AttendanceState state) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    if (state is AttendanceLoading ||
        state is AttendanceInitial ||
        state is AttendanceCheckedIn ||
        state is AttendanceCheckedOut) {
      return const Center(child: CircularProgressIndicator());
    } else if (state is AttendanceError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              state.message,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
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
      final history = state.history.where((attendance) {
        return attendance.checkInTime.month == _selectedMonth.month &&
            attendance.checkInTime.year == _selectedMonth.year;
      }).toList();

      if (history.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 64,
                  color: Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.noHistoryAvailable,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.scanToCheckIn,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        );
      }

      history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      final Map<String, List<Attendance>> groupedByDay = {};
      for (final item in history) {
        final dayKey = DateFormat('yyyy-MM-dd').format(item.checkInTime);
        groupedByDay.putIfAbsent(dayKey, () => []).add(item);
      }
      final dayKeys = groupedByDay.keys.toList();

      return RefreshIndicator(
        onRefresh: () async {
          context.read<AttendanceBloc>().add(const SyncRequested());
          context.read<AttendanceBloc>().add(
            HistoryRequested(userId: widget.delegate.uid),
          );
        },
        child: ListView.builder(
          padding: const EdgeInsetsDirectional.only(
            top: 16,
            bottom: 80,
            start: 16,
            end: 16,
          ),
          itemCount: dayKeys.length,
          itemBuilder: (context, dayIndex) {
            final dayKey = dayKeys[dayIndex];
            final records = groupedByDay[dayKey] ?? [];
            final dayDate = records.first.checkInTime;
            final fullDateStr = DateFormat(
              'EEEE، d MMMM yyyy',
              locale,
            ).format(dayDate);

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
                          color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fullDateStr,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${records.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0D47A1),
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

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
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
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    branchName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.login,
                                    size: 16,
                                    color: Colors.green,
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
                                  const Icon(
                                    Icons.logout,
                                    size: 16,
                                    color: Colors.orange,
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
                                        ? const Color(0xFF0D47A1)
                                        : Colors.grey[400],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    durationStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: item.checkOutTime != null
                                          ? const Color(0xFF0D47A1)
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!item.isSynced)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(end: 8.0),
                            child: Icon(
                              Icons.cloud_off,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                        if (item.checkOutTime == null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.active,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (dayIndex < dayKeys.length - 1) const Divider(height: 24),
              ],
            );
          },
        ),
      );
    }
    return Center(child: Text(l10n.somethingWentWrong));
  }

  void _showQRScanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final attendanceBloc = BlocProvider.of<AttendanceBloc>(context);
    final parentContext = context;
    final action = isCheckedIn ? l10n.checkOut : l10n.checkIn;
    final color = isCheckedIn ? Colors.orange : const Color(0xFF0D47A1);
    _isProcessing = false;

    final scannerController = MobileScannerController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.black,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
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
                  debugPrint('Barcode found! $rawValue');

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
                  } catch (e) {
                    debugPrint('Error parsing QR: $e');
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
                      if (isCheckedIn) {
                        attendanceBloc.add(
                          CheckOutRequested(
                            attendanceId: attendanceBloc.currentAttendanceId!,
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
                        backgroundColor: Colors.red,
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
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.scanForAction(action),
                      style: const TextStyle(
                        color: Colors.white,
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
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
                                color: Colors.grey[600],
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
                              style: const TextStyle(
                                color: Colors.black87,
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
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                child: IconButton(
                  tooltip: 'Close Scanner',
                  icon: const Icon(Icons.close, color: Colors.white),
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
          const SnackBar(
            content: Text(
              'Location services are disabled. Please enable them.',
            ),
            backgroundColor: Colors.red,
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
            const SnackBar(
              content: Text('Location permissions are denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permissions are permanently denied, we cannot request permissions.',
            ),
            backgroundColor: Colors.red,
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
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return 'Unknown Device';
  }
}
