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

// ─── Branch Events ─────────────────────────────────────────────────────

/// Loads all branches from Firestore
class LoadBranches extends MarketingEvent {
  const LoadBranches();
}

/// Loads today's attendance for [branchName]
class LoadTodayAttendanceByBranch extends MarketingEvent {
  final String branchName;
  final String organizationId;

  const LoadTodayAttendanceByBranch({
    required this.branchName,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [branchName, organizationId];
}

/// Loads saved branch preferences for [userId]
class LoadBranchPreferences extends MarketingEvent {
  final String userId;
  const LoadBranchPreferences({required this.userId});
  @override
  List<Object?> get props => [userId];
}

/// Adds a branch to the user's favorites
class AddFavoriteBranch extends MarketingEvent {
  final String userId;
  final String branchName;
  const AddFavoriteBranch({required this.userId, required this.branchName});
  @override
  List<Object?> get props => [userId, branchName];
}

/// Removes a branch from the user's favorites
class RemoveFavoriteBranch extends MarketingEvent {
  final String userId;
  final String branchName;
  const RemoveFavoriteBranch({required this.userId, required this.branchName});
  @override
  List<Object?> get props => [userId, branchName];
}

/// Sets [branchName] as the currently active (displayed) branch
class SetActiveBranch extends MarketingEvent {
  final String userId;
  final String branchName;
  final String organizationId;
  const SetActiveBranch({
    required this.userId,
    required this.branchName,
    required this.organizationId,
  });
  @override
  List<Object?> get props => [userId, branchName, organizationId];
}

/// Loads today's attendance for ALL favorite branches at once
class LoadAllFavoriteBranchesAttendance extends MarketingEvent {
  final List<String> favoriteBranches;
  final String organizationId;
  final DateTime? date;

  const LoadAllFavoriteBranchesAttendance({
    required this.favoriteBranches,
    required this.organizationId,
    this.date,
  });

  @override
  List<Object?> get props => [favoriteBranches, organizationId, date];
}

