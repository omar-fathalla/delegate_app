part of 'private_label_report_bloc.dart';

sealed class PrivateLabelReportEvent extends Equatable {
  const PrivateLabelReportEvent();

  @override
  List<Object?> get props => [];
}

final class PrivateLabelReportStarted extends PrivateLabelReportEvent {
  final String organizationUID;
  final String companyUID;

  const PrivateLabelReportStarted({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID];
}

final class PrivateLabelReportMonthChanged extends PrivateLabelReportEvent {
  /// `yyyy-MM`
  final String monthKey;

  const PrivateLabelReportMonthChanged(this.monthKey);

  @override
  List<Object?> get props => [monthKey];
}

final class PrivateLabelReportBranchFilterChanged extends PrivateLabelReportEvent {
  final String? branch;

  const PrivateLabelReportBranchFilterChanged(this.branch);

  @override
  List<Object?> get props => [branch];
}

final class PrivateLabelReportSearchQueryChanged extends PrivateLabelReportEvent {
  final String query;

  const PrivateLabelReportSearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

final class PrivateLabelReportViewModeChanged extends PrivateLabelReportEvent {
  final PrivateLabelReportViewMode mode;

  const PrivateLabelReportViewModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

final class PrivateLabelReportSortModeChanged extends PrivateLabelReportEvent {
  final PrivateLabelReportSortMode mode;

  const PrivateLabelReportSortModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

final class PrivateLabelReportRefreshRequested extends PrivateLabelReportEvent {
  const PrivateLabelReportRefreshRequested();
}
