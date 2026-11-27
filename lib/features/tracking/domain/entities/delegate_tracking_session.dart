import 'package:equatable/equatable.dart';

enum TrackingStatus {
  insideZone,
  outsideZone,
  offline,
  checkedOut,
  /// حضور مفتوح — نسيان تسجيل الانصراف / التوقيع (يظهر ضمن الحاضرين).
  forgotSignature,
  /// حساب المندوب موقوف — لا يظهر في التتبع المباشر.
  suspended,
}

class DelegateTrackingSession extends Equatable {
  final String delegateId;
  final String delegateName;
  final String delegatePhone;
  final String companyId;
  final String organizationId;
  final String branchId;
  final String branchName;
  final double branchLat;
  final double branchLng;
  final double geofenceRadius;
  final bool isTrackingEnabled;
  final TrackingStatus currentStatus;
  final double currentDistanceMeters;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime lastUpdated;
  final DateTime? lastBreachAt;
  final DateTime? firstExitedAt;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final bool isOnline;
  final bool isMockLocationDetected;
  final int offlineBreadcrumbsCount;
  final double? speed;
  final int? batteryLevel;
  final bool? isMoving;
  final String? avatarUrl;

  /// TAS-48: server verdict written by onDelegateTrackingWritten
  /// ('inside' / 'outside' / 'unknown'); null on docs it has not seen yet.
  final String? verifiedStatus;
  final double? verifiedDistanceMeters;
  final double? verifiedBranchRadius;

  /// The app's inside/outside claim disagrees with the server's distance.
  final bool statusMismatch;

  /// The written company/organization is not the delegate's membership.
  final bool scopeMismatch;

  const DelegateTrackingSession({
    required this.delegateId,
    required this.delegateName,
    required this.delegatePhone,
    required this.companyId,
    required this.organizationId,
    required this.branchId,
    required this.branchName,
    required this.branchLat,
    required this.branchLng,
    required this.geofenceRadius,
    required this.isTrackingEnabled,
    required this.currentStatus,
    required this.currentDistanceMeters,
    this.lastLatitude,
    this.lastLongitude,
    required this.lastUpdated,
    this.lastBreachAt,
    this.firstExitedAt,
    this.checkInTime,
    this.checkOutTime,
    this.isOnline = true,
    this.isMockLocationDetected = false,
    this.offlineBreadcrumbsCount = 0,
    this.speed,
    this.batteryLevel,
    this.isMoving,
    this.avatarUrl,
    this.verifiedStatus,
    this.verifiedDistanceMeters,
    this.verifiedBranchRadius,
    this.statusMismatch = false,
    this.scopeMismatch = false,
  });

  /// True when the server verdict can replace the app's geofence status.
  bool get hasServerVerdict =>
      (verifiedStatus == 'inside' || verifiedStatus == 'outside') &&
      verifiedDistanceMeters != null;

  /// TAS-48: what the supervisor/HR screens show. The app's own
  /// inside/outside (and distance) can be faked by the delegate's device, so
  /// the server verdict wins when present. Other statuses (checked out,
  /// offline, forgot signature, suspended) and docs without a verdict keep
  /// the app's values, so old data still shows.
  DelegateTrackingSession preferServerVerdict() {
    if (!hasServerVerdict) return this;
    if (currentStatus != TrackingStatus.insideZone &&
        currentStatus != TrackingStatus.outsideZone) {
      return this;
    }
    return copyWith(
      currentStatus: verifiedStatus == 'inside'
          ? TrackingStatus.insideZone
          : TrackingStatus.outsideZone,
      currentDistanceMeters: verifiedDistanceMeters,
      geofenceRadius: verifiedBranchRadius,
    );
  }

  bool get isInside =>
      currentStatus == TrackingStatus.insideZone ||
      currentStatus == TrackingStatus.forgotSignature;
  bool get isOutside => currentStatus == TrackingStatus.outsideZone;
  bool get isOffline => currentStatus == TrackingStatus.offline || !isOnline;

  /// TAS-364: no signal for this long during an open session = «التتبع واقف»
  /// (computed from the server's lastUpdated, no function needed).
  static const Duration staleAfter = Duration(minutes: 15);

