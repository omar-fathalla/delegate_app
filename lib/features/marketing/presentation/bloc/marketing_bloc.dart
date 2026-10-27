import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';

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

  // ─── Per-Branch Attendance Cache (Cache-First / Incremental) ────────────────
  // Key: "${organizationId}_${branchName}_${date.year}_${date.month}_${date.day}"
  static final Map<String, List<Map<String, dynamic>>> _perBranchAttendanceCache = {};
  static void clearCache() {
    _perBranchAttendanceCache.clear();
    DelegateProfileCache.clearSession();
  }

  Future<void> _onLoadAllFavoriteBranchesAttendance(
    LoadAllFavoriteBranchesAttendance event,
    Emitter<MarketingState> emit,
  ) async {
    if (event.favoriteBranches.isEmpty) {
      emit(const AllBranchesAttendanceLoaded(
        data: {},
        favoriteBranches: [],
        loadingBranches: {},
      ));
      return;
    }

    final date = event.date ?? DateTime.now();
    final dateSuffix = '${date.year}_${date.month}_${date.day}';

    // 1. Gather all currently cached branch data
    final Map<String, List<Map<String, dynamic>>> branchData = {};
    final List<String> branchesToFetch = [];

    // If current state already has loaded data, reuse it as immediate baseline
    if (state is AllBranchesAttendanceLoaded) {
      final currentState = state as AllBranchesAttendanceLoaded;
      for (final b in event.favoriteBranches) {
        if (currentState.data.containsKey(b)) {
          branchData[b] = currentState.data[b]!;
        }
      }
    }

    // Check persistent in-memory per-branch cache
    for (final branch in event.favoriteBranches) {
      final key = '${event.organizationId}_${branch}_$dateSuffix';
      if (_perBranchAttendanceCache.containsKey(key)) {
        branchData[branch] = _perBranchAttendanceCache[key]!;
      } else if (!branchData.containsKey(branch)) {
        branchesToFetch.add(branch);
      }
    }

    // If this is a forced refresh, re-fetch all requested branches
    if (event.forceRefresh) {
      branchesToFetch.clear();
      branchesToFetch.addAll(event.favoriteBranches);
    }

    // If we have some data ready right now (e.g. cached branches):
    if (branchData.isNotEmpty) {
      // 0ms instant render of cached branches!
      emit(AllBranchesAttendanceLoaded(
        data: Map.from(branchData),
        favoriteBranches: event.favoriteBranches,
        loadingBranches: Set.from(branchesToFetch),
      ));
    } else {
      // No data cached at all for any branch -> show initial loading skeletons
      emit(AllBranchesAttendanceLoading());
    }

    // Stale-While-Revalidate (SWR):
    // Even if all branches were present in local cache, we revalidate from the live server
    // in the background to ensure any newly added attendance/check-outs are delivered with 100% integrity.
    final branchesToQuery = branchesToFetch.isNotEmpty
        ? branchesToFetch
        : event.favoriteBranches;

    try {
      final fetchedData = await remoteDataSource.getTodayAttendanceForBranches(
        branchNames: branchesToQuery,
        organizationId: event.organizationId,
        date: date,
        onFirstPaint: (partial) {
          // First paint: logs (+ local profile caches). May still be enriching.
          for (final entry in partial.entries) {
            final key = '${event.organizationId}_${entry.key}_$dateSuffix';
            _perBranchAttendanceCache[key] = entry.value;
            branchData[entry.key] = entry.value;
          }
          for (final b in event.favoriteBranches) {
            branchData.putIfAbsent(b, () => []);
          }
          if (!isClosed) {
            emit(AllBranchesAttendanceLoaded(
              data: Map.from(branchData),
              favoriteBranches: event.favoriteBranches,
              loadingBranches: const {},
              isEnriching: true,
            ));
          }
        },
      );

      // Save fully enriched result to per-branch cache & merge
      for (final entry in fetchedData.entries) {
        final key = '${event.organizationId}_${entry.key}_$dateSuffix';
        _perBranchAttendanceCache[key] = entry.value;
        branchData[entry.key] = entry.value;
      }

      // Ensure every favorite branch has an entry in branchData
      for (final b in event.favoriteBranches) {
        branchData.putIfAbsent(b, () => []);
      }

      emit(AllBranchesAttendanceLoaded(
        data: Map.from(branchData),
        favoriteBranches: event.favoriteBranches,
        loadingBranches: const {},
        isEnriching: false,
      ));
    } catch (e) {
      // If we already showed cached data, keep it! Do not break the UI with error screen.
      if (branchData.isNotEmpty) {
        emit(AllBranchesAttendanceLoaded(
          data: Map.from(branchData),
          favoriteBranches: event.favoriteBranches,
          loadingBranches: const {},
          isEnriching: false,
        ));
      } else {
        emit(AllBranchesAttendanceError(
          message: 'فشل في جلب بيانات الفروع: ${e.toString()}',
        ));
      }
    }
  }
}

