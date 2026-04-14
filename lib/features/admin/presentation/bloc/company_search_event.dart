import 'package:equatable/equatable.dart';

/// Events for CompanySearchBloc
abstract class CompanySearchEvent extends Equatable {
  const CompanySearchEvent();

  @override
  List<Object?> get props => [];
}

/// Event to search companies by code
class SearchCompaniesRequested extends CompanySearchEvent {
  final String organizationUID;
  final String companyCode;

  const SearchCompaniesRequested({
    required this.organizationUID,
    required this.companyCode,
  });

  @override
  List<Object?> get props => [organizationUID, companyCode];
}

/// Event to load more companies (pagination)
class LoadMoreCompaniesRequested extends CompanySearchEvent {
  const LoadMoreCompaniesRequested();
}

/// Event to clear search results
class ClearSearchRequested extends CompanySearchEvent {
  const ClearSearchRequested();
}

/// Event to refresh search results
class RefreshSearchRequested extends CompanySearchEvent {
  const RefreshSearchRequested();
}