  /// True when the delegate is still checked in but the phone stopped sending.
  bool isTrackingStaleAt(DateTime now) =>
      (currentStatus == TrackingStatus.insideZone ||
          currentStatus == TrackingStatus.outsideZone ||
          currentStatus == TrackingStatus.forgotSignature) &&
      now.difference(lastUpdated) > staleAfter;

  bool get isTrackingStale => isTrackingStaleAt(DateTime.now());

  bool get isSuspended => currentStatus == TrackingStatus.suspended;

  bool get isInGracePeriod {
    if (firstExitedAt == null) return false;
    final diff = DateTime.now().difference(firstExitedAt!);
    return diff.inMinutes < 3 && currentStatus == TrackingStatus.outsideZone;
  }

  int get remainingGraceSeconds {
    if (firstExitedAt == null) return 0;
    final elapsed = DateTime.now().difference(firstExitedAt!).inSeconds;
    final remaining = 180 - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  DelegateTrackingSession copyWith({
    String? delegateId,
    String? delegateName,
    String? delegatePhone,
    String? companyId,
    String? organizationId,
    String? branchId,
    String? branchName,
    double? branchLat,
    double? branchLng,
    double? geofenceRadius,
    bool? isTrackingEnabled,
    TrackingStatus? currentStatus,
    double? currentDistanceMeters,
    double? lastLatitude,
    double? lastLongitude,
    DateTime? lastUpdated,
    DateTime? lastBreachAt,
    DateTime? firstExitedAt,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    bool? isOnline,
    bool? isMockLocationDetected,
    int? offlineBreadcrumbsCount,
    double? speed,
    int? batteryLevel,
    bool? isMoving,
    String? avatarUrl,
    String? verifiedStatus,
    double? verifiedDistanceMeters,
    double? verifiedBranchRadius,
    bool? statusMismatch,
    bool? scopeMismatch,
  }) {
    return DelegateTrackingSession(
      delegateId: delegateId ?? this.delegateId,
      delegateName: delegateName ?? this.delegateName,
      delegatePhone: delegatePhone ?? this.delegatePhone,
      companyId: companyId ?? this.companyId,
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      branchLat: branchLat ?? this.branchLat,
      branchLng: branchLng ?? this.branchLng,
      geofenceRadius: geofenceRadius ?? this.geofenceRadius,
      isTrackingEnabled: isTrackingEnabled ?? this.isTrackingEnabled,
      currentStatus: currentStatus ?? this.currentStatus,
      currentDistanceMeters: currentDistanceMeters ?? this.currentDistanceMeters,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastBreachAt: lastBreachAt ?? this.lastBreachAt,
      firstExitedAt: firstExitedAt ?? this.firstExitedAt,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      isOnline: isOnline ?? this.isOnline,
      isMockLocationDetected:
          isMockLocationDetected ?? this.isMockLocationDetected,
      offlineBreadcrumbsCount:
          offlineBreadcrumbsCount ?? this.offlineBreadcrumbsCount,
      speed: speed ?? this.speed,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isMoving: isMoving ?? this.isMoving,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      verifiedStatus: verifiedStatus ?? this.verifiedStatus,
      verifiedDistanceMeters:
          verifiedDistanceMeters ?? this.verifiedDistanceMeters,
      verifiedBranchRadius: verifiedBranchRadius ?? this.verifiedBranchRadius,
      statusMismatch: statusMismatch ?? this.statusMismatch,
      scopeMismatch: scopeMismatch ?? this.scopeMismatch,
    );
  }

  @override
  List<Object?> get props => [
        delegateId,
        delegateName,
        delegatePhone,
        companyId,
        organizationId,
        branchId,
        branchName,
        branchLat,
        branchLng,
        geofenceRadius,
        isTrackingEnabled,
        currentStatus,
        currentDistanceMeters,
        lastLatitude,
        lastLongitude,
        lastUpdated,
        lastBreachAt,
        firstExitedAt,
        checkInTime,
        checkOutTime,
        isOnline,
        isMockLocationDetected,
        offlineBreadcrumbsCount,
        speed,
        batteryLevel,
        isMoving,
        avatarUrl,
        verifiedStatus,
        verifiedDistanceMeters,
        verifiedBranchRadius,
        statusMismatch,
        scopeMismatch,
      ];
}
