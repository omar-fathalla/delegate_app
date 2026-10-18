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

  // Branch, Product, and Marketer filtering for audit review:
  final List<String> branches;
  final String? selectedBranch;
  final String? selectedProduct;
  final String? selectedMarketer;

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
    this.selectedProduct,
    this.selectedMarketer,
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

    if (selectedProduct != null && selectedProduct!.trim().isNotEmpty) {
      final p = selectedProduct!.trim().toLowerCase();
      list = list.where((a) => a.productName.trim().toLowerCase() == p).toList();
    }

    if (selectedMarketer != null && selectedMarketer!.trim().isNotEmpty) {
      final m = selectedMarketer!.trim();
      list = list.where((a) => a.delegateName.trim() == m).toList();
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

  /// All unique product names (from Catalog products + any audits).
  List<String> get allAvailableProducts {
    final map = <String, String>{};
    for (final p in products) {
      final trimmed = p.name.trim();
      if (trimmed.isNotEmpty) {
        map.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
    }
    for (final a in audits) {
      final trimmed = a.productName.trim();
      if (trimmed.isNotEmpty) {
        map.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
    }
    final list = map.values.toList()..sort();
    return list;
  }

  /// Finds the Catalog product metadata matching [productName] if present.
  PrivateLabelProduct? productForName(String productName) {
    final lower = productName.trim().toLowerCase();
    for (final p in products) {
      if (p.name.trim().toLowerCase() == lower) return p;
    }
    return null;
  }

  /// Audits count for a given product name (or total audits if null).
  int countForProduct(String? productName) {
    if (productName == null || productName.trim().isEmpty) return audits.length;
    final lower = productName.trim().toLowerCase();
    return audits.where((a) => a.productName.trim().toLowerCase() == lower).length;
  }

  /// All unique marketer names from loaded audits.
  List<String> get allAvailableMarketers {
    final set = <String>{};
    for (final a in audits) {
      final name = a.delegateName.trim();
      if (name.isNotEmpty) set.add(name);
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
    String? selectedProduct,
    bool clearSelectedProduct = false,
    String? selectedMarketer,
    bool clearSelectedMarketer = false,
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
      selectedProduct: clearSelectedProduct ? null : (selectedProduct ?? this.selectedProduct),
      selectedMarketer: clearSelectedMarketer ? null : (selectedMarketer ?? this.selectedMarketer),
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
        selectedProduct,
        selectedMarketer,
      ];
}

