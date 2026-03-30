import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_admins.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/suspend_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_admin_user.dart';

part 'manage_admins_event.dart';
part 'manage_admins_state.dart';

class ManageAdminsBloc extends Bloc<ManageAdminsEvent, ManageAdminsState> {
  final GetAdmins getAdmins;
  final DeleteAdminUser deleteAdminUser;
  final SuspendAdminUser suspendAdminUser;
  final UpdateAdminUser updateAdminUser;

  ManageAdminsBloc({
    required this.getAdmins,
    required this.deleteAdminUser,
    required this.suspendAdminUser,
    required this.updateAdminUser,
  }) : super(ManageAdminsInitial()) {
    on<LoadAdminsRequested>(_onLoad);
    on<DeleteAdminRequested>(_onDelete);
    on<SuspendAdminRequested>(_onSuspend);
    on<UpdateAdminRequested>(_onUpdate);
  }

  Future<void> _onLoad(
    LoadAdminsRequested event,
    Emitter<ManageAdminsState> emit,
  ) async {
    emit(ManageAdminsLoading());
    final result = await getAdmins(NoParams());
    result.fold(
      (failure) => emit(ManageAdminsError(message: failure.message)),
      (admins) => emit(ManageAdminsLoaded(admins: admins)),
    );
  }

  Future<void> _onDelete(
    DeleteAdminRequested event,
    Emitter<ManageAdminsState> emit,
  ) async {
    emit(ManageAdminsLoading());
    final result = await deleteAdminUser(
      DeleteAdminUserParams(adminId: event.adminId),
    );
    result.fold(
      (failure) => emit(ManageAdminsError(message: failure.message)),
      (_) => add(LoadAdminsRequested()),
    );
  }

  Future<void> _onSuspend(
    SuspendAdminRequested event,
    Emitter<ManageAdminsState> emit,
  ) async {
    emit(ManageAdminsLoading());
    final result = await suspendAdminUser(
      SuspendAdminUserParams(adminId: event.adminId, suspend: event.suspend),
    );
    result.fold(
      (failure) => emit(ManageAdminsError(message: failure.message)),
      (_) => add(LoadAdminsRequested()),
    );
  }

  Future<void> _onUpdate(
    UpdateAdminRequested event,
    Emitter<ManageAdminsState> emit,
  ) async {
    emit(ManageAdminsLoading());
    final result = await updateAdminUser(
      UpdateAdminUserParams(admin: event.admin),
    );
    result.fold(
      (failure) => emit(ManageAdminsError(message: failure.message)),
      (_) => add(LoadAdminsRequested()),
    );
  }
}
