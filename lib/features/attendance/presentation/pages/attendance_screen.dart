import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AttendanceScreen extends StatefulWidget {
  final User user;

  const AttendanceScreen({super.key, required this.user});

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
      create: (context) =>
          sl<AttendanceBloc>()..add(HistoryRequested(userId: widget.user.id)),
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
            // Check if there is an active check-in (no check-out time)
            final hasActiveCheckIn = state.history.any(
              (element) => element.checkOutTime == null,
            );
            setState(() {
              isCheckedIn = hasActiveCheckIn;
            });
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
              onPressed: () => _showQRScanner(context),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF42A5F5),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
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
    );
  }

  Widget _buildBody(BuildContext context, AttendanceState state) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    if (state is AttendanceLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (state is AttendanceHistoryLoaded) {
      // Filter history by selected month
      final history = state.history.where((attendance) {
        return attendance.checkInTime.month == _selectedMonth.month &&
            attendance.checkInTime.year == _selectedMonth.year;
      }).toList();

      if (history.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                l10n.noRecordsForMonth(
                  DateFormat('MMMM', locale).format(_selectedMonth),
                ),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }

      // Sort records by date (newest first)
      history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      // Group records by day
      final Map<String, List<Attendance>> groupedByDay = {};
      for (final item in history) {
        final dayKey = DateFormat('yyyy-MM-dd').format(item.checkInTime);
        groupedByDay.putIfAbsent(dayKey, () => []).add(item);
      }
      final dayKeys = groupedByDay.keys.toList();

      return ListView.builder(
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
              // Day header
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
              // Records for this day
              ...records.map((item) {
                final inTime = DateFormat(
                  'hh:mm a',
                  locale,
                ).format(item.checkInTime);
                final outTime = item.checkOutTime != null
                    ? DateFormat('hh:mm a', locale).format(item.checkOutTime!)
                    : '--:--';
                final branchName = item.branchName ?? l10n.unspecifiedBranch;

                // Calculate duration
                String durationStr;
                if (item.checkOutTime != null) {
                  final diff = item.checkOutTime!.difference(item.checkInTime);
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
                      // In/Out times column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Branch name
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
                            // Duration
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
                      // Active indicator
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
      );
    }
    return Center(child: Text(l10n.somethingWentWrong));
  }

  void _showQRScanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final attendanceBloc = BlocProvider.of<AttendanceBloc>(context);
    final parentContext = context; // Save parent context for SnackBars
    final action = isCheckedIn ? l10n.checkOut : l10n.checkIn;
    final color = isCheckedIn ? Colors.orange : const Color(0xFF0D47A1);
    _isProcessing = false; // Reset guard

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
              onDetect: (capture) {
                // Guard: only process once
                if (_isProcessing) return;
                _isProcessing = true;

                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String rawValue = barcodes.first.rawValue ?? '';
                  debugPrint('Barcode found! $rawValue');

                  // Parse branch from QR
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

                  // Stop camera FIRST to prevent black screen
                  scannerController.stop();

                  // Close scanner bottom sheet
                  Navigator.pop(parentContext);

                  if (scannedBranch != null) {
                    if (isCheckedIn) {
                      attendanceBloc.add(
                        CheckOutRequested(
                          attendanceId: attendanceBloc.currentAttendanceId!,
                          lat: 30.0444,
                          long: 31.2357,
                        ),
                      );
                    } else {
                      _checkIn(parentContext, attendanceBloc, scannedBranch);
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: Text(l10n.checkingInAt(scannedBranch)),
                        ),
                      );
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
                  _isProcessing = false; // Reset if no barcodes
                }
              },
            ),
            // Top Overlay
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
            // Bottom Info Panel
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
            // Close Button
            Positioned(
              top: 40,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                child: IconButton(
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

  void _checkIn(BuildContext context, AttendanceBloc bloc, String branchName) {
    bloc.add(
      CheckInRequested(
        userId: widget.user.id,
        lat:
            30.0444, // Mock location for now, or use real location if available
        long: 31.2357,
        branchName: branchName,
      ),
    );
  }
}
