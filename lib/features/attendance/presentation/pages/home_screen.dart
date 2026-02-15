import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isCheckedIn = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider(
      create: (context) =>
          sl<AttendanceBloc>()..add(HistoryRequested(userId: widget.user.id)),
      child: Scaffold(
        backgroundColor: Colors.grey[50], // Light professional background
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Color(0xFF0D47A1)),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF0D47A1),
                child: Text(
                  widget.user.name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.helloUser(widget.user.name),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.delegateRole,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                // In real app, clear session
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        body: BlocConsumer<AttendanceBloc, AttendanceState>(
          listener: (context, state) {
            if (state is AttendanceError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            } else if (state is AttendanceCheckedIn) {
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
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isCheckedIn
                            ? [const Color(0xFF00BFA5), const Color(0xFF00897B)]
                            : [
                                const Color(0xFF757575),
                                const Color(0xFF424242),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isCheckedIn
                                      ? const Color(0xFF00BFA5)
                                      : Colors.grey)
                                  .withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          l10n.currentStatus,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isCheckedIn ? l10n.online : l10n.offline,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          DateFormat(
                            'EEEE, MMM d, yyyy',
                            Localizations.localeOf(context).languageCode,
                          ).format(DateTime.now()),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Big Action Button
                  GestureDetector(
                    onTap: state is AttendanceLoading
                        ? null
                        : () {
                            // Mock Location for now (30.0, 31.0)
                            if (isCheckedIn) {
                              // Need attendance ID properly, simplified for demonstration
                              // In real logic, we should fetch current active attendance
                              BlocProvider.of<AttendanceBloc>(context).add(
                                const CheckOutRequested(
                                  attendanceId: 'temp_id',
                                  lat: 30.0,
                                  long: 31.0,
                                ),
                              );
                            } else {
                              BlocProvider.of<AttendanceBloc>(context).add(
                                CheckInRequested(
                                  userId: widget.user.id,
                                  lat: 30.0,
                                  long: 31.0,
                                ),
                              );
                            }
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: isCheckedIn
                              ? Colors.orange
                              : const Color(0xFF0D47A1),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 15,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: state is AttendanceLoading
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isCheckedIn
                                        ? Icons.exit_to_app
                                        : Icons.touch_app,
                                    size: 40,
                                    color: isCheckedIn
                                        ? Colors.orange
                                        : const Color(0xFF0D47A1),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    isCheckedIn ? l10n.checkOut : l10n.checkIn,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isCheckedIn
                                          ? Colors.orange
                                          : const Color(0xFF0D47A1),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                  Text(
                    l10n.recentHistory,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: state is AttendanceHistoryLoaded
                        ? ListView.builder(
                            itemCount: state.history.length,
                            itemBuilder: (context, index) {
                              final item = state.history[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.history,
                                      color: Color(0xFF0D47A1),
                                    ),
                                  ),
                                  title: Text(
                                    DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(item.checkInTime),
                                  ),
                                  subtitle: Text(
                                    l10n.historyInOut(
                                      DateFormat(
                                        'HH:mm',
                                      ).format(item.checkInTime),
                                      item.checkOutTime != null
                                          ? DateFormat(
                                              'HH:mm',
                                            ).format(item.checkOutTime!)
                                          : l10n.active,
                                    ),
                                  ),
                                  trailing: item.checkOutTime == null
                                      ? const Icon(
                                          Icons.circle,
                                          color: Colors.green,
                                          size: 12,
                                        )
                                      : const Icon(
                                          Icons.check_circle,
                                          color: Colors.grey,
                                          size: 16,
                                        ),
                                ),
                              );
                            },
                          )
                        : Center(child: Text(l10n.noHistoryAvailable)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
