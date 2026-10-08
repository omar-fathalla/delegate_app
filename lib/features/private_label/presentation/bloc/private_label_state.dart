part of 'private_label_bloc.dart';

enum PrivateLabelStatus { initial, loading, ready, failure }

enum PrivateLabelFeedbackType { success, info, error }

/// One-shot UI message. [id] makes repeated identical messages distinct.
class PrivateLabelFeedback extends Equatable {
  final int id;
  final String message;
  final PrivateLabelFeedbackType type;

  const PrivateLabelFeedback({
    required this.id,
    required this.message,
    required this.type,
  });

  @override
  List<Object?> get props => [id, message, type];
}

class PrivateLabelState extends Equatable {
  final PrivateLabelStatus status;
  final int year;
  final int month;

  /// Server (or cached) day summaries.
  final List<PrivateLabelDay> serverDays;

  /// Audits captured on this device and not yet uploaded.
  final List<PrivateLabelAuditDraft> pendingDrafts;

  /// [serverDays] merged with [pendingDrafts] (what the KPI is computed from).
  final List<PrivateLabelDay> days;
  final int restAllowance;
  final PrivateLabelKpi? kpi;
  final List<PrivateLabelProduct> products;
  final List<String> branches;
  final String? selectedDate;
  final List<PrivateLabelAudit> selectedDateAudits;
  final bool isLoadingAudits;
  final bool isRefreshing;
  final bool isSubmitting;
  final bool isSyncing;
  final bool isUpdatingRest;
  final String? errorMessage;
  final PrivateLabelFeedback? feedback;

  const PrivateLabelState({
    this.status = PrivateLabelStatus.initial,
    required this.year,
    required this.month,
    this.serverDays = const [],
    this.pendingDrafts = const [],
    this.days = const [],
    this.restAllowance = PrivateLabelRemoteDataSourceImpl.defaultMonthlyRestDays,
    this.kpi,
    this.products = const [],
    this.branches = const [],
    this.selectedDate,
    this.selectedDateAudits = const [],
    this.isLoadingAudits = false,
    this.isRefreshing = false,
    this.isSubmitting = false,
    this.isSyncing = false,
    this.isUpdatingRest = false,
    this.errorMessage,
    this.feedback,
  });

  /// Day summary for `yyyy-MM-dd`, if any.
  PrivateLabelDay? dayFor(String date) {
    for (final d in days) {
      if (d.date == date) return d;
    }
    return null;
  }

  List<PrivateLabelAuditDraft> pendingFor(String date) =>
      pendingDrafts.where((d) => d.auditDate == date).toList();

  PrivateLabelState copyWith({
    PrivateLabelStatus? status,
    int? year,
    int? month,
    List<PrivateLabelDay>? serverDays,
    List<PrivateLabelAuditDraft>? pendingDrafts,
    List<PrivateLabelDay>? days,
    int? restAllowance,
    PrivateLabelKpi? kpi,
    List<PrivateLabelProduct>? products,
    List<String>? branches,
    String? selectedDate,
    List<PrivateLabelAudit>? selectedDateAudits,
    bool? isLoadingAudits,
    bool? isRefreshing,
    bool? isSubmitting,
    bool? isSyncing,
    bool? isUpdatingRest,
    String? errorMessage,
    bool clearError = false,
    PrivateLabelFeedback? feedback,
  }) {
    return PrivateLabelState(
      status: status ?? this.status,
      year: year ?? this.year,
      month: month ?? this.month,
      serverDays: serverDays ?? this.serverDays,
      pendingDrafts: pendingDrafts ?? this.pendingDrafts,
      days: days ?? this.days,
      restAllowance: restAllowance ?? this.restAllowance,
      kpi: kpi ?? this.kpi,
      products: products ?? this.products,
      branches: branches ?? this.branches,
      selectedDate: selectedDate ?? this.selectedDate,
      selectedDateAudits: selectedDateAudits ?? this.selectedDateAudits,
      isLoadingAudits: isLoadingAudits ?? this.isLoadingAudits,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSyncing: isSyncing ?? this.isSyncing,
      isUpdatingRest: isUpdatingRest ?? this.isUpdatingRest,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      feedback: feedback ?? this.feedback,
    );
  }

  @override
  List<Object?> get props => [
        status,
        year,
        month,
        serverDays,
        pendingDrafts,
        days,
        restAllowance,
        kpi,
        products,
        branches,
        selectedDate,
        selectedDateAudits,
        isLoadingAudits,
        isRefreshing,
        isSubmitting,
        isSyncing,
        isUpdatingRest,
        errorMessage,
        feedback,
      ];
}
