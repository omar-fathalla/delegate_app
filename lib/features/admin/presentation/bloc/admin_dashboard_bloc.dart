import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDashboardBloc
    extends Bloc<AdminDashboardEvent, AdminDashboardState> {
  final GetDashboardSummary getDashboardSummary;
  static final Map<String, DashboardSummary> _summaryCache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static void clearCache() {
    _summaryCache.clear();
    _cacheTime.clear();
  }

  AdminDashboardBloc({required this.getDashboardSummary})
    : super(AdminDashboardInitial()) {
    on<LoadDashboard>(_onLoadDashboard);
  }

  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<AdminDashboardState> emit,
  ) async {
    final cacheKey = '${event.organizationUID}_${event.companyUID}';
    final cached = _summaryCache[cacheKey];

    // If cached data exists, emit it immediately for instant 0ms rendering
    if (cached != null) {
      emit(AdminDashboardLoaded(summary: cached));
    } else {
      emit(AdminDashboardLoading());
    }

    final result = await getDashboardSummary(
      GetDashboardSummaryParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );

    result.fold(
      (failure) {
        if (cached == null) {
          emit(AdminDashboardError(message: failure.message));
        }
      },
      (summary) {
        _summaryCache[cacheKey] = summary;
        _cacheTime[cacheKey] = DateTime.now();
        emit(AdminDashboardLoaded(summary: summary));
      },
    );
  }
}
