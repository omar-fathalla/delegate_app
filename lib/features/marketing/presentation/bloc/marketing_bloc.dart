import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';

part 'marketing_event.dart';
part 'marketing_state.dart';

class MarketingBloc extends Bloc<MarketingEvent, MarketingState> {
  final GetMarketingCompanies getCompanies;
  final GetMarketingDelegates getDelegates;
  final MarketingRemoteDataSource remoteDataSource;
  final BranchPreferenceService branchPreferenceService;

  List<Delegate> _allDelegates = [];

  // Pagination state
  List<Map<String, dynamic>> _allCompanies = [];
  DocumentSnapshot? _lastCompanyDocument;
  bool _hasMoreCompanies = true;
  bool _isLoadingMore = false;

  MarketingBloc({
    required this.getCompanies,
    required this.getDelegates,
    required this.remoteDataSource,
    required this.branchPreferenceService,
  }) : super(MarketingInitial()) {
    on<LoadCompanies>(_onLoadCompanies);
    on<LoadCompaniesPaginated>(_onLoadCompaniesPaginated);
    on<LoadDelegates>(_onLoadDelegates);
    on<SearchDelegates>(_onSearchDelegates);
    // Branch events
    on<LoadBranches>(_onLoadBranches);
    on<LoadTodayAttendanceByBranch>(_onLoadTodayAttendanceByBranch);
    on<LoadBranchPreferences>(_onLoadBranchPreferences);
    on<AddFavoriteBranch>(_onAddFavoriteBranch);
    on<RemoveFavoriteBranch>(_onRemoveFavoriteBranch);
    on<SetActiveBranch>(_onSetActiveBranch);
    on<LoadAllFavoriteBranchesAttendance>(_onLoadAllFavoriteBranchesAttendance);
  }

  Future<void> _onLoadCompanies(
    LoadCompanies event,
    Emitter<MarketingState> emit,
  ) async {
    emit(CompaniesLoading());
    final result = await getCompanies(event.organizationUID);
    result.fold(
      (failure) => emit(CompaniesError(message: failure.message)),
      (companies) => emit(CompaniesLoaded(companies: companies)),
    );
  }

