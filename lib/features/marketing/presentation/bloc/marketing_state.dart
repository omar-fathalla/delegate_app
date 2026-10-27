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

// ─── Branch States ──────────────────────────────────────────────────────

class BranchesLoading extends MarketingState {}

class BranchesLoaded extends MarketingState {
  final List<Map<String, dynamic>> branches;
  const BranchesLoaded({required this.branches});
  @override
  List<Object?> get props => [branches];
}

class BranchesError extends MarketingState {
  final String message;
  const BranchesError({required this.message});
  @override
  List<Object?> get props => [message];
}

class TodayAttendanceLoading extends MarketingState {}

class TodayAttendanceLoaded extends MarketingState {
  final List<Map<String, dynamic>> records;
  final String branchName;
  const TodayAttendanceLoaded({
    required this.records,
    required this.branchName,
  });
  @override
  List<Object?> get props => [records, branchName];
}

class TodayAttendanceError extends MarketingState {
  final String message;
  const TodayAttendanceError({required this.message});
  @override
  List<Object?> get props => [message];
}

/// Fired after loading/updating branch preferences
class BranchPreferencesLoaded extends MarketingState {
  final List<String> favoriteBranches;
  final String? activeBranch;

  const BranchPreferencesLoaded({
    required this.favoriteBranches,
    this.activeBranch,
  });

  @override
  List<Object?> get props => [favoriteBranches, activeBranch];

  BranchPreferencesLoaded copyWith({
    List<String>? favoriteBranches,
    String? activeBranch,
    bool clearActiveBranch = false,
  }) {
    return BranchPreferencesLoaded(
      favoriteBranches: favoriteBranches ?? this.favoriteBranches,
      activeBranch: clearActiveBranch ? null : (activeBranch ?? this.activeBranch),
    );
  }
}

/// Loading attendance for all favorite branches
class AllBranchesAttendanceLoading extends MarketingState {}

/// Attendance data for ALL favorite branches loaded
/// [data] maps branchName → list of today's attendance records
class AllBranchesAttendanceLoaded extends MarketingState {
  final Map<String, List<Map<String, dynamic>>> data;
  final List<String> favoriteBranches;
  final Set<String> loadingBranches;
  /// True while profile enrichment is still in flight after first paint.
  final bool isEnriching;

  const AllBranchesAttendanceLoaded({
    required this.data,
    required this.favoriteBranches,
    this.loadingBranches = const {},
    this.isEnriching = false,
  });

  bool isBranchLoading(String branch) => loadingBranches.contains(branch);

  AllBranchesAttendanceLoaded copyWith({
    Map<String, List<Map<String, dynamic>>>? data,
    List<String>? favoriteBranches,
    Set<String>? loadingBranches,
    bool? isEnriching,
  }) {
    return AllBranchesAttendanceLoaded(
      data: data ?? this.data,
      favoriteBranches: favoriteBranches ?? this.favoriteBranches,
      loadingBranches: loadingBranches ?? this.loadingBranches,
      isEnriching: isEnriching ?? this.isEnriching,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AllBranchesAttendanceLoaded &&
        const DeepCollectionEquality().equals(data, other.data) &&
        const ListEquality().equals(favoriteBranches, other.favoriteBranches) &&
        const SetEquality().equals(loadingBranches, other.loadingBranches) &&
        isEnriching == other.isEnriching;
  }

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(data) ^
      const ListEquality().hash(favoriteBranches) ^
      const SetEquality().hash(loadingBranches) ^
      isEnriching.hashCode;

  @override
  List<Object?> get props => [data, favoriteBranches, loadingBranches, isEnriching];
}

class AllBranchesAttendanceError extends MarketingState {
  final String message;
  const AllBranchesAttendanceError({required this.message});
  @override
  List<Object?> get props => [message];
}

