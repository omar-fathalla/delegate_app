import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a supervisor's floor inspection / verification check
class FloorVerificationItem {
  final String delegateId;
  final String branchName;
  final String date; // YYYY-MM-DD
  final String status; // 'verified' | 'missing'
  final DateTime timestamp;
  final String verifiedBy;
  final String verifierName;

  const FloorVerificationItem({
    required this.delegateId,
    required this.branchName,
    required this.date,
    required this.status,
    required this.timestamp,
    required this.verifiedBy,
    required this.verifierName,
  });

  bool get isVerified => status == 'verified';
  bool get isMissing => status == 'missing';

  Map<String, dynamic> toJson() => {
        'delegateId': delegateId,
        'branchName': branchName,
        'date': date,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        'verifiedBy': verifiedBy,
        'verifierName': verifierName,
      };

  factory FloorVerificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    final rawTs = json['timestamp'];
    if (rawTs is Timestamp) {
      parsedTime = rawTs.toDate();
    } else if (rawTs is String) {
      parsedTime = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      parsedTime = DateTime.now();
    }

    return FloorVerificationItem(
      delegateId: json['delegateId'] as String? ?? '',
      branchName: json['branchName'] as String? ?? '',
      date: json['date'] as String? ?? '',
      status: json['status'] as String? ?? 'verified',
      timestamp: parsedTime,
      verifiedBy: json['verifiedBy'] as String? ?? '',
      verifierName: json['verifierName'] as String? ?? '',
    );
  }

  FloorVerificationItem copyWith({
    String? delegateId,
    String? branchName,
    String? date,
    String? status,
    DateTime? timestamp,
    String? verifiedBy,
    String? verifierName,
  }) {
    return FloorVerificationItem(
      delegateId: delegateId ?? this.delegateId,
      branchName: branchName ?? this.branchName,
      date: date ?? this.date,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifierName: verifierName ?? this.verifierName,
    );
  }
}
