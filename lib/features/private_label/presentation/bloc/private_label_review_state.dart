part of 'private_label_review_bloc.dart';

enum PrivateLabelReviewStatusView { initial, loading, ready, failure }

/// Smart triage filters for the auditor.
enum PrivateLabelReviewFilter { all, pending, priceIssues, rejected }

class PrivateLabelReviewFeedback extends Equatable {
  final int id;
  final String message;
  final bool isError;

  const PrivateLabelReviewFeedback({
    required this.id,
    required this.message,
    this.isError = false,
  });

  @override
  List<Object?> get props => [id, message, isError];
}

class PrivateLabelReviewState extends Equatable {
  final PrivateLabelReviewStatusView status;

  /// `yyyy-MM-dd` (null means all dates / unconstrained review queue)
  final String? date;
  final List<PrivateLabelAudit> audits;
  final PrivateLabelReviewFilter filter;
  final List<PrivateLabelProduct> products;
  final String? savingAuditId;
  final bool isSavingProduct;
  final String? errorMessage;
  final PrivateLabelReviewFeedback? feedback;

  // Branch filtering for audit review:
  final List<String> branches;
  final String? selectedBranch;

  const PrivateLabelReviewState({
    this.status = PrivateLabelReviewStatusView.initial,
    this.date,
    this.audits = const [],
    this.filter = PrivateLabelReviewFilter.pending,
    this.products = const [],
    this.savingAuditId,
    this.isSavingProduct = false,
    this.errorMessage,
    this.feedback,
    this.branches = const [],
    this.selectedBranch,
  });

  static bool isPriceIssue(PrivateLabelAudit a) =>
      a.hasPriceMismatch || a.reviewStatus == PrivateLabelReviewStatus.priceIssue;

  int countFor(PrivateLabelReviewFilter f) => _apply(f).length;

  List<PrivateLabelAudit> get filteredAudits => _apply(filter);

  List<PrivateLabelAudit> _apply(PrivateLabelReviewFilter f) {
    var list = audits;
    switch (f) {
      case PrivateLabelReviewFilter.all:
        break;
      case PrivateLabelReviewFilter.pending:
        list = list
            .where((a) => a.reviewStatus == PrivateLabelReviewStatus.pending)
            .toList();
        break;
      case PrivateLabelReviewFilter.priceIssues:
        list = list.where(isPriceIssue).toList();
        break;
      case PrivateLabelReviewFilter.rejected:
        list = list
            .where((a) => a.reviewStatus == PrivateLabelReviewStatus.rejected)
            .toList();
        break;
    }

    if (selectedBranch != null && selectedBranch!.trim().isNotEmpty) {
      final b = selectedBranch!.trim();
      list = list.where((a) => a.branchName.trim() == b).toList();
    }

    return list;
  }

  /// All unique branch names (from official branch list + any audits).
  List<String> get allAvailableBranches {
    final set = <String>{...branches};
    for (final a in audits) {
      if (a.branchName.isNotEmpty) set.add(a.branchName);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Filtered audits grouped by branch (branch name → audits), sorted alphabetically.
  Map<String, List<PrivateLabelAudit>> get groupedByBranch {
    final map = <String, List<PrivateLabelAudit>>{};
    for (final a in filteredAudits) {
      final b = a.branchName.isEmpty ? 'بدون فرع' : a.branchName;
      map.putIfAbsent(b, () => []).add(a);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  PrivateLabelReviewState copyWith({
    PrivateLabelReviewStatusView? status,
    String? date,
    bool clearDate = false,
    List<PrivateLabelAudit>? audits,
    PrivateLabelReviewFilter? filter,
    List<PrivateLabelProduct>? products,
    String? savingAuditId,
    bool clearSaving = false,
    bool? isSavingProduct,
    String? errorMessage,
    bool clearError = false,
    PrivateLabelReviewFeedback? feedback,
    List<String>? branches,
    String? selectedBranch,
    bool clearSelectedBranch = false,
  }) {
    return PrivateLabelReviewState(
      status: status ?? this.status,
      date: clearDate ? null : (date ?? this.date),
      audits: audits ?? this.audits,
      filter: filter ?? this.filter,
      products: products ?? this.products,
      savingAuditId: clearSaving ? null : (savingAuditId ?? this.savingAuditId),
      isSavingProduct: isSavingProduct ?? this.isSavingProduct,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      feedback: feedback ?? this.feedback,
      branches: branches ?? this.branches,
      selectedBranch: clearSelectedBranch ? null : (selectedBranch ?? this.selectedBranch),
    );
  }

  @override
  List<Object?> get props => [
        status,
        date,
        audits,
        filter,
        products,
        savingAuditId,
        isSavingProduct,
        errorMessage,
        feedback,
        branches,
        selectedBranch,
      ];
}
