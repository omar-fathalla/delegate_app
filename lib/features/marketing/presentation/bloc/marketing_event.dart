part of 'marketing_bloc.dart';

abstract class MarketingEvent extends Equatable {
  const MarketingEvent();

  @override
  List<Object?> get props => [];
}

class LoadCompanies extends MarketingEvent {
  final String organizationUID;

  const LoadCompanies({required this.organizationUID});

  @override
  List<Object?> get props => [organizationUID];
}

/// Load companies with pagination
class LoadCompaniesPaginated extends MarketingEvent {
  final String organizationUID;
  final bool isInitialLoad;

  const LoadCompaniesPaginated({
    required this.organizationUID,
    this.isInitialLoad = false,
  });

  @override
  List<Object?> get props => [organizationUID, isInitialLoad];
}

class LoadDelegates extends MarketingEvent {
  final String organizationUID;
  final String? companyUID;

  const LoadDelegates({required this.organizationUID, this.companyUID});

  @override
  List<Object?> get props => [organizationUID, companyUID];
}

class SearchDelegates extends MarketingEvent {
  final String organizationUID;
  final String query;
  final String? statusFilter;
  final String? positionFilter;

  const SearchDelegates({
    required this.organizationUID,
    required this.query,
    this.statusFilter,
    this.positionFilter,
  });

  @override
  List<Object?> get props => [
    organizationUID,
    query,
    statusFilter,
    positionFilter,
  ];
}
