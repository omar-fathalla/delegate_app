import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDelegatesBloc
    extends Bloc<AdminDelegatesEvent, AdminDelegatesState> {
  final GetCompanyDelegates getCompanyDelegates;

  AdminDelegatesBloc({required this.getCompanyDelegates})
    : super(AdminDelegatesInitial()) {
    on<LoadCompanyDelegates>(_onLoadCompanyDelegates);
  }

  Future<void> _onLoadCompanyDelegates(
    LoadCompanyDelegates event,
    Emitter<AdminDelegatesState> emit,
  ) async {
    emit(AdminDelegatesLoading());
    final result = await getCompanyDelegates(
      GetCompanyDelegatesParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );

    result.fold(
      (failure) => emit(AdminDelegatesError(message: failure.message)),
      (delegates) => emit(AdminDelegatesLoaded(delegates: delegates)),
    );
  }
}
