import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/wallet/data/models/user_wallet_model.dart';

abstract class WalletRemoteDataSource {
  Stream<UserWalletModel?> streamUserWallet(String userId);
  Stream<List<UserWalletModel>> streamAllWallets();
  Stream<List<WalletTransactionModel>> streamUserTransactions(String userId);
  Future<void> toggleWalletStatus({required String userId, required bool isEnabled});
  Future<void> deleteWallet({required String userId});
  Future<void> updateMonthlyAllocation({
    required String userId,
    required double monthlyAllocation,
    String? notes,
    required String adminUid,
  });
  Future<void> adjustBalance({
    required String userId,
    required double deltaAmount,
    required String reason,
    required String adminUid,
    required String adminName,
  });
  Future<void> applyMonthlyRenewal({
    required String userId,
    required String periodKey,
    required String adminUid,
    required String adminName,
    String? notes,
    double? customAmount,
  });
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
    double? monthlyAllocation,
    bool isInternalOnly = true,
  });
  Future<void> recordPayout({
    required String userId,
    required double amount,
    required String note,
    required String adminUid,
    required String adminName,
    bool? isInternalOnly,
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
  Future<void> deleteWallet({required String userId}) async {
    final transSnap = await _walletsRef.doc(userId).collection('transactions').get();
    final batch = _firestore.batch();
    for (var doc in transSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_walletsRef.doc(userId));
    await batch.commit();
  }

  @override
  Future<void> updateMonthlyAllocation({
    required String userId,
    required double monthlyAllocation,
    String? notes,
    required String adminUid,
  }) async {
    final updates = <String, dynamic>{
      'monthlyAllocation': monthlyAllocation,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    };
    if (notes != null) {
      updates['notes'] = notes;
    }
    await _walletsRef.doc(userId).set(updates, SetOptions(merge: true));
  }

  @override
  Future<void> adjustBalance({
    required String userId,
    required double deltaAmount,
    required String reason,
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
      final newBalance = (currentBalance + deltaAmount).clamp(0.0, double.infinity);

      // 1. Update wallet balance
      transaction.update(walletDocRef, {
        'currentBalance': newBalance,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      });

      // 2. Add adjustment transaction
      final transRef = walletDocRef.collection('transactions').doc();
      transaction.set(transRef, {
        'userId': userId,
        'type': 'adjustment',
        'amount': deltaAmount,
        'balanceBefore': currentBalance,
        'balanceAfter': newBalance,
        'notes': reason.trim().isNotEmpty
            ? reason.trim()
            : (deltaAmount >= 0 ? 'تعديل يدوي بالزيادة' : 'تعديل يدوي بالإنقاص'),
        'createdBy': adminUid,
        'createdByName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> applyMonthlyRenewal({
    required String userId,
    required String periodKey,
    required String adminUid,
    required String adminName,
    String? notes,
    double? customAmount,
  }) async {
    final walletDocRef = _walletsRef.doc(userId);

    await _firestore.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(walletDocRef);
      if (!docSnapshot.exists) {
        throw Exception('المحفظة غير موجودة');
      }

      final data = docSnapshot.data() as Map<String, dynamic>;
      final monthlyAllocation = (data['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
      final renewalAmount = (customAmount != null && customAmount > 0)
          ? customAmount
          : monthlyAllocation;
      if (renewalAmount <= 0) {
        throw Exception('يرجى إدخال مبلغ صحيح للإضافة أو تحديد الاستحقاق الشهري بالمحفظة أولاً');
      }

      final currentBalance = (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
      final totalAllocated = (data['totalAllocated'] as num?)?.toDouble() ?? 0.0;
      final newBalance = currentBalance + renewalAmount;
      final newTotalAllocated = totalAllocated + renewalAmount;

      // 1. Update wallet balance
      transaction.update(walletDocRef, {
        'currentBalance': newBalance,
        'totalAllocated': newTotalAllocated,
        'lastPeriodKey': periodKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      });

      // 2. Add monthlyRenewal transaction
      final transRef = walletDocRef.collection('transactions').doc();
      final renewalNote = notes?.trim().isNotEmpty == true
          ? notes!.trim()
          : 'تغذية الاستحقاق الشهري الدوري ($periodKey)';
      transaction.set(transRef, {
        'userId': userId,
        'type': 'monthlyRenewal',
        'amount': renewalAmount,
        'balanceBefore': currentBalance,
        'balanceAfter': newBalance,
        'periodKey': periodKey,
        'notes': renewalNote,
        'createdBy': adminUid,
        'createdByName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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
    double? monthlyAllocation,
    bool isInternalOnly = true,
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
      double existingMonthly = 0.0;

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        currentBalance = (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
        totalAllocated = (data['totalAllocated'] as num?)?.toDouble() ?? 0.0;
        totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
        existingMonthly = (data['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
      }

      final newBalance = currentBalance + amount;
      final newTotalAllocated = totalAllocated + amount;
      final finalMonthly = monthlyAllocation ?? (existingMonthly > 0 ? existingMonthly : amount);

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
          'monthlyAllocation': finalMonthly,
          'isWalletEnabled': true, // Auto-enable upon allocation
          'isInternalOnly': isInternalOnly,
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

    // 4. Send targeted notification ONLY if this is NOT an internal-only secret wallet
    if (!isInternalOnly) {
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
  }

  @override
  Future<void> recordPayout({
    required String userId,
    required double amount,
    required String note,
    required String adminUid,
    required String adminName,
    bool? isInternalOnly,
  }) async {
    final walletDocRef = _walletsRef.doc(userId);
    bool shouldSendNotification = false;

    await _firestore.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(walletDocRef);
      if (!docSnapshot.exists) {
        throw Exception('المحفظة غير موجودة');
      }

      final data = docSnapshot.data() as Map<String, dynamic>;
      final currentBalance = (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final docInternalOnly = (data['isInternalOnly'] as bool?) ?? true;

      // Only notify if explicitly told or if doc is not internal only
      shouldSendNotification = !(isInternalOnly ?? docInternalOnly);

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

    // 3. Send targeted notification ONLY if not internal only
    if (shouldSendNotification) {
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

  String _normalizePhone(String phone) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String normalized = phone.trim();
    normalized = normalized.replaceAll(RegExp(r'[^\d+٠-٩]'), '');
    for (int i = 0; i < arabic.length; i++) {
      normalized = normalized.replaceAll(arabic[i], english[i]);
    }
    if (normalized.startsWith('+20')) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('+2')) {
      normalized = normalized.substring(2);
    } else if (normalized.startsWith('0020')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('002')) {
      normalized = normalized.substring(3);
    }
    if (normalized.length == 10 && RegExp(r'^1[0125]').hasMatch(normalized)) {
      normalized = '0$normalized';
    }
    return normalized;
  }

  @override
  Future<List<Map<String, String>>> searchUsers(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final resultsMap = <String, Map<String, String>>{};

    // إضافة مستخدم للنتائج مع ضمان توفير كل من id و uid
    void addUserDoc(String id, Map<String, dynamic> data, {String defaultRole = ''}) {
      if (resultsMap.containsKey(id)) return;
      final name = (data['displayName'] ??
              data['fullName'] ??
              data['name'] ??
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
          .toString()
          .trim();
      final phone = (data['phoneNumber'] ?? data['phone'] ?? data['mobile'] ?? '').toString().trim();
      final role = (data['role'] ?? data['position'] ?? defaultRole).toString().trim();
      final company = (data['companyName'] ?? data['organizationName'] ?? '').toString().trim();
      final companyId = (data['companyUID'] ?? data['organizationUID'] ?? '').toString().trim();

      resultsMap[id] = {
        'id': id,
        'uid': id,
        'name': name.isNotEmpty ? name : (phone.isNotEmpty ? phone : id),
        'phone': phone,
        'role': role.isNotEmpty ? role : 'مستخدم',
        'companyName': company,
        'companyUID': companyId,
      };
    }

    try {
      // ── الاستراتيجية 1: البحث المباشر والفوري برقم الهاتف ──
      final digits = cleanQuery.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length >= 3) {
        final normalizedPhone = _normalizePhone(cleanQuery);
        final normalizedDigits = normalizedPhone.replaceAll(RegExp(r'[^\d]'), '');

        String core10 = '';
        if (normalizedDigits.length == 10 && RegExp(r'^1[0125]').hasMatch(normalizedDigits)) {
          core10 = normalizedDigits;
        } else if (normalizedDigits.length == 11 && normalizedDigits.startsWith('0')) {
          core10 = normalizedDigits.substring(1);
        } else if (normalizedDigits.length >= 12 && normalizedDigits.startsWith('20')) {
          core10 = normalizedDigits.substring(2);
        } else if (normalizedDigits.length >= 14 && normalizedDigits.startsWith('0020')) {
          core10 = normalizedDigits.substring(4);
        } else if (digits.length >= 10) {
          final stripped = digits.replaceFirst(RegExp(r'^(0020|20|\+20|\+2|0)'), '');
          if (stripped.length == 10) {
            core10 = stripped;
          }
        }

        final phoneCandidates = <String>{
          cleanQuery,
          digits,
          normalizedPhone,
          normalizedDigits,
        };

        if (core10.isNotEmpty) {
          phoneCandidates.addAll([
            core10,
            '0$core10',
            '+20$core10',
            '20$core10',
            '0020$core10',
            '+2$core10',
          ]);
        }

        final phoneFutures = <Future>[];
        for (final p in phoneCandidates) {
          if (p.isEmpty) continue;

          // 1. users: phoneNumber
          phoneFutures.add(_firestore
              .collection('users')
              .where('phoneNumber', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data());
            }
          }).catchError((_) => null));

          // 2. users: phone
          phoneFutures.add(_firestore
              .collection('users')
              .where('phone', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data());
            }
          }).catchError((_) => null));

          // 3. delegates (collectionGroup): phoneNumber
          phoneFutures.add(_firestore
              .collectionGroup('delegates')
              .where('phoneNumber', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data(), defaultRole: 'delegate');
            }
          }).catchError((_) => null));

          // 4. delegates (collectionGroup): phone
          phoneFutures.add(_firestore
              .collectionGroup('delegates')
              .where('phone', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data(), defaultRole: 'delegate');
            }
          }).catchError((_) => null));

          // 5. top-level delegates: phoneNumber
          phoneFutures.add(_firestore
              .collection('delegates')
              .where('phoneNumber', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data(), defaultRole: 'delegate');
            }
          }).catchError((_) => null));

          // 6. top-level delegates: phone
          phoneFutures.add(_firestore
              .collection('delegates')
              .where('phone', isEqualTo: p)
              .limit(5)
              .get()
              .then((snap) {
            for (var doc in snap.docs) {
              addUserDoc(doc.id, doc.data(), defaultRole: 'delegate');
            }
          }).catchError((_) => null));
        }

        await Future.wait(phoneFutures);
      }

      // ── الاستراتيجية 2: البحث ببادئة الاسم إذا كان الإدخال نصياً ──
      if (resultsMap.length < 20 && cleanQuery.length >= 2) {
        final queryEnd = '$cleanQuery\uf8ff';

        final nameQueries = [
          _firestore
              .collection('users')
              .where('displayName', isGreaterThanOrEqualTo: cleanQuery)
              .where('displayName', isLessThanOrEqualTo: queryEnd)
              .limit(10)
              .get(),
          _firestore
              .collection('users')
              .where('fullName', isGreaterThanOrEqualTo: cleanQuery)
              .where('fullName', isLessThanOrEqualTo: queryEnd)
              .limit(10)
              .get(),
          _firestore
              .collection('users')
              .where('name', isGreaterThanOrEqualTo: cleanQuery)
              .where('name', isLessThanOrEqualTo: queryEnd)
              .limit(10)
              .get(),
          _firestore
              .collectionGroup('delegates')
              .where('fullName', isGreaterThanOrEqualTo: cleanQuery)
              .where('fullName', isLessThanOrEqualTo: queryEnd)
              .limit(10)
              .get(),
          _firestore
              .collectionGroup('delegates')
              .where('firstName', isGreaterThanOrEqualTo: cleanQuery)
              .where('firstName', isLessThanOrEqualTo: queryEnd)
              .limit(10)
              .get(),
        ];

        final responses = await Future.wait(
          nameQueries.map((q) => q.catchError((_) => null as dynamic)),
        );
        for (final dynamic resp in responses) {
          if (resp is QuerySnapshot<Map<String, dynamic>>) {
            for (var doc in resp.docs) {
              addUserDoc(doc.id, doc.data());
            }
          }
        }
      }

      // ── الاستراتيجية 3: بحث احتياطي شامل في الذاكرة ──
      if (resultsMap.isEmpty) {
        final lowerQuery = cleanQuery.toLowerCase();
        final usersSnap = await _firestore.collection('users').limit(150).get();
        for (var doc in usersSnap.docs) {
          final d = doc.data();
          final name = (d['displayName'] ?? d['fullName'] ?? d['name'] ?? '').toString().toLowerCase();
          final phone = (d['phoneNumber'] ?? d['phone'] ?? '').toString();
          final role = (d['role'] ?? '').toString().toLowerCase();
          final company = (d['companyName'] ?? '').toString().toLowerCase();

          if (name.contains(lowerQuery) ||
              phone.contains(cleanQuery) ||
              role.contains(lowerQuery) ||
              company.contains(lowerQuery)) {
            addUserDoc(doc.id, d);
          }
        }

        if (resultsMap.length < 20) {
          final delSnap = await _firestore.collectionGroup('delegates').limit(150).get();
          for (var doc in delSnap.docs) {
            final d = doc.data();
            final name = (d['displayName'] ?? d['fullName'] ?? d['name'] ?? '').toString().toLowerCase();
            final phone = (d['phoneNumber'] ?? d['phone'] ?? '').toString();
            final company = (d['companyName'] ?? '').toString().toLowerCase();

            if (name.contains(lowerQuery) ||
                phone.contains(cleanQuery) ||
                company.contains(lowerQuery)) {
              addUserDoc(doc.id, d, defaultRole: 'delegate');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error searching users in wallet datasource: $e');
    }

    final list = resultsMap.values.toList();
    list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    return list;
  }
}
