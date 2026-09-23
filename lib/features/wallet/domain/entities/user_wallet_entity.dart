import 'package:equatable/equatable.dart';

enum WalletTransactionType {
  allocation, // إيداع / تخصيص رصيد من المستحقات
  payout, // صرف / تسوية مستحقات نقدية
  adjustment, // تعديل رصيد يدوي (زيادة أو إنقاص)
  monthlyRenewal, // تغذية المستحق الشهري الدوري
}

extension WalletTransactionTypeX on WalletTransactionType {
  String get displayName {
    switch (this) {
      case WalletTransactionType.allocation:
        return 'إيداع وتخصيص مستحقات';
      case WalletTransactionType.payout:
        return 'صرف وتسوية نقدية';
      case WalletTransactionType.adjustment:
        return 'تعديل رصيد يدوي';
      case WalletTransactionType.monthlyRenewal:
        return 'تغذية المستحق الشهري';
    }
  }

  bool get isAllocation => this == WalletTransactionType.allocation;
  bool get isPayout => this == WalletTransactionType.payout;
  bool get isAdjustment => this == WalletTransactionType.adjustment;
  bool get isMonthlyRenewal => this == WalletTransactionType.monthlyRenewal;
}

class UserWalletEntity extends Equatable {
  final String userId;
  final String userName;
  final String userPhone;
  final String userRole;
  final String companyName;
  final String companyUID;
  final double currentBalance;
  final double totalAllocated;
  final double totalPaid;
  final double monthlyAllocation;
  final bool isWalletEnabled;
  final bool isInternalOnly;
  final String notes;
  final String? lastPeriodKey;
  final DateTime? updatedAt;
  final String? updatedBy;

  const UserWalletEntity({
    required this.userId,
    required this.userName,
    this.userPhone = '',
    this.userRole = '',
    this.companyName = '',
    this.companyUID = '',
    this.currentBalance = 0.0,
    this.totalAllocated = 0.0,
    this.totalPaid = 0.0,
    this.monthlyAllocation = 0.0,
    this.isWalletEnabled = false,
    this.isInternalOnly = true,
    this.notes = '',
    this.lastPeriodKey,
    this.updatedAt,
    this.updatedBy,
  });

  UserWalletEntity copyWith({
    String? userId,
    String? userName,
    String? userPhone,
    String? userRole,
    String? companyName,
    String? companyUID,
    double? currentBalance,
    double? totalAllocated,
    double? totalPaid,
    double? monthlyAllocation,
    bool? isWalletEnabled,
    bool? isInternalOnly,
    String? notes,
    String? lastPeriodKey,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return UserWalletEntity(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      userRole: userRole ?? this.userRole,
      companyName: companyName ?? this.companyName,
      companyUID: companyUID ?? this.companyUID,
      currentBalance: currentBalance ?? this.currentBalance,
      totalAllocated: totalAllocated ?? this.totalAllocated,
      totalPaid: totalPaid ?? this.totalPaid,
      monthlyAllocation: monthlyAllocation ?? this.monthlyAllocation,
      isWalletEnabled: isWalletEnabled ?? this.isWalletEnabled,
      isInternalOnly: isInternalOnly ?? this.isInternalOnly,
      notes: notes ?? this.notes,
      lastPeriodKey: lastPeriodKey ?? this.lastPeriodKey,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        userName,
        userPhone,
        userRole,
        companyName,
        companyUID,
        currentBalance,
        totalAllocated,
        totalPaid,
        monthlyAllocation,
        isWalletEnabled,
        isInternalOnly,
        notes,
        lastPeriodKey,
        updatedAt,
        updatedBy,
      ];
}

class WalletTransactionEntity extends Equatable {
  final String id;
  final String userId;
  final WalletTransactionType type;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? periodKey;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  const WalletTransactionEntity({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.periodKey,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        type,
        amount,
        balanceBefore,
        balanceAfter,
        periodKey,
        notes,
        createdBy,
        createdByName,
        createdAt,
      ];
}
