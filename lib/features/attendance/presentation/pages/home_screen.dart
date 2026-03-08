import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/injection_container.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  final Delegate delegate;

  const HomeScreen({super.key, required this.delegate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isCheckedIn = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return BlocProvider(
      create: (context) =>
          sl<AttendanceBloc>()
            ..add(HistoryRequested(userId: widget.delegate.uid)),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: theme.colorScheme.surfaceTint,
          iconTheme: IconThemeData(color: theme.colorScheme.primary),
          title: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.helloUser(widget.delegate.firstName),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.delegateRole,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l10n.logout,
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
                  backgroundColor: theme.colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else if (state is AttendanceCheckedIn) {
              setState(() => isCheckedIn = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.checkedInSuccessfully),
                  backgroundColor: theme.colorScheme.tertiary,
                ),
              );
            } else if (state is AttendanceCheckedOut) {
              setState(() => isCheckedIn = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.checkedOutSuccessfully),
                  backgroundColor: theme.colorScheme.secondary,
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
                  Card(
                    color: isCheckedIn
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            l10n.currentStatus,
                            style: TextStyle(
                              color: isCheckedIn
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isCheckedIn ? l10n.online : l10n.offline,
                            style: TextStyle(
                              color: isCheckedIn
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
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
                            style: TextStyle(
                              color: isCheckedIn
                                  ? theme.colorScheme.onPrimary.withValues(
                                      alpha: 0.8,
                                    )
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Big Action Button
                  GestureDetector(
                    onTap: state is AttendanceLoading
                        ? null
                        : () async {
                            final position = await _getCurrentLocation(context);
                            if (position == null || !context.mounted) return;

                            if (isCheckedIn) {
                              final activeId = context
                                  .read<AttendanceBloc>()
                                  .currentAttendanceId;
                              if (activeId == null) return;

                              context.read<AttendanceBloc>().add(
                                CheckOutRequested(
                                  attendanceId: activeId,
                                  userId: widget.delegate.uid,
                                  lat: position.latitude,
                                  long: position.longitude,
                                ),
                              );
                            } else {
                              final deviceInfoPlugin = DeviceInfoPlugin();
                              String deviceInfoStr = 'Unknown Device';
                              try {
                                if (Platform.isAndroid) {
                                  final androidInfo =
                                      await deviceInfoPlugin.androidInfo;
                                  deviceInfoStr =
                                      '${androidInfo.brand} ${androidInfo.model}';
                                } else if (Platform.isIOS) {
                                  final iosInfo =
                                      await deviceInfoPlugin.iosInfo;
                                  deviceInfoStr =
                                      '${iosInfo.name} ${iosInfo.systemName} ${iosInfo.systemVersion}';
                                }
                              } catch (_) {}

                              if (!context.mounted) return;

                              context.read<AttendanceBloc>().add(
                                CheckInRequested(
                                  userId: widget.delegate.uid,
                                  companyId: widget.delegate.companyUID,
                                  organizationId:
                                      widget.delegate.organizationUID,
                                  deviceInfo: deviceInfoStr,
                                  lat: position.latitude,
                                  long: position.longitude,
                                  branchName:
                                      'الفرع الرئيسي', // Default for manual button in Home
                                ),
                              );
                            }
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: isCheckedIn
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: 0.1,
                            ),
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
                                        ? theme.colorScheme.secondary
                                        : theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    isCheckedIn ? l10n.checkOut : l10n.checkIn,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isCheckedIn
                                          ? theme.colorScheme.secondary
                                          : theme.colorScheme.primary,
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
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
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.history,
                                      color: theme.colorScheme.primary,
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
                                      ? Icon(
                                          Icons.circle,
                                          color: theme.colorScheme.secondary,
                                          size: 12,
                                        )
                                      : Icon(
                                          Icons.check_circle,
                                          color:
                                              theme.colorScheme.outlineVariant,
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

  Future<Position?> _getCurrentLocation(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خدمات الموقع معطلة. يرجى تفعيلها.')),
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
            const SnackBar(content: Text('تم رفض إذن الوصول للموقع')),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('إذن الموقع مرفوض بشكل دائم.')),
        );
      }
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
