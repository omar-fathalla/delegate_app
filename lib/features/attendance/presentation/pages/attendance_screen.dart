import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/injection_container.dart';
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
  final List<String> _branches = [
    'سموحة',
    'الابراهيمية',
    'عجمي ستار',
    'الرحاب',
  ];
  String _selectedBranch = 'سموحة';
  bool isCheckedIn = false;
  bool _isProcessing = false; // Guard against multiple scans

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          sl<AttendanceBloc>()..add(HistoryRequested(userId: widget.user.id)),
      child: BlocConsumer<AttendanceBloc, AttendanceState>(
        listener: (context, state) {
          if (state is AttendanceCheckedIn) {
            setState(() => isCheckedIn = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Checked In Successfully'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is AttendanceCheckedOut) {
            setState(() => isCheckedIn = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Checked Out Successfully'),
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
            appBar: AppBar(
              title: const Text('Attendance'),
              centerTitle: true,
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
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
                isCheckedIn ? 'Scan to Check Out' : 'Scan to Check In',
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Month Selector
          Row(
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
                    // Trigger refresh of history based on month (Implementation needed in Logic)
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedMonth),
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
          const SizedBox(height: 16),
          // Branch Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranch,
                dropdownColor: const Color(0xFF0D47A1),
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: _branches.map((String branch) {
                  return DropdownMenuItem<String>(
                    value: branch,
                    child: Text(branch),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedBranch = newValue!;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AttendanceState state) {
    if (state is AttendanceLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (state is AttendanceHistoryLoaded) {
      // Filter history by selected Month (Logic usually should be in Bloc, but simplistic here)
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
                'No attendance records for ${DateFormat('MMMM').format(_selectedMonth)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.only(
          top: 16,
          bottom: 80,
          left: 16,
          right: 16,
        ),
        itemCount: history.length,
        itemBuilder: (context, index) {
          final item = history[index];
          final dateStr = DateFormat('dd').format(item.checkInTime);
          final dayStr = DateFormat('EEE').format(item.checkInTime);
          final inTime = DateFormat(
            'hh:mm a',
          ).format(item.checkInTime); // 12h format
          final outTime = item.checkOutTime != null
              ? DateFormat('hh:mm a').format(item.checkOutTime!)
              : '--:--';

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      Text(
                        dayStr,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.login,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'In: $inTime',
                            style: const TextStyle(fontWeight: FontWeight.w500),
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
                            'Out: $outTime',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _selectedBranch,
                    style: const TextStyle(fontSize: 10, color: Colors.blue),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return const Center(child: Text('Something went wrong'));
  }

  void _showQRScanner(BuildContext context) {
    final attendanceBloc = BlocProvider.of<AttendanceBloc>(context);
    final parentContext = context; // Save parent context for SnackBars
    final action = isCheckedIn ? 'Check Out' : 'Check In';
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
try {
  final dynamic decoded = jsonDecode(rawValue);

  // التحقق من أن البيانات عبارة عن Map وأن النوع هو attendance
  if (decoded is Map<String, dynamic> && decoded['type'] == 'attendance') {
    if (decoded.containsKey('branch') && decoded['branch'] is String) {
      scannedBranch = decoded['branch'] as String;
    }
  }
} catch (e) {
  // في حال فشل تحويل الـ JSON، يمكنك وضع كود احتياطي هنا أو طباعة خطأ
  print("Error decoding JSON: $e");
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
                          content: Text('تسجيل حضور في $scannedBranch...'),
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'QR Code غير صالح. يرجى مسح كود فرع صحيح.',
                        ),
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
                      'مسح لـ $action',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _selectedBranch,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
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
                              DateFormat('EEEE, d MMMM').format(DateTime.now()),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              DateFormat('hh:mm a').format(DateTime.now()),
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
                      'وجه الكاميرا نحو QR Code لـ $action',
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
