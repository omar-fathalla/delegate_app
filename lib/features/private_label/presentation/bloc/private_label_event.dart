part of 'private_label_bloc.dart';

sealed class PrivateLabelEvent extends Equatable {
  const PrivateLabelEvent();

  @override
  List<Object?> get props => [];
}

/// Boots the feature for the signed-in marketer (cache-first, then network).
final class PrivateLabelStarted extends PrivateLabelEvent {
  final String organizationUID;
  final String companyUID;
  final String delegateUid;
  final String delegateName;

  /// When false (home card), skips loading the catalog, branches and day list.
  final bool loadDetails;

  const PrivateLabelStarted({
    required this.organizationUID,
    required this.companyUID,
    required this.delegateUid,
    required this.delegateName,
    this.loadDetails = true,
  });

  @override
  List<Object?> get props =>
      [organizationUID, companyUID, delegateUid, delegateName, loadDetails];
}

final class PrivateLabelRefreshRequested extends PrivateLabelEvent {
  const PrivateLabelRefreshRequested();
}

final class PrivateLabelMonthChanged extends PrivateLabelEvent {
  final int year;
  final int month;

  const PrivateLabelMonthChanged({required this.year, required this.month});

  @override
  List<Object?> get props => [year, month];
}

final class PrivateLabelAuditSubmitted extends PrivateLabelEvent {
  final PrivateLabelAuditDraft draft;

  const PrivateLabelAuditSubmitted(this.draft);

  @override
  List<Object?> get props => [draft];
}

final class PrivateLabelRestDayRequested extends PrivateLabelEvent {
  /// `yyyy-MM-dd`
  final String date;

  const PrivateLabelRestDayRequested(this.date);

  @override
  List<Object?> get props => [date];
}

final class PrivateLabelRestDayCancelled extends PrivateLabelEvent {
  /// `yyyy-MM-dd`
  final String date;

  const PrivateLabelRestDayCancelled(this.date);

  @override
  List<Object?> get props => [date];
}

final class PrivateLabelSyncRequested extends PrivateLabelEvent {
  /// Manual syncs show feedback even when nothing could be uploaded.
  final bool manual;

  const PrivateLabelSyncRequested({this.manual = false});

  @override
  List<Object?> get props => [manual];
}

final class PrivateLabelDateSelected extends PrivateLabelEvent {
  /// `yyyy-MM-dd`
  final String date;

  const PrivateLabelDateSelected(this.date);

  @override
  List<Object?> get props => [date];
}
