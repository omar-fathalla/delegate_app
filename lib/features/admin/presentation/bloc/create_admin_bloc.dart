import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';
import 'package:delegate_app/core/usecases/usecase.dart';

part 'create_admin_event.dart';
part 'create_admin_state.dart';

class CreateAdminBloc extends Bloc<CreateAdminEvent, CreateAdminState> {
  final CreateAdmin createAdmin;
  final GetOrganizations getOrganizations;

  CreateAdminBloc({required this.createAdmin, required this.getOrganizations})
    : super(CreateAdminInitial()) {
    on<LoadOrganizationsRequested>(_onLoadOrgs);
    on<CreateAdminSubmitted>(_onSubmitted);
  }

  Future<void> _onLoadOrgs(
    LoadOrganizationsRequested event,
    Emitter<CreateAdminState> emit,
  ) async {
    final result = await getOrganizations(NoParams());
    result.fold(
      (_) => emit(const CreateAdminOrgsLoaded(organizations: [])),
      (orgs) => emit(CreateAdminOrgsLoaded(organizations: orgs)),
    );
  }

  Future<void> _onSubmitted(
    CreateAdminSubmitted event,
    Emitter<CreateAdminState> emit,
  ) async {
    emit(CreateAdminLoading());
    final result = await createAdmin(
      CreateAdminParams(
        phoneNumber: event.phoneNumber,
        email: event.email,
        displayName: event.displayName,
        role: event.role,
        organizationUID: event.organizationUID,
      ),
    );
    result.fold(
      (failure) => emit(CreateAdminError(message: failure.message)),
      (adminUser) => emit(CreateAdminSuccess(adminUser: adminUser)),
    );
  }
}
