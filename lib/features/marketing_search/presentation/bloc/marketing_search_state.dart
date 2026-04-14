import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../admin/domain/entities/company.dart';
import '../../../profile/domain/entities/delegate.dart';

/// Base class for all marketing search states
abstract class MarketingSearchState extends Equatable {
  const MarketingSearchState();

  @override
  List<Object?> get props => [];
}

/// Initial state - no search performed yet
class MarketingSearchInitial extends MarketingSearchState {
  const MarketingSearchInitial();
}

/// Loading state - search in progress
class MarketingSearchLoading extends MarketingSearchState {
  final String searchType; // 'company' or 'delegate'

  const MarketingSearchLoading({required this.searchType});

  @override
  List<Object?> get props => [searchType];
}

/// Success state - company search results
class CompanySearchSuccess extends MarketingSearchState {
  final List<Company> companies;
  final String searchQuery;
  final bool hasReachedMax;
  final bool isLoadingMore;
  final DocumentSnapshot? lastDoc;

  const CompanySearchSuccess({
    required this.companies,
    required this.searchQuery,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
    this.lastDoc,
  });

  @override
  List<Object?> get props => [
    companies,
    searchQuery,
    hasReachedMax,
    isLoadingMore,
    lastDoc,
  ];

  CompanySearchSuccess copyWith({
    List<Company>? companies,
    String? searchQuery,
    bool? hasReachedMax,
    bool? isLoadingMore,
    DocumentSnapshot? lastDoc,
  }) {
    return CompanySearchSuccess(
      companies: companies ?? this.companies,
      searchQuery: searchQuery ?? this.searchQuery,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      lastDoc: lastDoc ?? this.lastDoc,
    );
  }
}

/// Success state - delegate search results
class DelegateSearchSuccess extends MarketingSearchState {
  final List<Delegate> delegates;
  final String searchQuery;
  final bool hasReachedMax;
  final bool isLoadingMore;
  final DocumentSnapshot? lastDoc;

  const DelegateSearchSuccess({
    required this.delegates,
    required this.searchQuery,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
    this.lastDoc,
  });

  @override
  List<Object?> get props => [
    delegates,
    searchQuery,
    hasReachedMax,
    isLoadingMore,
    lastDoc,
  ];

  DelegateSearchSuccess copyWith({
    List<Delegate>? delegates,
    String? searchQuery,
    bool? hasReachedMax,
    bool? isLoadingMore,
    DocumentSnapshot? lastDoc,
  }) {
    return DelegateSearchSuccess(
      delegates: delegates ?? this.delegates,
      searchQuery: searchQuery ?? this.searchQuery,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      lastDoc: lastDoc ?? this.lastDoc,
    );
  }
}

/// Empty state - no results found
class MarketingSearchEmpty extends MarketingSearchState {
  final String searchType; // 'company' or 'delegate'
  final String searchQuery;

  const MarketingSearchEmpty({
    required this.searchType,
    required this.searchQuery,
  });

  @override
  List<Object?> get props => [searchType, searchQuery];
}

/// Error state - search failed
class MarketingSearchError extends MarketingSearchState {
  final String message;

  const MarketingSearchError({required this.message});

  @override
  List<Object?> get props => [message];
}
