import 'package:equatable/equatable.dart';

class Attendance extends Equatable {
  final String id;
  final String userId;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? branchName;

  const Attendance({
    required this.id,
    required this.userId,
    required this.checkInTime,
    this.checkOutTime,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.branchName,
  });

  @override
  List<Object?> get props => [
    id,
    userId,
    checkInTime,
    checkOutTime,
    latitude,
    longitude,
    imageUrl,
    branchName,
  ];
}
