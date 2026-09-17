import 'package:equatable/equatable.dart';

class Branch extends Equatable {
  final String id;
  final String branchName;
  final double latitude;
  final double longitude;
  final double geofenceRadius;
  final String? organizationUID;
  final String? organizationName;

  const Branch({
    required this.id,
    required this.branchName,
    required this.latitude,
    required this.longitude,
    required this.geofenceRadius,
    this.organizationUID,
    this.organizationName,
  });

  @override
  List<Object?> get props => [
    id,
    branchName,
    latitude,
    longitude,
    geofenceRadius,
    organizationUID,
    organizationName,
  ];
}
