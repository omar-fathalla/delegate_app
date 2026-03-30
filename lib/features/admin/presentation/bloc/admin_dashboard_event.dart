import 'package:equatable/equatable.dart';

abstract class AdminDashboardEvent extends Equatable {
  const AdminDashboardEvent();

  @override
  List<Object?> get props => [];
}

class LoadDashboard extends AdminDashboardEvent {
  final String organizationUID;
  final String companyUID;

  const LoadDashboard({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID];
}
