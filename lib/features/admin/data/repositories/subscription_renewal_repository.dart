import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';

/// Renewal (طلب تجديد) for a company supervisor's expired delegates.
///
/// UI-agnostic: the «تجديد المناديب» page uses it with a multi-select; a
/// per-row button can call [submitRenewal] with a single uid.
class SubscriptionRenewalRepository {
  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  SubscriptionRenewalRepository({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _clock = clock ?? (() => DateTime.now().toUtc());

  CollectionReference<Map<String, dynamic>> get _requests => _firestore.collection('delegate_requests');

  /// Suspended (subscription expired) app-added delegates of [companyUID]
  /// across every organization/chain of that company.
  Future<Either<Failure, List<RenewableDelegate>>> loadRenewableDelegates({
    required String companyUID,
  }) async {
    if (companyUID.trim().isEmpty) {
      return const Left(ServerFailure('لا توجد شركة مرتبطة بحسابك.'));
    }
    try {
      final regs = await _requests
          .where('companyUID', isEqualTo: companyUID)
          .where('requestType', isEqualTo: kRequestTypeNewDelegate)
          .where('status', isEqualTo: 'approved')
          .get();
      final pending = await _pendingRenewalsByUid(companyUID: companyUID);
      final out = <RenewableDelegate>[];
      for (final reg in regs.docs) {
        final r = reg.data();
        if ((r['supervisorUid'] ?? '').toString().isEmpty) continue;
        if ((r['existingDelegateUid'] ?? '').toString().isNotEmpty) continue;
        final org = (r['organizationUID'] ?? '').toString();
        if (org.isEmpty) continue;
        final snap = await _firestore
            .collection('organizations')
            .doc(org)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .doc(reg.id)
            .get();
        final d = snap.data();
        if (d == null) continue;
        if (d['status'] != 'suspended' || d['statusReason'] != kSubscriptionExpiredReason) continue;
        out.add(RenewableDelegate(
          uid: reg.id,
          fullName: (d['fullName'] ?? r['fullName'] ?? '').toString(),
          phoneNumber: (d['phoneNumber'] ?? r['phoneNumber'] ?? '').toString(),
          organizationName: (d['organizationName'] ?? r['organizationName'] ?? '').toString(),
          delegatePublicId: d['delegatePublicId']?.toString(),
          pendingRenewalRequestId: pending[reg.id],
        ));
      }
      out.sort((a, b) => a.fullName.compareTo(b.fullName));
      return Right(out);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل المناديب المطلوب تجديدهم: $e'));
    }
  }

  /// uid -> id of an open (unpaid, not failed) renewal for the current period.
  Future<Map<String, String>> _pendingRenewalsByUid({
    required String companyUID,
  }) async {
    final period = SubscriptionCycleHelper.getCycleCode(_clock());
    final snap = await _requests
        .where('companyUID', isEqualTo: companyUID)
        .where('requestType', isEqualTo: kRequestTypeRenewal)
        .where('status', isEqualTo: 'pending')
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['periodCode'] != period) continue;
      if (data['paymentStatus'] != 'pending') continue;
      for (final uid in (data['coveredDelegateUids'] as List? ?? const [])) {
        out[uid.toString()] = doc.id;
      }
    }
    return out;
  }

  /// Creates ONE renewal request for the selected delegates (one Paymob
  /// payment for the total). Returns the request id.
  Future<Either<Failure, String>> submitRenewal({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required String companyUID,
    required String companyName,
    required String organizationUID,
    required String organizationName,
    required List<RenewableDelegate> delegates,
  }) async {
    if (delegates.isEmpty) {
      return const Left(ServerFailure('اختر مندوباً واحداً على الأقل للتجديد.'));
    }
    if (delegates.length > SubscriptionCycleHelper.maxDelegatesPerRenewal) {
      return Left(ServerFailure(
        'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب تجديد واحد. '
        'اختر جزءاً منهم الآن وجدّد الباقي في طلب لاحق.',
      ));
    }
    final now = _clock();
    if (SubscriptionCycleHelper.isFreePromotionActive(now, companyUID)) {
      return const Left(ServerFailure('لا حاجة للتجديد خلال فترة العرض المجاني (حتى 31/12/2026).'));
    }
    final awaiting = delegates.where((d) => d.isAwaitingPayment).map((d) => d.fullName).toList();
    if (awaiting.isNotEmpty) {
      return Left(ServerFailure('يوجد طلب تجديد بانتظار الدفع لكل من: ${awaiting.join('، ')}'));
    }
    try {
      final fee = SubscriptionCycleHelper.getProratedSubscriptionFee(now, companyUID);
      final items = delegates.map((d) => RenewalItem(uid: d.uid, fullName: d.fullName, fee: fee)).toList();
      final total = SubscriptionCycleHelper.totalFor(items.length, now, companyUID);
      final docRef = _requests.doc();
      final request = DelegateSubscriptionRequest(
        id: docRef.id,
        supervisorUid: supervisorUid,
        supervisorName: supervisorName,
        supervisorPhone: supervisorPhone,
        companyUID: companyUID,
        companyName: companyName,
        organizationUID: organizationUID,
        organizationName: organizationName,
        firstName: '',
        secondName: '',
        thirdName: '',
        fullName: items.length == 1 ? items.first.fullName : 'تجديد ${items.length} مناديب',
        phoneNumber: '',
        nationalId: '',
        profileImageUrl: '',
        nationalIdFrontUrl: '',
        nationalIdBackUrl: '',
        paymentMethod: SubscriptionPaymentMethod.paymob,
        subscriptionCycle: SubscriptionCycleHelper.getCycleCode(now),
        cycleStartDate: SubscriptionCycleHelper.getCycleStartDate(now),
        cycleEndDate: SubscriptionCycleHelper.getCycleEndDate(now),
        fee: total,
        remainingMonths: SubscriptionCycleHelper.getRemainingMonthsInCycle(now),
        status: SubscriptionRequestStatus.pending,
        requestType: kRequestTypeRenewal,
        createdAt: now,
        paymentStatus: SubscriptionPaymentStatus.pending,
        coveredDelegateUids: items.map((i) => i.uid).toList(),
        items: items,
      );
      await docRef.set({
        ...request.toMap(),
        'periodStart': SubscriptionCycleHelper.periodStartDay(now),
        'periodEnd': SubscriptionCycleHelper.periodEndDay(now),
        'createdAtServer': FieldValue.serverTimestamp(),
      });
      return Right(docRef.id);
    } catch (e) {
      return Left(ServerFailure('فشل إنشاء طلب التجديد: $e'));
    }
  }

  /// Lets the supervisor drop an unpaid renewal (e.g. to change the selection).
  Future<Either<Failure, void>> cancelRenewal(String requestId) async {
    try {
      final ref = _requests.doc(requestId);
      final snap = await ref.get();
      final data = snap.data();
      if (data == null) return const Left(ServerFailure('طلب التجديد غير موجود.'));
      if (data['paymentStatus'] == 'paid') {
        return const Left(ServerFailure('لا يمكن إلغاء طلب تم دفعه.'));
      }
      await ref.update({'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل إلغاء طلب التجديد: $e'));
    }
  }

  /// Live payment state of a renewal (set to paid/failed by the server only).
  Stream<SubscriptionPaymentStatus> watchPaymentStatus(String requestId) => _requests
      .doc(requestId)
      .snapshots()
      .map((s) => SubscriptionPaymentStatusX.parse(s.data()?['paymentStatus']));
}
