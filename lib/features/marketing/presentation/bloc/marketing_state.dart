part of 'marketing_bloc.dart';

abstract class MarketingState extends Equatable {
  const MarketingState();

  @override
  List<Object?> get props => [];
}

class MarketingInitial extends MarketingState {}

class CompaniesLoading extends MarketingState {}

class CompaniesLoaded extends MarketingState {
  final List<Map<String, dynamic>> companies;
  final bool hasMore;
  final bool isLoadingMore;

  const CompaniesLoaded({
    required this.companies,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  @override
  List<Object?> get props => [companies, hasMore, isLoadingMore];

  CompaniesLoaded copyWith({
    List<Map<String, dynamic>>? companies,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return CompaniesLoaded(
      companies: companies ?? this.companies,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class CompaniesError extends MarketingState {
  final String message;

  const CompaniesError({required this.message});

  @override
  List<Object?> get props => [message];
}

class DelegatesLoading extends MarketingState {}

class DelegatesLoaded extends MarketingState {
  final List<Delegate> delegates;

  const DelegatesLoaded({required this.delegates});

  @override
  List<Object?> get props => [delegates];
}

class DelegatesError extends MarketingState {
  final String message;

  const DelegatesError({required this.message});

  @override
  List<Object?> get props => [message];
}
