import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_location_fetcher.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/attendance_action_button.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_action_lock.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/early_checkout_confirm_sheet.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/attendance_history_list.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/current_status_card.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/home_app_bar.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_summary_card.dart';
import 'package:delegate_app/injection_container.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/keyed_stream_builder.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/security_audit_service.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';

class HomeScreen extends StatefulWidget {
  final Delegate delegate;

  const HomeScreen({super.key, required this.delegate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AttendanceActionLock _actionLock = AttendanceActionLock();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return BlocProvider(
      create: (context) => sl<AttendanceBloc>()
        ..add(
          HistoryRequested(
            userId: widget.delegate.uid,
            organizationId: widget.delegate.organizationUID,
          ),
        ),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: HomeAppBar(delegate: widget.delegate),
        body: BlocConsumer<AttendanceBloc, AttendanceState>(
          listener: (context, state) {
            if (state is AttendanceError) {
              AppSnackBar.showError(context, state.message);
            } else if (state is AttendanceCheckedIn) {
              AppSnackBar.showSuccess(context, l10n.checkedInSuccessfully);
              if (WebRuntimePolicy.liveTrackingEnabled) {
                DelegateTrackingEngine()
                    .startTrackingSession(delegateId: widget.delegate.uid);
              }
              context.read<AttendanceBloc>().add(
                HistoryRequested(
                  userId: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                ),
              );
            } else if (state is AttendanceCheckedOut) {
              AppSnackBar.showSuccess(context, l10n.checkedOutSuccessfully);
              DelegateTrackingEngine().stopTrackingSession();
              context.read<AttendanceBloc>().add(
                HistoryRequested(
                  userId: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                ),
              );
            }
          },
          builder: (context, state) {
            bool isCheckedIn = false;
            Attendance? activeAttendance;

            if (state is AttendanceHistoryLoaded) {
              isCheckedIn = state.activeAttendance != null;
              activeAttendance = state.activeAttendance;

              if (WebRuntimePolicy.liveTrackingEnabled &&
                  isCheckedIn &&
                  !DelegateTrackingEngine().isTracking) {
                DelegateTrackingEngine()
                    .startTrackingSession(delegateId: widget.delegate.uid);
              }
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
                      isLoading:
                          state is AttendanceLoading || _actionLock.isBusy,
                      loadingLabel:
                          _actionLock.isBusy ? l10n.attLocatingShort : null,
                      onTap: () => _actionLock.run(
                        bloc: context.read<AttendanceBloc>(),
                        onChanged: () {
                          if (mounted) setState(() {});
                        },
                        action: () async {
                        final position = await _getCurrentLocation(context);
                        if (position == null || !context.mounted) return;

                        if (isCheckedIn) {
                          final attendance = activeAttendance;
                          if (attendance == null) return;
                          if (!await confirmEarlyCheckOutIfNeeded(
                            context,
                            checkInTime: attendance.checkInTime,
                            now: sl.isRegistered<TrustedTimeService>()
                                ? sl<TrustedTimeService>().now
                                : DateTime.now(),
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          context.read<AttendanceBloc>().add(
                            CheckOutRequested(
                              attendanceId: attendance.id,
                              userId: widget.delegate.uid,
                              organizationId: widget.delegate.organizationUID,
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
                              delegateName: widget.delegate.fullName.isNotEmpty
                                  ? widget.delegate.fullName
                                  : null,
                              phoneNumber: widget.delegate.phoneNumber.isNotEmpty
                                  ? widget.delegate.phoneNumber
                                  : null,
                              companyName: widget.delegate.companyName.isNotEmpty
                                  ? widget.delegate.companyName
                                  : null,
                              personalPhotoURL: widget.delegate.personalPhotoForCopy,
                            ),
                          );
                        }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Task Summary ──
                  _DelegateTaskSummary(delegate: widget.delegate),

                  const SizedBox(height: 24),
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
    if (!WebRuntimePolicy.delegateDeviceBindingEnabled) {
      return 'Web Browser';
    }
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
    if (!WebRuntimePolicy.checkInEnabled) {
      if (context.mounted) {
        AppSnackBar.showInfo(context, WebRuntimePolicy.checkInWebMessage);
      }
      return null;
    }
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

    // Same fallback chain as the attendance screen (TAS-278).
    final fix = await AttendanceLocationFetcher().fetch();
    if (fix == null) {
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.locationTimeout,
        );
      }
      return null;
    }
    final position = fix.position;

    if (position.isMocked) {
      final device = await _getDeviceInfo();
      SecurityAuditService.logMockLocationViolation(
        delegate: widget.delegate,
        position: position,
        deviceModel: device,
        actionType: 'تسجيل حضور/انصراف',
      );
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          'تم اكتشاف استخدام برنامج لتزييف الموقع الجغرافي (Fake GPS). يرجى إيقاف التطبيق لتسجيل الحضور والانصراف.',
        );
      }
      return null;
    }

    return position;
  }
}

/// Fetches delegate tasks in real-time and displays them in a [TaskSummaryCard].
class _DelegateTaskSummary extends StatelessWidget {
  final Delegate delegate;

  const _DelegateTaskSummary({required this.delegate});

  @override
  Widget build(BuildContext context) {
    // TAS-90: subscribed once per delegate scope, not on every build.
    return KeyedStreamBuilder<QuerySnapshot>(
      streamKey: (delegate.organizationUID, delegate.companyUID, delegate.uid),
      create: () => FirebaseFirestore.instance
          .collection('organizations')
          .doc(delegate.organizationUID)
          .collection('tasks')
          .where('companyId', isEqualTo: delegate.companyUID)
          .where(
            Filter.or(
              Filter('assignedTo', isEqualTo: delegate.uid),
              Filter('assignedTo', isEqualTo: 'all'),
              Filter('assignedTo', isEqualTo: 'all_branch_marketing'),
              Filter('assignedTo', isEqualTo: 'all_marketing_promotion'),
            ),
          )
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const TaskSummaryCard(tasks: [], isLoading: true);
        }
        if (snapshot.hasError) {
          return const TaskSummaryCard(tasks: []);
        }

        final tasks = snapshot.data?.docs.map((doc) {
          return TaskModel.fromFirestore(doc);
        }).toList() ?? [];

        return TaskSummaryCard(tasks: tasks);
      },
    );
  }
}