  Future<void> _onLoadCompaniesPaginated(
    LoadCompaniesPaginated event,
    Emitter<MarketingState> emit,
  ) async {
    // If it's initial load, reset everything
    if (event.isInitialLoad) {
      _allCompanies = [];
      _lastCompanyDocument = null;
      _hasMoreCompanies = true;
      _isLoadingMore = false;
      emit(CompaniesLoading());
    } else {
      // If already loading more, ignore
      if (_isLoadingMore) {
        return;
      }

      // If no more companies, ignore
      if (!_hasMoreCompanies) {
        return;
      }

      // Set loading more flag
      _isLoadingMore = true;

      // Emit loading more state
      if (state is CompaniesLoaded) {
        emit((state as CompaniesLoaded).copyWith(isLoadingMore: true));
      }
    }

    try {
      // Fetch paginated companies
      final result = await remoteDataSource.getCompaniesPaginated(
        event.organizationUID,
        lastDocument: _lastCompanyDocument,
        limit: 20,
      );

      final newCompanies = result['companies'] as List<Map<String, dynamic>>;
      final hasMore = result['hasMore'] as bool;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;

      // Update pagination state
      _allCompanies.addAll(newCompanies);
      _lastCompanyDocument = lastDoc;
      _hasMoreCompanies = hasMore;
      _isLoadingMore = false;

      // Emit loaded state
      emit(
        CompaniesLoaded(
          companies: _allCompanies,
          hasMore: _hasMoreCompanies,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      _isLoadingMore = false;
      emit(CompaniesError(message: 'فشل في جلب الشركات: ${e.toString()}'));
    }
  }

  Future<void> _onLoadDelegates(
    LoadDelegates event,
    Emitter<MarketingState> emit,
  ) async {
    emit(DelegatesLoading());
    final result = await getDelegates(
      GetMarketingDelegatesParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );
    result.fold((failure) => emit(DelegatesError(message: failure.message)), (
      delegates,
    ) {
      _allDelegates = delegates;
      emit(DelegatesLoaded(delegates: delegates));
    });
  }

  Future<void> _onSearchDelegates(
    SearchDelegates event,
    Emitter<MarketingState> emit,
  ) async {
    emit(DelegatesLoading());

    // If we haven't loaded delegates yet, load them first
    if (_allDelegates.isEmpty) {
      final result = await getDelegates(
        GetMarketingDelegatesParams(organizationUID: event.organizationUID),
      );
      if (result.isLeft()) {
        final failure = result.fold((l) => l, (r) => null)!;
        emit(DelegatesError(message: failure.message));
        return;
      }
      _allDelegates = result.fold((l) => [], (r) => r);
    }

    final query = event.query.toLowerCase().trim();
    final statusFilter = event.statusFilter;
    final positionFilter = event.positionFilter;

    final filteredDelegates = _allDelegates.where((delegate) {
      final matchesQuery =
          query.isEmpty ||
          delegate.fullName.toLowerCase().contains(query) ||
          delegate.phoneNumber.contains(query) ||
          delegate.delegatePublicId.contains(query);

      final matchesStatus =
          statusFilter == null ||
          statusFilter.isEmpty ||
          delegate.status.name == statusFilter;
      final matchesPosition =
          positionFilter == null ||
          positionFilter.isEmpty ||
          delegate.position.name == positionFilter;

      return matchesQuery && matchesStatus && matchesPosition;
    }).toList();

    emit(DelegatesLoaded(delegates: filteredDelegates));
  }

  // ─── Branch Handlers ───────────────────────────────────────────────────────

  Future<void> _onLoadBranches(
    LoadBranches event,
    Emitter<MarketingState> emit,
  ) async {
    emit(BranchesLoading());
    try {
      final branches = await remoteDataSource.getBranches();
      emit(BranchesLoaded(branches: branches));
    } catch (e) {
      emit(BranchesError(message: 'فشل في جلب الفروع: ${e.toString()}'));
    }
  }

  Future<void> _onLoadTodayAttendanceByBranch(
    LoadTodayAttendanceByBranch event,
    Emitter<MarketingState> emit,
  ) async {
    emit(TodayAttendanceLoading());
    try {
      final records = await remoteDataSource.getTodayAttendanceByBranch(
        branchName: event.branchName,
        organizationId: event.organizationId,
      );
      emit(TodayAttendanceLoaded(
        records: records,
        branchName: event.branchName,
      ));
    } catch (e) {
      emit(TodayAttendanceError(
        message: 'فشل في جلب بيانات الحضور: ${e.toString()}',
      ));
    }
  }

  Future<void> _onLoadBranchPreferences(
    LoadBranchPreferences event,
    Emitter<MarketingState> emit,
  ) async {
    final favorites = branchPreferenceService.getFavoriteBranches(event.userId);
    final active = branchPreferenceService.getActiveBranch(event.userId);
    emit(BranchPreferencesLoaded(
      favoriteBranches: favorites,
      activeBranch: active,
    ));
  }

  Future<void> _onAddFavoriteBranch(
    AddFavoriteBranch event,
    Emitter<MarketingState> emit,
  ) async {
    await branchPreferenceService.addFavoriteBranch(
      event.userId,
      event.branchName,
    );
    final favorites = branchPreferenceService.getFavoriteBranches(event.userId);
    final active = branchPreferenceService.getActiveBranch(event.userId);
    emit(BranchPreferencesLoaded(
      favoriteBranches: favorites,
      activeBranch: active,
    ));
  }

  Future<void> _onRemoveFavoriteBranch(
    RemoveFavoriteBranch event,
    Emitter<MarketingState> emit,
  ) async {
    await branchPreferenceService.removeFavoriteBranch(
      event.userId,
      event.branchName,
    );
    final favorites = branchPreferenceService.getFavoriteBranches(event.userId);
    final active = branchPreferenceService.getActiveBranch(event.userId);
    emit(BranchPreferencesLoaded(
      favoriteBranches: favorites,
      activeBranch: active,
    ));
  }

  Future<void> _onSetActiveBranch(
    SetActiveBranch event,
    Emitter<MarketingState> emit,
  ) async {
    await branchPreferenceService.setActiveBranch(
      event.userId,
      event.branchName,
    );
    final favorites = branchPreferenceService.getFavoriteBranches(event.userId);
    emit(BranchPreferencesLoaded(
      favoriteBranches: favorites,
      activeBranch: event.branchName,
    ));
  }

  // ─── Load ALL favorite branches attendance at once ──────────────────────────

  Future<void> _onLoadAllFavoriteBranchesAttendance(
    LoadAllFavoriteBranchesAttendance event,
    Emitter<MarketingState> emit,
  ) async {
    if (event.favoriteBranches.isEmpty) {
      emit(AllBranchesAttendanceLoaded(
        data: {},
        favoriteBranches: [],
      ));
      return;
    }

    emit(AllBranchesAttendanceLoading());

    try {
      // جلب بيانات كل الفروع بالتوازي
      final futures = event.favoriteBranches.map(
        (branch) => remoteDataSource.getTodayAttendanceByBranch(
          branchName: branch,
          organizationId: event.organizationId,
        ),
      );

      final results = await Future.wait(futures);

      final Map<String, List<Map<String, dynamic>>> data = {};
      for (var i = 0; i < event.favoriteBranches.length; i++) {
        data[event.favoriteBranches[i]] = results[i];
      }

      emit(AllBranchesAttendanceLoaded(
        data: data,
        favoriteBranches: event.favoriteBranches,
      ));
    } catch (e) {
      emit(AllBranchesAttendanceError(
        message: 'فشل في جلب بيانات الفروع: ${e.toString()}',
      ));
    }
  }
}

