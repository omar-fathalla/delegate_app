part of 'private_label_report_bloc.dart';

enum PrivateLabelReportStatus { initial, loading, ready, failure }

enum PrivateLabelReportViewMode { branches, marketers }

enum PrivateLabelReportSortMode {
  highestScore, // الأعلى تقييماً ⬇
  lowestScore, // الأقل تقييماً ⬆
  mostAudits, // الأكثر توثيقاً ⬇
  alphabetical, // أبجدياً أ - ي
}

class BranchReportData extends Equatable {
  final String branchName;
  final double achievementScore; // 0..100
  final int totalAudits;
  final int totalRejected;
  final List<String> marketerUids;
  final List<String> marketerNames;

  const BranchReportData({
    required this.branchName,
    required this.achievementScore,
    required this.totalAudits,
    this.totalRejected = 0,
    required this.marketerUids,
    required this.marketerNames,
  });

  @override
  List<Object?> get props => [
        branchName,
        achievementScore,
        totalAudits,
        totalRejected,
        marketerUids,
        marketerNames,
      ];
}

class MarketerReportData extends Equatable {
  final String delegateUid;
  final String delegateName;
  final PrivateLabelKpi kpi;
  final int totalAudits;
  final int totalRejected;
  final List<String> branchNames;

  const MarketerReportData({
    required this.delegateUid,
    required this.delegateName,
    required this.kpi,
    required this.totalAudits,
    this.totalRejected = 0,
    required this.branchNames,
  });

  double get scorePercentage => kpi.scorePercentage;

  @override
  List<Object?> get props => [
        delegateUid,
        delegateName,
        kpi,
        totalAudits,
        totalRejected,
        branchNames,
      ];
}

class PrivateLabelReportState extends Equatable {
  final PrivateLabelReportStatus status;

  /// `yyyy-MM`
  final String monthKey;
  final List<String> branches;
  final String? selectedBranch;
  final String searchQuery;
  final PrivateLabelReportViewMode viewMode;
  final PrivateLabelReportSortMode sortMode;
  final List<BranchReportData> branchReports;
  final List<MarketerReportData> marketerReports;
  final String? errorMessage;

  const PrivateLabelReportState({
    this.status = PrivateLabelReportStatus.initial,
    required this.monthKey,
    this.branches = const [],
    this.selectedBranch,
    this.searchQuery = '',
    this.viewMode = PrivateLabelReportViewMode.branches,
    this.sortMode = PrivateLabelReportSortMode.highestScore,
    this.branchReports = const [],
    this.marketerReports = const [],
    this.errorMessage,
  });

  double get averageScore {
    if (branchReports.isEmpty) return 0.0;
    final total = branchReports.fold<double>(0.0, (sum, b) => sum + b.achievementScore);
    return double.parse((total / branchReports.length).toStringAsFixed(1));
  }

  int get totalAuditsMonth =>
      branchReports.fold<int>(0, (sum, b) => sum + b.totalAudits);

  int get totalActiveBranches =>
      branchReports.where((b) => b.totalAudits > 0 || b.marketerUids.isNotEmpty).length;

  int get totalActiveMarketers => marketerReports.length;

  List<BranchReportData> get filteredBranchReports {
    var list = branchReports;

    if (selectedBranch != null && selectedBranch!.trim().isNotEmpty) {
      final b = selectedBranch!.trim();
      list = list.where((item) => item.branchName.trim() == b).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((item) {
        final matchesBranch = item.branchName.toLowerCase().contains(q);
        final matchesMarketers =
            item.marketerNames.any((m) => m.toLowerCase().contains(q));
        return matchesBranch || matchesMarketers;
      }).toList();
    }

    final sorted = List<BranchReportData>.from(list);
    sorted.sort((a, b) {
      switch (sortMode) {
        case PrivateLabelReportSortMode.highestScore:
          final cmp = b.achievementScore.compareTo(a.achievementScore);
          if (cmp != 0) return cmp;
          return b.totalAudits.compareTo(a.totalAudits);
        case PrivateLabelReportSortMode.lowestScore:
          final cmp = a.achievementScore.compareTo(b.achievementScore);
          if (cmp != 0) return cmp;
          return a.totalAudits.compareTo(b.totalAudits);
        case PrivateLabelReportSortMode.mostAudits:
          final cmp = b.totalAudits.compareTo(a.totalAudits);
          if (cmp != 0) return cmp;
          return b.achievementScore.compareTo(a.achievementScore);
        case PrivateLabelReportSortMode.alphabetical:
          return a.branchName.compareTo(b.branchName);
      }
    });

    return sorted;
  }

  List<MarketerReportData> get filteredMarketerReports {
    var list = marketerReports;

    if (selectedBranch != null && selectedBranch!.trim().isNotEmpty) {
      final b = selectedBranch!.trim();
      list = list.where((m) => m.branchNames.contains(b)).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((m) {
        final matchesName = m.delegateName.toLowerCase().contains(q);
        final matchesBranch = m.branchNames.any((b) => b.toLowerCase().contains(q));
        return matchesName || matchesBranch;
      }).toList();
    }

    final sorted = List<MarketerReportData>.from(list);
    sorted.sort((a, b) {
      switch (sortMode) {
        case PrivateLabelReportSortMode.highestScore:
          final cmp = b.scorePercentage.compareTo(a.scorePercentage);
          if (cmp != 0) return cmp;
          return b.totalAudits.compareTo(a.totalAudits);
        case PrivateLabelReportSortMode.lowestScore:
          final cmp = a.scorePercentage.compareTo(b.scorePercentage);
          if (cmp != 0) return cmp;
          return a.totalAudits.compareTo(b.totalAudits);
        case PrivateLabelReportSortMode.mostAudits:
          final cmp = b.totalAudits.compareTo(a.totalAudits);
          if (cmp != 0) return cmp;
          return b.scorePercentage.compareTo(a.scorePercentage);
        case PrivateLabelReportSortMode.alphabetical:
          return a.delegateName.compareTo(b.delegateName);
      }
    });

    return sorted;
  }

  PrivateLabelReportState copyWith({
    PrivateLabelReportStatus? status,
    String? monthKey,
    List<String>? branches,
    String? selectedBranch,
    bool clearSelectedBranch = false,
    String? searchQuery,
    PrivateLabelReportViewMode? viewMode,
    PrivateLabelReportSortMode? sortMode,
    List<BranchReportData>? branchReports,
    List<MarketerReportData>? marketerReports,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PrivateLabelReportState(
      status: status ?? this.status,
      monthKey: monthKey ?? this.monthKey,
      branches: branches ?? this.branches,
      selectedBranch:
          clearSelectedBranch ? null : (selectedBranch ?? this.selectedBranch),
      searchQuery: searchQuery ?? this.searchQuery,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      branchReports: branchReports ?? this.branchReports,
      marketerReports: marketerReports ?? this.marketerReports,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        monthKey,
        branches,
        selectedBranch,
        searchQuery,
        viewMode,
        sortMode,
        branchReports,
        marketerReports,
        errorMessage,
      ];
}
