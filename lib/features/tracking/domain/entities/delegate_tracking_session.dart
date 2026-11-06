import 'package:equatable/equatable.dart';

enum TrackingStatus {
  insideZone,
  outsideZone,
  offline,
  checkedOut,
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
  });

  bool get isInside => currentStatus == TrackingStatus.insideZone;
  bool get isOutside => currentStatus == TrackingStatus.outsideZone;
  bool get isOffline => currentStatus == TrackingStatus.offline || !isOnline;

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
      ];
}
