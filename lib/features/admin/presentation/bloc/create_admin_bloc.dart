import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';

part 'create_admin_event.dart';
part 'create_admin_state.dart';

class CreateAdminBloc extends Bloc<CreateAdminEvent, CreateAdminState> {
  final CreateAdmin createAdmin;

  CreateAdminBloc({required this.createAdmin}) : super(CreateAdminInitial()) {
    on<CreateAdminSubmitted>(_onSubmitted);
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
      ),
    );
    result.fold(
      (failure) => emit(CreateAdminError(message: failure.message)),
      (adminUser) => emit(CreateAdminSuccess(adminUser: adminUser)),
    );
  }
}
