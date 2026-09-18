import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';

abstract class WalletRemoteDataSource {
  Stream<UserWalletModel?> streamUserWallet(String userId);
  Stream<List<UserWalletModel>> streamAllWallets();
  Stream<List<WalletTransactionModel>> streamUserTransactions(String userId);
  Future<void> toggleWalletStatus({required String userId, required bool isEnabled});
  Future<void> allocateBalance({
    required String userId,
    required String userName,
    required String userPhone,
    required String userRole,
    required String companyName,
    required String companyUID,
    required double amount,
    required String periodKey,
    required String note,
    required String adminUid,
    required String adminName,
  });
  Future<void> recordPayout({
    required String userId,
    required double amount,
    required String note,
    required String adminUid,
    required String adminName,
  });
  Stream<double> streamMonthlyAllocationsTotal(String periodKey);
  Future<List<Map<String, String>>> searchUsers(String query);
}

class WalletRemoteDataSourceImpl implements WalletRemoteDataSource {
  final FirebaseFirestore _firestore;

  WalletRemoteDataSourceImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _walletsRef => _firestore.collection('user_wallets');

  @override
  Stream<UserWalletModel?> streamUserWallet(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _walletsRef.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserWalletModel.fromFirestore(doc);
    });
  }

  @override
  Stream<List<UserWalletModel>> streamAllWallets() {
    return _walletsRef
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => UserWalletModel.fromFirestore(doc)).toList();
    });
  }

  @override
  Stream<List<WalletTransactionModel>> streamUserTransactions(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _walletsRef
        .doc(userId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => WalletTransactionModel.fromFirestore(doc))
          .toList();
    });
  }

  @override
  Future<void> toggleWalletStatus({required String userId, required bool isEnabled}) async {
    await _walletsRef.doc(userId).set({
      'isWalletEnabled': isEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> allocateBalance({
    required String userId,
    required String userName,
    required String userPhone,
    required String userRole,
    required String companyName,
    required String companyUID,
    required double amount,
    required String periodKey,
    required String note,
    required String adminUid,
    required String adminName,
  }) async {
    final walletDocRef = _walletsRef.doc(userId);
    final allocationDocRef = _firestore
        .collection('monthly_collections')
        .doc(periodKey)
        .collection('allocations')
        .doc();

    await _firestore.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(walletDocRef);
      double currentBalance = 0.0;
      double totalAllocated = 0.0;
      double totalPaid = 0.0;

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        currentBalance = (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
        totalAllocated = (data['totalAllocated'] as num?)?.toDouble() ?? 0.0;
        totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
      }

      final newBalance = currentBalance + amount;
      final newTotalAllocated = totalAllocated + amount;

      // 1. Update user wallet document
      transaction.set(
        walletDocRef,
        {
          'userId': userId,
          'userName': userName,
          'userPhone': userPhone,
          'userRole': userRole,
          'companyName': companyName,
          'companyUID': companyUID,
          'currentBalance': newBalance,
          'totalAllocated': newTotalAllocated,
          'totalPaid': totalPaid,
          'isWalletEnabled': true, // Auto-enable upon allocation
          'lastPeriodKey': periodKey,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': adminUid,
        },
        SetOptions(merge: true),
      );

      // 2. Add transaction history in subcollection
      final transRef = walletDocRef.collection('transactions').doc();
      transaction.set(transRef, {
        'userId': userId,
        'type': 'allocation',
        'amount': amount,
        'balanceBefore': currentBalance,
        'balanceAfter': newBalance,
        'periodKey': periodKey,
        'notes': note.trim().isNotEmpty ? note.trim() : 'تخصيص مستحقات من الرصيد المتبقي',
        'createdBy': adminUid,
        'createdByName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Track in monthly_collections for synchronization with Collections screen
      transaction.set(allocationDocRef, {
        'userId': userId,
        'userName': userName,
        'amount': amount,
        'periodKey': periodKey,
        'notes': note.trim(),
        'createdBy': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    // 4. Send targeted in-app & push notification to the specific user only
    try {
      final formattedAmt = NumberFormat('#,##0.00', 'en_US').format(amount);
      final notifTitle = 'إيداع رصيد في محفظتك';
      final notifBody = note.trim().isNotEmpty
          ? 'تم تخصيص $formattedAmt ج.م في محفظتك المالية ($note).'
          : 'تم تخصيص $formattedAmt ج.م في محفظتك المالية بواسطة الإدارة.';

      await _firestore.collection('notifications').add({
        'delegateUid': userId, // Target ONLY this specific user
        'phoneNumber': userPhone,
        'organizationId': companyUID,
        'companyId': companyUID,
        'companyName': companyName,
        'title': notifTitle,
        'body': notifBody,
        'type': 'wallet_allocation',
        'amount': amount,
        'periodKey': periodKey,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
        'createdByName': adminName,
        'senderName': adminName,
        'senderRole': 'superAdmin',
      });
      debugPrint('Targeted wallet notification sent to $userId ($userPhone)');
    } catch (e) {
      debugPrint('Error sending wallet allocation notification: $e');
    }
  }

  @override
  Future<void> recordPayout({
    required String userId,
    required double amount,
    required String note,
    required String adminUid,
    required String adminName,
  }) async {
    final walletDocRef = _walletsRef.doc(userId);

    await _firestore.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(walletDocRef);
      if (!docSnapshot.exists) {
        throw Exception('المحفظة غير موجودة');
      }

      final data = docSnapshot.data() as Map<String, dynamic>;
      final currentBalance = (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;

      if (amount <= 0 || amount > currentBalance) {
        throw Exception('المبلغ المطلوب صرفه غير صالح أو أكبر من رصيد المحفظة الحالي ($currentBalance ج.م)');
      }

      final newBalance = (currentBalance - amount).clamp(0.0, double.infinity);
      final newTotalPaid = totalPaid + amount;

      // 1. Update wallet balance
      transaction.update(walletDocRef, {
        'currentBalance': newBalance,
        'totalPaid': newTotalPaid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      });

      // 2. Add payout transaction record
      final transRef = walletDocRef.collection('transactions').doc();
      transaction.set(transRef, {
        'userId': userId,
        'type': 'payout',
        'amount': amount,
        'balanceBefore': currentBalance,
        'balanceAfter': newBalance,
        'notes': note.trim().isNotEmpty ? note.trim() : 'تسوية وصرف مستحقات (تم التحصيل)',
        'createdBy': adminUid,
        'createdByName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    // 3. Send targeted notification to the specific user for payout
    try {
      final formattedAmt = NumberFormat('#,##0.00', 'en_US').format(amount);
      final notifTitle = 'تسوية وصرف مستحقات';
      final notifBody = note.trim().isNotEmpty
          ? 'تم تسجيل صرف مبلغ $formattedAmt ج.م من محفظتك المالية ($note).'
          : 'تم تسجيل صرف مبلغ $formattedAmt ج.م من محفظتك المالية.';

      await _firestore.collection('notifications').add({
        'delegateUid': userId, // Target ONLY this specific user
        'title': notifTitle,
        'body': notifBody,
        'type': 'wallet_payout',
        'amount': amount,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
        'createdByName': adminName,
        'senderName': adminName,
        'senderRole': 'superAdmin',
      });
      debugPrint('Targeted payout notification sent to $userId');
    } catch (e) {
      debugPrint('Error sending wallet payout notification: $e');
    }
  }

  @override
  Stream<double> streamMonthlyAllocationsTotal(String periodKey) {
    return _firestore
        .collection('monthly_collections')
        .doc(periodKey)
        .collection('allocations')
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        final amt = (doc.data()['amount'] as num?)?.toDouble() ?? 0.0;
        total += amt;
      }
      return total;
    });
  }

  @override
  Future<List<Map<String, String>>> searchUsers(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    final resultsMap = <String, Map<String, String>>{};

    try {
      // 1. Query top-level users collection
      final usersSnap = await _firestore.collection('users').limit(100).get();
      for (var doc in usersSnap.docs) {
        final d = doc.data();
        final name = (d['displayName'] ?? d['fullName'] ?? d['name'] ?? '').toString();
        final phone = (d['phoneNumber'] ?? d['phone'] ?? '').toString();
        final role = (d['role'] ?? '').toString();
        final company = (d['companyName'] ?? '').toString();
        final companyId = (d['companyUID'] ?? '').toString();

        if (cleanQuery.isEmpty ||
            name.toLowerCase().contains(cleanQuery) ||
            phone.contains(cleanQuery) ||
            company.toLowerCase().contains(cleanQuery) ||
            role.toLowerCase().contains(cleanQuery)) {
          resultsMap[doc.id] = {
            'id': doc.id,
            'name': name.isNotEmpty ? name : doc.id,
            'phone': phone,
            'role': role,
            'companyName': company,
            'companyUID': companyId,
          };
        }
      }

      // 2. Query collectionGroup delegates if needed
      if (resultsMap.length < 50) {
        final delSnap = await _firestore.collectionGroup('delegates').limit(100).get();
        for (var doc in delSnap.docs) {
          final d = doc.data();
          final name = (d['displayName'] ?? d['fullName'] ?? d['name'] ?? '').toString();
          final phone = (d['phoneNumber'] ?? d['phone'] ?? '').toString();
          final company = (d['companyName'] ?? '').toString();
          final companyId = (d['companyUID'] ?? '').toString();

          if (cleanQuery.isEmpty ||
              name.toLowerCase().contains(cleanQuery) ||
              phone.contains(cleanQuery) ||
              company.toLowerCase().contains(cleanQuery)) {
            if (!resultsMap.containsKey(doc.id)) {
              resultsMap[doc.id] = {
                'id': doc.id,
                'name': name.isNotEmpty ? name : doc.id,
                'phone': phone,
                'role': 'delegate',
                'companyName': company,
                'companyUID': companyId,
              };
            }
          }
        }
      }
    } catch (e) {
      // Ignore query errors
    }

    final list = resultsMap.values.toList();
    list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    return list;
  }
}
