import 'package:equatable/equatable.dart';

/// Base class for all marketing search events
abstract class MarketingSearchEvent extends Equatable {
  const MarketingSearchEvent();

  @override
  List<Object?> get props => [];
}

/// Event to search for a company by name (first batch)
class SearchCompanyRequested extends MarketingSearchEvent {
  final String organizationUID;
  final String companyName;

  const SearchCompanyRequested({
    required this.organizationUID,
    required this.companyName,
  });

  @override
  List<Object?> get props => [organizationUID, companyName];
}

/// Event to load more companies (pagination)
class LoadMoreCompaniesRequested extends MarketingSearchEvent {
  const LoadMoreCompaniesRequested();
}

/// Event to search for a delegate by name and/or phone number (first batch)
class SearchDelegateRequested extends MarketingSearchEvent {
  final String organizationUID;
  final String? phoneNumber;
  final String? name;

  const SearchDelegateRequested({
    required this.organizationUID,
    this.phoneNumber,
    this.name,
  });

  @override
  List<Object?> get props => [organizationUID, phoneNumber, name];
}

/// Event to load more delegates (pagination)
class LoadMoreDelegatesRequested extends MarketingSearchEvent {
  const LoadMoreDelegatesRequested();
}

/// Event to clear search results
class ClearSearchRequested extends MarketingSearchEvent {
  const ClearSearchRequested();
}
