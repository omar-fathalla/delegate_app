part of 'attendance_bloc.dart';

abstract class AttendanceEvent extends Equatable {
  const AttendanceEvent();

  @override
  List<Object?> get props => [];
}

class CheckInRequested extends AttendanceEvent {
  final String userId;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final double lat;
  final double long;
  final String? branchName;
  final String? branchId;
  final String? branchOrganizationUID;
  final String? delegateName;
  final String? phoneNumber;
  final String? companyName;
  final String? personalPhotoURL;
  final Map<String, dynamic>? qrProof;

  const CheckInRequested({
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
    this.branchId,
    this.branchOrganizationUID,
    this.delegateName,
    this.phoneNumber,
    this.companyName,
    this.personalPhotoURL,
    this.qrProof,
  });

  @override
  List<Object?> get props => [
    userId,
    companyId,
    organizationId,
    deviceInfo,
    lat,
    long,
    branchName,
    branchId,
    branchOrganizationUID,
    delegateName,
    phoneNumber,
    companyName,
    personalPhotoURL,
    qrProof,
  ];
}

class CheckOutRequested extends AttendanceEvent {
  final String attendanceId;
  final String userId;
  final String organizationId;
  final double lat;
  final double long;

  const CheckOutRequested({
    required this.attendanceId,
    required this.userId,
    required this.organizationId,
    required this.lat,
    required this.long,
  });

  @override
  List<Object> get props => [attendanceId, userId, organizationId, lat, long];
}

class HistoryRequested extends AttendanceEvent {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;

  const HistoryRequested({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [
    userId,
    organizationId,
    nationalityID,
    phoneNumber,
  ];
}

class LoadMoreHistoryRequested extends AttendanceEvent {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;

  const LoadMoreHistoryRequested({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [
    userId,
    organizationId,
    nationalityID,
    phoneNumber,
  ];
}

/// TAS-363: send what [userId] saved on the phone without network. With
/// [reloadHistory] the history is read again afterwards (network back).
class SyncRequested extends AttendanceEvent {
  const SyncRequested({
    this.userId = '',
    this.reloadHistory = false,
    this.nationalityID,
    this.phoneNumber,
  });

  final String userId;
  final bool reloadHistory;
  final String? nationalityID;
  final String? phoneNumber;

  @override
  List<Object?> get props => [
    userId,
    reloadHistory,
    nationalityID,
    phoneNumber,
  ];
}

class CheckOutAndCheckInRequested extends AttendanceEvent {
  final String oldAttendanceId;
  final String userId;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final double lat;
  final double long;
  final String? branchName;
  final String? branchId;
  final String? branchOrganizationUID;
  final String? delegateName;
  final String? phoneNumber;
  final String? companyName;
  final String? personalPhotoURL;
  final Map<String, dynamic>? qrProof;

  const CheckOutAndCheckInRequested({
    required this.oldAttendanceId,
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
    this.branchId,
    this.branchOrganizationUID,
    this.delegateName,
    this.phoneNumber,
    this.companyName,
    this.personalPhotoURL,
    this.qrProof,
  });

  @override
  List<Object?> get props => [
    oldAttendanceId,
    userId,
    companyId,
    organizationId,
    deviceInfo,
    lat,
    long,
    branchName,
    branchId,
    branchOrganizationUID,
    delegateName,
    phoneNumber,
    companyName,
    personalPhotoURL,
    qrProof,
  ];
}
