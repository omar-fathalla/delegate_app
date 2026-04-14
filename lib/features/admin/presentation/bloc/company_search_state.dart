import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/company.dart';

/// States for CompanySearchBloc
abstract class CompanySearchState extends Equatable {
  const CompanySearchState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class CompanySearchInitial extends CompanySearchState {
  const CompanySearchInitial();
}

/// Loading state (initial search)
class CompanySearchLoading extends CompanySearchState {
  const CompanySearchLoading();
}

/// Loading more state (pagination)
class CompanySearchLoadingMore extends CompanySearchState {
  final List<Company> companies;
  final bool hasReachedMax;
  final DocumentSnapshot? lastDocument;
  final String currentSearchQuery;

  const CompanySearchLoadingMore({
    required this.companies,
    required this.hasReachedMax,
    this.lastDocument,
    required this.currentSearchQuery,
  });

  @override
  List<Object?> get props => [
    companies,
    hasReachedMax,
    lastDocument,
    currentSearchQuery,
  ];
}

/// Success state with data
class CompanySearchSuccess extends CompanySearchState {
  final List<Company> companies;
  final bool hasReachedMax;
  final DocumentSnapshot? lastDocument;
  final String currentSearchQuery;

  const CompanySearchSuccess({
    required this.companies,
    required this.hasReachedMax,
    this.lastDocument,
    required this.currentSearchQuery,
  });

  @override
  List<Object?> get props => [
    companies,
    hasReachedMax,
    lastDocument,
    currentSearchQuery,
  ];

  /// Copy with new values
  CompanySearchSuccess copyWith({
    List<Company>? companies,
    bool? hasReachedMax,
    DocumentSnapshot? lastDocument,
    String? currentSearchQuery,
  }) {
    return CompanySearchSuccess(
      companies: companies ?? this.companies,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      lastDocument: lastDocument ?? this.lastDocument,
      currentSearchQuery: currentSearchQuery ?? this.currentSearchQuery,
    );
  }
}

/// Error state
class CompanySearchError extends CompanySearchState {
  final String message;

  const CompanySearchError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// Empty state (no results found)
class CompanySearchEmpty extends CompanySearchState {
  final String searchQuery;

  const CompanySearchEmpty({required this.searchQuery});

  @override
  List<Object?> get props => [searchQuery];
}
