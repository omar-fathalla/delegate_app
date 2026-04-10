import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';

part 'marketing_event.dart';
part 'marketing_state.dart';

class MarketingBloc extends Bloc<MarketingEvent, MarketingState> {
  final GetMarketingCompanies getCompanies;
  final GetMarketingDelegates getDelegates;
  final MarketingRemoteDataSource remoteDataSource;

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
  }) : super(MarketingInitial()) {
    on<LoadCompanies>(_onLoadCompanies);
    on<LoadCompaniesPaginated>(_onLoadCompaniesPaginated);
    on<LoadDelegates>(_onLoadDelegates);
    on<SearchDelegates>(_onSearchDelegates);
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
}
