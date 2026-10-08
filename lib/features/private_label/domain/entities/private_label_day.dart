import 'package:equatable/equatable.dart';

/// Whether the day was worked (documentation uploaded) or registered as a rest day.
enum PrivateLabelDayType { worked, rest }

PrivateLabelDayType privateLabelDayTypeFromString(String? value) {
  return value == PrivateLabelDayType.rest.name
      ? PrivateLabelDayType.rest
      : PrivateLabelDayType.worked;
}

/// One summary document per marketer per day (`{delegateUid}_{yyyy-MM-dd}`).
///
/// This is what the monthly KPI is computed from, so the KPI never needs to
/// read every single audit document.
class PrivateLabelDay extends Equatable {
  final String id;
  final String organizationUID;
  final String companyUID;
  final String delegateUid;
  final String delegateName;

  /// `yyyy-MM-dd`
  final String date;

  /// `yyyy-MM`
  final String month;
  final PrivateLabelDayType type;
  final int auditsCount;
  final int rejectedCount;
  final List<String> branchNames;

  /// True when the day exists only on this device (audits waiting to sync).
  final bool isLocalOnly;

  const PrivateLabelDay({
    required this.id,
    required this.organizationUID,
    required this.companyUID,
    required this.delegateUid,
    required this.delegateName,
    required this.date,
    required this.month,
    required this.type,
    this.auditsCount = 0,
    this.rejectedCount = 0,
    this.branchNames = const [],
    this.isLocalOnly = false,
  });

  bool get isRest => type == PrivateLabelDayType.rest;

  /// A worked day counts as achieved when at least one audit was not rejected.
  bool get isWorkedAchieved =>
      type == PrivateLabelDayType.worked && auditsCount > rejectedCount;

  PrivateLabelDay copyWith({
    PrivateLabelDayType? type,
    int? auditsCount,
    int? rejectedCount,
    List<String>? branchNames,
    bool? isLocalOnly,
  }) {
    return PrivateLabelDay(
      id: id,
      organizationUID: organizationUID,
      companyUID: companyUID,
      delegateUid: delegateUid,
      delegateName: delegateName,
      date: date,
      month: month,
      type: type ?? this.type,
      auditsCount: auditsCount ?? this.auditsCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      branchNames: branchNames ?? this.branchNames,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
    );
  }

  @override
  List<Object?> get props => [
        id,
        organizationUID,
        companyUID,
        delegateUid,
        delegateName,
        date,
        month,
        type,
        auditsCount,
        rejectedCount,
        branchNames,
        isLocalOnly,
      ];
}
