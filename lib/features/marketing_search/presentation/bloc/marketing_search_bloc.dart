import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/search_company_by_code.dart';
import '../../domain/usecases/search_delegate_by_phone.dart';
import 'marketing_search_event.dart';
import 'marketing_search_state.dart';

/// BLoC for marketing search operations with infinite scroll pagination
class MarketingSearchBloc
    extends Bloc<MarketingSearchEvent, MarketingSearchState> {
  final SearchCompanyByCode searchCompanyByCode;
  final SearchDelegateByPhone searchDelegateByPhone;

  // Store current search parameters for pagination
  String? _currentOrganizationUID;
  String? _currentCompanyName;
  String? _currentPhoneNumber;

  MarketingSearchBloc({
    required this.searchCompanyByCode,
    required this.searchDelegateByPhone,
  }) : super(const MarketingSearchInitial()) {
    on<SearchCompanyRequested>(_onSearchCompanyRequested);
    on<LoadMoreCompaniesRequested>(_onLoadMoreCompaniesRequested);
    on<SearchDelegateRequested>(_onSearchDelegateRequested);
    on<LoadMoreDelegatesRequested>(_onLoadMoreDelegatesRequested);
    on<ClearSearchRequested>(_onClearSearchRequested);
  }

  /// Handle search company request (first batch)
  Future<void> _onSearchCompanyRequested(
    SearchCompanyRequested event,
    Emitter<MarketingSearchState> emit,
  ) async {
    // Store search parameters for pagination
    _currentOrganizationUID = event.organizationUID;
    _currentCompanyName = event.companyName;

    emit(const MarketingSearchLoading(searchType: 'company'));

    final result = await searchCompanyByCode(
      SearchCompanyByCodeParams(
        organizationUID: event.organizationUID,
        companyName: event.companyName,
      ),
    );

    result.fold(
      (failure) => emit(MarketingSearchError(message: failure.message)),
      (paginationResponse) {
        if (paginationResponse.items.isEmpty) {
          emit(
            MarketingSearchEmpty(
              searchType: 'company',
              searchQuery: event.companyName,
            ),
          );
        } else {
          emit(
            CompanySearchSuccess(
              companies: paginationResponse.items,
              searchQuery: event.companyName,
              hasReachedMax: paginationResponse.hasReachedMax,
              lastDoc: paginationResponse.lastDoc,
            ),
          );
        }
      },
    );
  }

  /// Handle load more companies request (pagination)
  Future<void> _onLoadMoreCompaniesRequested(
    LoadMoreCompaniesRequested event,
    Emitter<MarketingSearchState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CompanySearchSuccess) return;
    if (currentState.hasReachedMax || currentState.isLoadingMore) return;

    // Emit loading more state
    emit(currentState.copyWith(isLoadingMore: true));

    final result = await searchCompanyByCode(
      SearchCompanyByCodeParams(
        organizationUID: _currentOrganizationUID!,
        companyName: _currentCompanyName!,
        startAfterDoc: currentState.lastDoc,
      ),
    );

    result.fold(
      (failure) => emit(MarketingSearchError(message: failure.message)),
      (paginationResponse) {
        emit(
          currentState.copyWith(
            companies: [...currentState.companies, ...paginationResponse.items],
            hasReachedMax: paginationResponse.hasReachedMax,
            isLoadingMore: false,
            lastDoc: paginationResponse.lastDoc,
          ),
        );
      },
    );
  }

  /// Handle search delegate request (first batch)
  Future<void> _onSearchDelegateRequested(
    SearchDelegateRequested event,
    Emitter<MarketingSearchState> emit,
  ) async {
    // Store search parameters for pagination
    _currentOrganizationUID = event.organizationUID;
    _currentPhoneNumber = event.phoneNumber;

    emit(const MarketingSearchLoading(searchType: 'delegate'));

    final result = await searchDelegateByPhone(
      SearchDelegateByPhoneParams(
        organizationUID: event.organizationUID,
        phoneNumber: event.phoneNumber,
      ),
    );

    result.fold(
      (failure) => emit(MarketingSearchError(message: failure.message)),
      (paginationResponse) {
        if (paginationResponse.items.isEmpty) {
          emit(
            MarketingSearchEmpty(
              searchType: 'delegate',
              searchQuery: event.phoneNumber,
            ),
          );
        } else {
          emit(
            DelegateSearchSuccess(
              delegates: paginationResponse.items,
              searchQuery: event.phoneNumber,
              hasReachedMax: paginationResponse.hasReachedMax,
              lastDoc: paginationResponse.lastDoc,
            ),
          );
        }
      },
    );
  }

  /// Handle load more delegates request (pagination)
  Future<void> _onLoadMoreDelegatesRequested(
    LoadMoreDelegatesRequested event,
    Emitter<MarketingSearchState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DelegateSearchSuccess) return;
    if (currentState.hasReachedMax || currentState.isLoadingMore) return;

    // Emit loading more state
    emit(currentState.copyWith(isLoadingMore: true));

    final result = await searchDelegateByPhone(
      SearchDelegateByPhoneParams(
        organizationUID: _currentOrganizationUID!,
        phoneNumber: _currentPhoneNumber!,
        startAfterDoc: currentState.lastDoc,
      ),
    );

    result.fold(
      (failure) => emit(MarketingSearchError(message: failure.message)),
      (paginationResponse) {
        emit(
          currentState.copyWith(
            delegates: [...currentState.delegates, ...paginationResponse.items],
            hasReachedMax: paginationResponse.hasReachedMax,
            isLoadingMore: false,
            lastDoc: paginationResponse.lastDoc,
          ),
        );
      },
    );
  }

  /// Handle clear search request
  void _onClearSearchRequested(
    ClearSearchRequested event,
    Emitter<MarketingSearchState> emit,
  ) {
    // Clear stored search parameters
    _currentOrganizationUID = null;
    _currentCompanyName = null;
    _currentPhoneNumber = null;

    emit(const MarketingSearchInitial());
  }
}
