import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/attendance_action_button.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/attendance_history_list.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/current_status_card.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/home_app_bar.dart';
import 'package:delegate_app/injection_container.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  final Delegate delegate;

  const HomeScreen({super.key, required this.delegate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
        appBar: HomeAppBar(delegate: widget.delegate),
        body: BlocConsumer<AttendanceBloc, AttendanceState>(
          listener: (context, state) {
            if (state is AttendanceError) {
              AppSnackBar.showError(context, state.message);
            } else if (state is AttendanceCheckedIn) {
              AppSnackBar.showSuccess(context, l10n.checkedInSuccessfully);
              context.read<AttendanceBloc>().add(
                HistoryRequested(userId: widget.delegate.uid),
              );
            } else if (state is AttendanceCheckedOut) {
              AppSnackBar.showSuccess(context, l10n.checkedOutSuccessfully);
              context.read<AttendanceBloc>().add(
                HistoryRequested(userId: widget.delegate.uid),
              );
            }
          },
          builder: (context, state) {
            bool isCheckedIn = false;
            String? activeAttendanceId;

            if (state is AttendanceHistoryLoaded) {
              isCheckedIn = state.activeAttendanceId != null;
              activeAttendanceId = state.activeAttendanceId;
            }

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CurrentStatusCard(isCheckedIn: isCheckedIn),

                  const SizedBox(height: 40),

                  Center(
                    child: AttendanceActionButton(
                      isCheckedIn: isCheckedIn,
                      isLoading: state is AttendanceLoading,
                      onTap: () async {
                        final position = await _getCurrentLocation(context);
                        if (position == null || !context.mounted) return;

                        if (isCheckedIn) {
                          if (activeAttendanceId == null) return;
                          context.read<AttendanceBloc>().add(
                            CheckOutRequested(
                              attendanceId: activeAttendanceId,
                              userId: widget.delegate.uid,
                              lat: position.latitude,
                              long: position.longitude,
                            ),
                          );
                        } else {
                          final deviceInfoStr = await _getDeviceInfo();
                          if (!context.mounted) return;
                          context.read<AttendanceBloc>().add(
                            CheckInRequested(
                              userId: widget.delegate.uid,
                              companyId: widget.delegate.companyUID,
                              organizationId: widget.delegate.organizationUID,
                              deviceInfo: deviceInfoStr,
                              lat: position.latitude,
                              long: position.longitude,
                              branchName: 'الفرع الرئيسي',
                            ),
                          );
                        }
                      },
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
                        ? AttendanceHistoryList(history: state.history)
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

  Future<Position?> _getCurrentLocation(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      AppSnackBar.showError(context, 'خدمات الموقع معطلة. يرجى تفعيلها.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        AppSnackBar.showError(context, 'تم رفض إذن الوصول للموقع');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      AppSnackBar.showError(context, 'إذن الموقع مرفوض بشكل دائم.');
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
