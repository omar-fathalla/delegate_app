import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_marketing_employees.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

part 'manage_marketing_event.dart';
part 'manage_marketing_state.dart';

class ManageMarketingBloc
    extends Bloc<ManageMarketingEvent, ManageMarketingState> {
  final GetMarketingEmployees getMarketingEmployees;
  MarketingEmployeesScope _scope = const MarketingEmployeesScope();
  final AdminRepository adminRepository;

  ManageMarketingBloc({
    required this.getMarketingEmployees,
    required this.adminRepository,
  }) : super(ManageMarketingInitial()) {
    on<LoadMarketingEmployeesRequested>(_onLoad);
    on<DeleteMarketingEmployeeRequested>(_onDelete);
    on<SuspendMarketingEmployeeRequested>(_onSuspend);
    on<UpdateMarketingEmployeeRequested>(_onUpdate);
  }

  Future<void> _onLoad(
    LoadMarketingEmployeesRequested event,
    Emitter<ManageMarketingState> emit,
  ) async {
    emit(ManageMarketingLoading());
    _scope = event.scope ?? _scope;
    final result = await getMarketingEmployees(_scope);
    result.fold(
      (failure) => emit(ManageMarketingError(message: failure.message)),
      (employees) => emit(ManageMarketingLoaded(employees: employees)),
    );
  }

  Future<void> _onDelete(
    DeleteMarketingEmployeeRequested event,
    Emitter<ManageMarketingState> emit,
  ) async {
    emit(ManageMarketingLoading());
    final result = await adminRepository.deleteMarketingEmployee(
      event.employeeId,
    );
    result.fold(
      (failure) => emit(ManageMarketingError(message: failure.message)),
      (_) => add(const LoadMarketingEmployeesRequested()),
    );
  }

  Future<void> _onSuspend(
    SuspendMarketingEmployeeRequested event,
    Emitter<ManageMarketingState> emit,
  ) async {
    emit(ManageMarketingLoading());
    final result = await adminRepository.suspendMarketingEmployee(
      event.employeeId,
      event.suspend,
    );
    result.fold(
      (failure) => emit(ManageMarketingError(message: failure.message)),
      (_) => add(const LoadMarketingEmployeesRequested()),
    );
  }

  Future<void> _onUpdate(
    UpdateMarketingEmployeeRequested event,
    Emitter<ManageMarketingState> emit,
  ) async {
    emit(ManageMarketingLoading());
    final result = await adminRepository.updateMarketingEmployee(
      event.employee,
    );
    result.fold(
      (failure) => emit(ManageMarketingError(message: failure.message)),
      (_) => add(const LoadMarketingEmployeesRequested()),
    );
  }
}
