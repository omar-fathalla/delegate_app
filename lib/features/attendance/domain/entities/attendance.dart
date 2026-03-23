import 'package:equatable/equatable.dart';

class Attendance extends Equatable {
  final String id;
  final String userId;
  final String organizationId; // معرّف المنظمة - لعزل البيانات لكل منظمة
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? branchName;
  final bool isSynced;
  final DateTime? localCheckInTime;
  final DateTime? localCheckOutTime;

  const Attendance({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.checkInTime,
    this.checkOutTime,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.branchName,
    this.isSynced = true,
    this.localCheckInTime,
    this.localCheckOutTime,
  });

  @override
  List<Object?> get props => [
    id,
    userId,
    organizationId,
    checkInTime,
    checkOutTime,
    latitude,
    longitude,
    imageUrl,
    branchName,
    isSynced,
    localCheckInTime,
    localCheckOutTime,
  ];
}
