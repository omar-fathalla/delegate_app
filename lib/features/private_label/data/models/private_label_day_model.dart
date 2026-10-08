import 'package:delegate_app/features/private_label/data/models/private_label_json.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';

/// Firestore: `/organizations/{organizationUID}/private_label_days/{delegateUid}_{yyyy-MM-dd}`
class PrivateLabelDayModel extends PrivateLabelDay {
  const PrivateLabelDayModel({
    required super.id,
    required super.organizationUID,
    required super.companyUID,
    required super.delegateUid,
    required super.delegateName,
    required super.date,
    required super.month,
    required super.type,
    super.auditsCount,
    super.rejectedCount,
    super.branchNames,
    super.isLocalOnly,
  });

  factory PrivateLabelDayModel.fromJson(Map<String, dynamic> json, String id) {
    return PrivateLabelDayModel(
      id: id,
      organizationUID: PrivateLabelJson.parseString(json['organizationUID']),
      companyUID: PrivateLabelJson.parseString(json['companyUID']),
      delegateUid: PrivateLabelJson.parseString(json['delegateUid']),
      delegateName: PrivateLabelJson.parseString(json['delegateName']),
      date: PrivateLabelJson.parseString(json['date']),
      month: PrivateLabelJson.parseString(json['month']),
      type: privateLabelDayTypeFromString(json['type'] as String?),
      auditsCount: PrivateLabelJson.parseInt(json['auditsCount']),
      rejectedCount: PrivateLabelJson.parseInt(json['rejectedCount']),
      branchNames: PrivateLabelJson.parseStringList(json['branchNames']),
    );
  }

  factory PrivateLabelDayModel.fromEntity(PrivateLabelDay d) {
    return PrivateLabelDayModel(
      id: d.id,
      organizationUID: d.organizationUID,
      companyUID: d.companyUID,
      delegateUid: d.delegateUid,
      delegateName: d.delegateName,
      date: d.date,
      month: d.month,
      type: d.type,
      auditsCount: d.auditsCount,
      rejectedCount: d.rejectedCount,
      branchNames: d.branchNames,
      isLocalOnly: d.isLocalOnly,
    );
  }

  /// Plain JSON (no Firestore sentinels) — safe for both local cache and server.
  Map<String, dynamic> toJson() => {
        'organizationUID': organizationUID,
        'companyUID': companyUID,
        'delegateUid': delegateUid,
        'delegateName': delegateName,
        'date': date,
        'month': month,
        'type': type.name,
        'auditsCount': auditsCount,
        'rejectedCount': rejectedCount,
        'branchNames': branchNames,
      };

  Map<String, dynamic> toLocalJson() => {'id': id, ...toJson()};

  factory PrivateLabelDayModel.fromLocalJson(Map<String, dynamic> json) =>
      PrivateLabelDayModel.fromJson(json, PrivateLabelJson.parseString(json['id']));
}
