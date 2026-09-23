import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/wallet/domain/entities/user_wallet_entity.dart';

class UserWalletModel extends UserWalletEntity {
  const UserWalletModel({
    required super.userId,
    required super.userName,
    super.userPhone = '',
    super.userRole = '',
    super.companyName = '',
    super.companyUID = '',
    super.currentBalance = 0.0,
    super.totalAllocated = 0.0,
    super.totalPaid = 0.0,
    super.monthlyAllocation = 0.0,
    super.isWalletEnabled = false,
    super.isInternalOnly = true,
    super.notes = '',
    super.lastPeriodKey,
    super.updatedAt,
    super.updatedBy,
  });

  factory UserWalletModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return UserWalletModel.fromMap(data, doc.id);
  }

  factory UserWalletModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? updated;
    if (map['updatedAt'] != null) {
      if (map['updatedAt'] is Timestamp) {
        updated = (map['updatedAt'] as Timestamp).toDate();
      } else if (map['updatedAt'] is String) {
        updated = DateTime.tryParse(map['updatedAt']);
      }
    }

    return UserWalletModel(
      userId: docId,
      userName: map['userName']?.toString() ?? '',
      userPhone: map['userPhone']?.toString() ?? '',
      userRole: map['userRole']?.toString() ?? '',
      companyName: map['companyName']?.toString() ?? '',
      companyUID: map['companyUID']?.toString() ?? '',
      currentBalance: (map['currentBalance'] as num?)?.toDouble() ?? 0.0,
      totalAllocated: (map['totalAllocated'] as num?)?.toDouble() ?? 0.0,
      totalPaid: (map['totalPaid'] as num?)?.toDouble() ?? 0.0,
      monthlyAllocation: (map['monthlyAllocation'] as num?)?.toDouble() ?? 0.0,
      isWalletEnabled: (map['isWalletEnabled'] as bool?) ?? false,
      isInternalOnly: (map['isInternalOnly'] as bool?) ?? true,
      notes: map['notes']?.toString() ?? '',
      lastPeriodKey: map['lastPeriodKey']?.toString(),
      updatedAt: updated,
      updatedBy: map['updatedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'userRole': userRole,
      'companyName': companyName,
      'companyUID': companyUID,
      'currentBalance': currentBalance,
      'totalAllocated': totalAllocated,
      'totalPaid': totalPaid,
      'monthlyAllocation': monthlyAllocation,
      'isWalletEnabled': isWalletEnabled,
      'isInternalOnly': isInternalOnly,
      'notes': notes,
      'lastPeriodKey': lastPeriodKey,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  factory UserWalletModel.fromEntity(UserWalletEntity entity) {
    return UserWalletModel(
      userId: entity.userId,
      userName: entity.userName,
      userPhone: entity.userPhone,
      userRole: entity.userRole,
      companyName: entity.companyName,
      companyUID: entity.companyUID,
      currentBalance: entity.currentBalance,
      totalAllocated: entity.totalAllocated,
      totalPaid: entity.totalPaid,
      monthlyAllocation: entity.monthlyAllocation,
      isWalletEnabled: entity.isWalletEnabled,
      isInternalOnly: entity.isInternalOnly,
      notes: entity.notes,
      lastPeriodKey: entity.lastPeriodKey,
      updatedAt: entity.updatedAt,
      updatedBy: entity.updatedBy,
    );
  }
}

class WalletTransactionModel extends WalletTransactionEntity {
  const WalletTransactionModel({
    required super.id,
    required super.userId,
    required super.type,
    required super.amount,
    required super.balanceBefore,
    required super.balanceAfter,
    super.periodKey,
    super.notes = '',
    super.createdBy = '',
    super.createdByName = '',
    required super.createdAt,
  });

  factory WalletTransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return WalletTransactionModel.fromMap(data, doc.id);
  }

  factory WalletTransactionModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime created = DateTime.now();
    if (map['createdAt'] != null) {
      if (map['createdAt'] is Timestamp) {
        created = (map['createdAt'] as Timestamp).toDate();
      } else if (map['createdAt'] is String) {
        created = DateTime.tryParse(map['createdAt']) ?? DateTime.now();
      }
    }

    final typeStr = map['type']?.toString().toLowerCase() ?? 'allocation';
    WalletTransactionType type = WalletTransactionType.allocation;
    if (typeStr == 'payout') {
      type = WalletTransactionType.payout;
    } else if (typeStr == 'adjustment') {
      type = WalletTransactionType.adjustment;
    } else if (typeStr == 'monthlyrenewal' || typeStr == 'monthly_renewal') {
      type = WalletTransactionType.monthlyRenewal;
    }

    return WalletTransactionModel(
      id: docId,
      userId: map['userId']?.toString() ?? '',
      type: type,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      balanceBefore: (map['balanceBefore'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (map['balanceAfter'] as num?)?.toDouble() ?? 0.0,
      periodKey: map['periodKey']?.toString(),
      notes: map['notes']?.toString() ?? '',
      createdBy: map['createdBy']?.toString() ?? '',
      createdByName: map['createdByName']?.toString() ?? '',
      createdAt: created,
    );
  }

  Map<String, dynamic> toMap() {
    String typeStr = 'allocation';
    switch (type) {
      case WalletTransactionType.payout:
        typeStr = 'payout';
        break;
      case WalletTransactionType.adjustment:
        typeStr = 'adjustment';
        break;
      case WalletTransactionType.monthlyRenewal:
        typeStr = 'monthlyRenewal';
        break;
      case WalletTransactionType.allocation:
        typeStr = 'allocation';
        break;
    }

    return {
      'userId': userId,
      'type': typeStr,
      'amount': amount,
      'balanceBefore': balanceBefore,
      'balanceAfter': balanceAfter,
      'periodKey': periodKey,
      'notes': notes,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
