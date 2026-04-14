import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/search_companies_by_code.dart';
import 'company_search_event.dart';
import 'company_search_state.dart';

/// BLoC for company search with infinite scroll pagination
class CompanySearchBloc extends Bloc<CompanySearchEvent, CompanySearchState> {
  final SearchCompaniesByCode searchCompaniesByCode;

  // Current search parameters
  String? _currentOrganizationUID;
  String? _currentSearchQuery;

  CompanySearchBloc({required this.searchCompaniesByCode})
    : super(const CompanySearchInitial()) {
    on<SearchCompaniesRequested>(_onSearchCompaniesRequested);
    on<LoadMoreCompaniesRequested>(_onLoadMoreCompaniesRequested);
    on<ClearSearchRequested>(_onClearSearchRequested);
    on<RefreshSearchRequested>(_onRefreshSearchRequested);
  }

  /// Handle search companies request
  Future<void> _onSearchCompaniesRequested(
    SearchCompaniesRequested event,
    Emitter<CompanySearchState> emit,
  ) async {
    // Store current search parameters
    _currentOrganizationUID = event.organizationUID;
    _currentSearchQuery = event.companyCode;

    emit(const CompanySearchLoading());

    final result = await searchCompaniesByCode(
      SearchCompaniesByCodeParams(
        organizationUID: event.organizationUID,
        companyCode: event.companyCode,
        limit: 20,
      ),
    );

    result.fold(
      (failure) => emit(CompanySearchError(message: failure.message)),
      (paginationResponse) {
        if (paginationResponse.items.isEmpty) {
          emit(CompanySearchEmpty(searchQuery: event.companyCode));
        } else {
          emit(
            CompanySearchSuccess(
              companies: paginationResponse.items,
              hasReachedMax: paginationResponse.hasReachedMax,
              lastDocument: paginationResponse.lastDoc,
              currentSearchQuery: event.companyCode,
            ),
          );
        }
      },
    );
  }

  /// Handle load more companies request (pagination)
  Future<void> _onLoadMoreCompaniesRequested(
    LoadMoreCompaniesRequested event,
    Emitter<CompanySearchState> emit,
  ) async {
    final currentState = state;

    // Only proceed if we have a success state and haven't reached max
    if (currentState is! CompanySearchSuccess ||
        currentState.hasReachedMax ||
        _currentOrganizationUID == null ||
        _currentSearchQuery == null) {
      return;
    }

    // Emit loading more state
    emit(
      CompanySearchLoadingMore(
        companies: currentState.companies,
        hasReachedMax: currentState.hasReachedMax,
        lastDocument: currentState.lastDocument,
        currentSearchQuery: currentState.currentSearchQuery,
      ),
    );

    final result = await searchCompaniesByCode(
      SearchCompaniesByCodeParams(
        organizationUID: _currentOrganizationUID!,
        companyCode: _currentSearchQuery!,
        lastDocument: currentState.lastDocument,
        limit: 20,
      ),
    );

    result.fold(
      (failure) => emit(CompanySearchError(message: failure.message)),
      (paginationResponse) {
        final allCompanies = [
          ...currentState.companies,
          ...paginationResponse.items,
        ];

        emit(
          CompanySearchSuccess(
            companies: allCompanies,
            hasReachedMax: paginationResponse.hasReachedMax,
            lastDocument: paginationResponse.lastDoc,
            currentSearchQuery: currentState.currentSearchQuery,
          ),
        );
      },
    );
  }

  /// Handle clear search request
  void _onClearSearchRequested(
    ClearSearchRequested event,
    Emitter<CompanySearchState> emit,
  ) {
    _currentOrganizationUID = null;
    _currentSearchQuery = null;
    emit(const CompanySearchInitial());
  }

  /// Handle refresh search request
  Future<void> _onRefreshSearchRequested(
    RefreshSearchRequested event,
    Emitter<CompanySearchState> emit,
  ) async {
    if (_currentOrganizationUID != null && _currentSearchQuery != null) {
      add(
        SearchCompaniesRequested(
          organizationUID: _currentOrganizationUID!,
          companyCode: _currentSearchQuery!,
        ),
      );
    }
  }
}
