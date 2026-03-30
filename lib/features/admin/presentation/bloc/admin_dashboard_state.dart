import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:equatable/equatable.dart';

abstract class AdminDashboardState extends Equatable {
  const AdminDashboardState();

  @override
  List<Object?> get props => [];
}

class AdminDashboardInitial extends AdminDashboardState {}

class AdminDashboardLoading extends AdminDashboardState {}

class AdminDashboardLoaded extends AdminDashboardState {
  final DashboardSummary summary;

  const AdminDashboardLoaded({required this.summary});

  @override
  List<Object?> get props => [summary];
}

class AdminDashboardError extends AdminDashboardState {
  final String message;

  const AdminDashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}
