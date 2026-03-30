import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDashboardBloc
    extends Bloc<AdminDashboardEvent, AdminDashboardState> {
  final GetDashboardSummary getDashboardSummary;

  AdminDashboardBloc({required this.getDashboardSummary})
    : super(AdminDashboardInitial()) {
    on<LoadDashboard>(_onLoadDashboard);
  }

  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<AdminDashboardState> emit,
  ) async {
    emit(AdminDashboardLoading());
    final result = await getDashboardSummary(
      GetDashboardSummaryParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );

    result.fold(
      (failure) => emit(AdminDashboardError(message: failure.message)),
      (summary) => emit(AdminDashboardLoaded(summary: summary)),
    );
  }
}
