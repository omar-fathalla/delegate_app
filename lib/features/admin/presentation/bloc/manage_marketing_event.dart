part of 'manage_marketing_bloc.dart';

abstract class ManageMarketingEvent extends Equatable {
  const ManageMarketingEvent();

  @override
  List<Object?> get props => [];
}

class LoadMarketingEmployeesRequested extends ManageMarketingEvent {}

class DeleteMarketingEmployeeRequested extends ManageMarketingEvent {
  final String employeeId;
  const DeleteMarketingEmployeeRequested({required this.employeeId});

  @override
  List<Object?> get props => [employeeId];
}

class SuspendMarketingEmployeeRequested extends ManageMarketingEvent {
  final String employeeId;
  final bool suspend;
  const SuspendMarketingEmployeeRequested({
    required this.employeeId,
    required this.suspend,
  });

  @override
  List<Object?> get props => [employeeId, suspend];
}

class UpdateMarketingEmployeeRequested extends ManageMarketingEvent {
  final AdminUser employee;
  const UpdateMarketingEmployeeRequested({required this.employee});

  @override
  List<Object?> get props => [employee];
}
