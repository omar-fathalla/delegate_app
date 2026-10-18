part of 'private_label_review_bloc.dart';

sealed class PrivateLabelReviewEvent extends Equatable {
  const PrivateLabelReviewEvent();

  @override
  List<Object?> get props => [];
}

final class PrivateLabelReviewStarted extends PrivateLabelReviewEvent {
  final String organizationUID;
  final String companyUID;
  final String reviewerUid;
  final String reviewerName;

  const PrivateLabelReviewStarted({
    required this.organizationUID,
    required this.companyUID,
    required this.reviewerUid,
    required this.reviewerName,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, reviewerUid, reviewerName];
}

final class PrivateLabelReviewDateChanged extends PrivateLabelReviewEvent {
  /// `yyyy-MM-dd` or null for all dates
  final String? date;

  const PrivateLabelReviewDateChanged(this.date);

  @override
  List<Object?> get props => [date];
}

final class PrivateLabelReviewFilterChanged extends PrivateLabelReviewEvent {
  final PrivateLabelReviewFilter filter;

  const PrivateLabelReviewFilterChanged(this.filter);

  @override
  List<Object?> get props => [filter];
}

final class PrivateLabelReviewRefreshRequested extends PrivateLabelReviewEvent {
  const PrivateLabelReviewRefreshRequested();
}

final class PrivateLabelReviewDecisionSubmitted extends PrivateLabelReviewEvent {
  final String auditId;
  final PrivateLabelReviewStatus status;
  final String? notes;

  const PrivateLabelReviewDecisionSubmitted({
    required this.auditId,
    required this.status,
    this.notes,
  });

  @override
  List<Object?> get props => [auditId, status, notes];
}

final class PrivateLabelReviewProductSaved extends PrivateLabelReviewEvent {
  final PrivateLabelProduct product;

  const PrivateLabelReviewProductSaved(this.product);

  @override
  List<Object?> get props => [product];
}

final class PrivateLabelReviewAuditDeleted extends PrivateLabelReviewEvent {
  final PrivateLabelAudit audit;

  const PrivateLabelReviewAuditDeleted(this.audit);

  @override
  List<Object?> get props => [audit];
}

final class PrivateLabelReviewAuditUpdated extends PrivateLabelReviewEvent {
  final PrivateLabelAudit audit;

  const PrivateLabelReviewAuditUpdated(this.audit);

  @override
  List<Object?> get props => [audit];
}

final class PrivateLabelReviewBranchSelected extends PrivateLabelReviewEvent {
  final String? branch;

  const PrivateLabelReviewBranchSelected(this.branch);

  @override
  List<Object?> get props => [branch];
}

final class PrivateLabelReviewProductSelected extends PrivateLabelReviewEvent {
  final String? productName;

  const PrivateLabelReviewProductSelected(this.productName);

  @override
  List<Object?> get props => [productName];
}

final class PrivateLabelReviewMarketerSelected extends PrivateLabelReviewEvent {
  final String? marketerName;

  const PrivateLabelReviewMarketerSelected(this.marketerName);

  @override
  List<Object?> get props => [marketerName];
}

