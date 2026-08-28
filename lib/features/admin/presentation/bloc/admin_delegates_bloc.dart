import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDelegatesBloc
    extends Bloc<AdminDelegatesEvent, AdminDelegatesState> {
  final GetCompanyDelegates getCompanyDelegates;
  static final Map<String, List<Delegate>> _delegatesCache = {};
  static final Map<String, DateTime> _delegatesCacheTime = {};

  static void clearCache() {
    _delegatesCache.clear();
    _delegatesCacheTime.clear();
  }

  AdminDelegatesBloc({required this.getCompanyDelegates})
    : super(AdminDelegatesInitial()) {
    on<LoadCompanyDelegates>(_onLoadCompanyDelegates);
  }

  Future<void> _onLoadCompanyDelegates(
    LoadCompanyDelegates event,
    Emitter<AdminDelegatesState> emit,
  ) async {
    final cacheKey = '${event.organizationUID}_${event.companyUID}';
    final cached = _delegatesCache[cacheKey];

    // If cached data is available, emit loaded state immediately for 0ms loading
    if (cached != null) {
      emit(AdminDelegatesLoaded(delegates: cached));
    } else {
      emit(AdminDelegatesLoading());
    }

    final result = await getCompanyDelegates(
      GetCompanyDelegatesParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );

    result.fold(
      (failure) {
        if (cached == null) {
          emit(AdminDelegatesError(message: failure.message));
        }
      },
      (delegates) {
        _delegatesCache[cacheKey] = delegates;
        _delegatesCacheTime[cacheKey] = DateTime.now();
        emit(AdminDelegatesLoaded(delegates: delegates));
      },
    );
  }
}
