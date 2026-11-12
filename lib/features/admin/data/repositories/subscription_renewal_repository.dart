import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/config/app_env.dart';
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
  final bool? _advanceRenewalEnabled;
  final int _advanceRenewalDays;

  SubscriptionRenewalRepository({
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
    bool? advanceRenewalEnabled,
    int? advanceRenewalDays,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _clock = clock ?? SubscriptionCycleHelper.currentTime,
       _advanceRenewalEnabled = advanceRenewalEnabled,
       _advanceRenewalDays =
           advanceRenewalDays ??
           ((advanceRenewalEnabled ?? AppEnv.isDev)
               ? SubscriptionCycleHelper.devAdvanceRenewalDays
               : SubscriptionCycleHelper.defaultAdvanceRenewalDays);

  late bool _resolvedEnabled = _advanceRenewalEnabled ?? AppEnv.isDev;
  late int _resolvedDays = _advanceRenewalDays;

  bool get _advanceFlag => _resolvedEnabled;

  bool isAdvanceRenewalOpen([DateTime? at]) =>
      SubscriptionCycleHelper.isAdvanceRenewalOpen(
        at ?? _clock(),
        enabled: _resolvedEnabled,
        days: _resolvedDays,
      );

  String currentPeriodCode([DateTime? at]) =>
      SubscriptionCycleHelper.getCycleCode(at ?? _clock());

  String nextPeriodCode([DateTime? at]) =>
      SubscriptionCycleHelper.nextCycleCode(at ?? _clock());

  /// Next period when the advance window is open, otherwise the current period.
  String targetPeriodCode([DateTime? at]) =>
      SubscriptionCycleHelper.payableCycleCode(
        at ?? _clock(),
        enabled: _resolvedEnabled,
        days: _resolvedDays,
      );

  /// Reads `config/subscriptions` unless the constructor overrode the flag.
  /// Falls back to the ENV=dev default (enabled, 60 days) or prod off.
  Future<void> refreshAdvanceConfig() async {
    if (_advanceRenewalEnabled != null) {
      _resolvedEnabled = _advanceRenewalEnabled!;
      _resolvedDays = _advanceRenewalDays;
      return;
    }
    try {
      final snap = await _firestore.doc('config/subscriptions').get();
      final data = snap.data();
      SubscriptionCycleHelper.applyConfig(
        freePromotionLastDay: data?['freePromotionLastDay']?.toString(),
      );
      if (data != null && data.containsKey('advanceRenewalEnabled')) {
        _resolvedEnabled = data['advanceRenewalEnabled'] == true;
        final n = data['advanceRenewalDays'];
        final days = n is num ? n.toInt() : 0;
        _resolvedDays = (days >= 1 && days <= 180)
            ? days
            : (_resolvedEnabled
                  ? SubscriptionCycleHelper.devAdvanceRenewalDays
                  : SubscriptionCycleHelper.defaultAdvanceRenewalDays);
        return;
      }
    } catch (_) {
      // Fall back below (deny-all rules, missing doc, network).
    }
    _resolvedEnabled = AppEnv.isDev;
    _resolvedDays = AppEnv.isDev
        ? SubscriptionCycleHelper.devAdvanceRenewalDays
        : SubscriptionCycleHelper.defaultAdvanceRenewalDays;
  }

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('delegate_requests');

  /// App-added delegates of [companyUID] that can be renewed.
  ///
  /// Always includes every app-added delegate for the current period
  /// (covered rows have [RenewableDelegate.isCovered] and a reason).
  /// During the advance window also includes a second list for the next
  /// period. A uid may appear once per period.
  Future<Either<Failure, List<RenewableDelegate>>> loadRenewableDelegates({
    required String companyUID,
    String? organizationUID,
  }) async {
    if (companyUID.trim().isEmpty) {
      return const Left(ServerFailure('لا توجد شركة مرتبطة بحسابك.'));
    }
    try {
      await refreshAdvanceConfig();
      final org = organizationUID?.trim() ?? '';
      Query<Map<String, dynamic>> regsQuery = _requests
          .where('companyUID', isEqualTo: companyUID)
          .where('requestType', isEqualTo: kRequestTypeNewDelegate)
          .where('status', isEqualTo: 'approved');
      if (org.isNotEmpty) {
        // Org-admin read rules require docOrg == caller org; the unfiltered
        // companyUID query is PERMISSION_DENIED for that role.
        regsQuery = regsQuery.where('organizationUID', isEqualTo: org);
      }
      final regs = await regsQuery.get();
      final now = _clock();
      final current = currentPeriodCode(now);
      final next = nextPeriodCode(now);
      final advance = isAdvanceRenewalOpen(now);
      final pending = await _pendingRenewalsByUid(
        companyUID: companyUID,
        organizationUID: org.isEmpty ? null : org,
        periods: {current, if (advance) next},
      );
      final eligible = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final reg in regs.docs) {
        final r = reg.data();
        if ((r['supervisorUid'] ?? '').toString().isEmpty) continue;
        if ((r['existingDelegateUid'] ?? '').toString().isNotEmpty) continue;
        final rowOrg = (r['organizationUID'] ?? '').toString();
        if (rowOrg.isEmpty) continue;
        eligible.add(reg);
      }
      const batchSize = 20;
      final out = <RenewableDelegate>[];
      for (var i = 0; i < eligible.length; i += batchSize) {
        final end = i + batchSize > eligible.length
            ? eligible.length
            : i + batchSize;
        final chunk = eligible.sublist(i, end);
        final snaps = await Future.wait(
          chunk.map((reg) {
            final rowOrg = (reg.data()['organizationUID'] ?? '').toString();
            return _firestore
                .collection('organizations')
                .doc(rowOrg)
                .collection('companies')
                .doc(companyUID)
                .collection('delegates')
                .doc(reg.id)
                .get();
          }),
        );
        for (var j = 0; j < chunk.length; j++) {
          final reg = chunk[j];
          final r = reg.data();
          final d = snaps[j].data();
          if (d == null) continue;
          RenewableDelegate row(
            String period, {
            String? pendingId,
            required bool covered,
          }) => RenewableDelegate(
            uid: reg.id,
            fullName: (d['fullName'] ?? r['fullName'] ?? '').toString(),
            phoneNumber: (d['phoneNumber'] ?? r['phoneNumber'] ?? '')
                .toString(),
            organizationName:
                (d['organizationName'] ?? r['organizationName'] ?? '')
                    .toString(),
            delegatePublicId: d['delegatePublicId']?.toString(),
            pendingRenewalRequestId: pendingId,
            periodCode: period,
            status: (d['status'] ?? '').toString(),
            statusReason: (d['statusReason'] ?? '').toString(),
            isCovered: covered,
            exclusionReason: covered ? 'مغطى بالفعل لهذه الفترة' : null,
          );
          // Current period: every app-added delegate, so the UI can select
          // many/all, filter الموقوفين / قرب ينتهي, and show covered ones
          // as excluded with a reason (L1 group renewal).
          out.add(
            row(
              current,
              pendingId: pending['${reg.id}|$current'],
              covered: _subscriptionCovers(d, current),
            ),
          );
          if (advance) {
            out.add(
              row(
                next,
                pendingId: pending['${reg.id}|$next'],
                covered: _subscriptionCovers(d, next),
              ),
            );
          }
        }
      }
      out.sort((a, b) {
        final byPeriod = a.periodCode.compareTo(b.periodCode);
        if (byPeriod != 0) return byPeriod;
        return a.fullName.compareTo(b.fullName);
      });
      return Right(out);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل المناديب المطلوب تجديدهم: $e'));
    }
  }

  bool _mapCovers(dynamic raw, String period) {
    if (raw is! Map) return false;
    final map = Map<String, dynamic>.from(raw);
    if ((map['periodCode'] ?? '').toString() != period) return false;
    final status = (map['paymentStatus'] ?? '').toString();
    return status == 'paid' || status == 'waived';
  }

  bool _subscriptionCovers(Map<String, dynamic> data, String period) {
    return _mapCovers(data['subscription'], period) ||
        _mapCovers(data['nextSubscription'], period);
  }

  /// uid|period -> id of an open (unpaid) renewal for those periods.
  Future<Map<String, String>> _pendingRenewalsByUid({
    required String companyUID,
    String? organizationUID,
    required Set<String> periods,
  }) async {
    final org = organizationUID?.trim() ?? '';
    Query<Map<String, dynamic>> pendingQuery = _requests
        .where('companyUID', isEqualTo: companyUID)
        .where('requestType', isEqualTo: kRequestTypeRenewal)
        .where('status', isEqualTo: 'pending');
    if (org.isNotEmpty) {
      pendingQuery = pendingQuery.where('organizationUID', isEqualTo: org);
    }
    final snap = await pendingQuery.get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final period = (data['periodCode'] ?? '').toString();
      if (!periods.contains(period)) continue;
      if (data['paymentStatus'] != 'pending') continue;
      for (final uid in (data['coveredDelegateUids'] as List? ?? const [])) {
        out['${uid.toString()}|$period'] = doc.id;
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
      return const Left(
        ServerFailure('اختر مندوباً واحداً على الأقل للتجديد.'),
      );
    }
    if (delegates.length > SubscriptionCycleHelper.maxDelegatesPerRenewal) {
      return Left(
        ServerFailure(
          'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب تجديد واحد. '
          'اختر جزءاً منهم الآن وجدّد الباقي في طلب لاحق.',
        ),
      );
    }
    final now = _clock();
    await refreshAdvanceConfig();
    final current = currentPeriodCode(now);
    final periods = <String>{
      for (final d in delegates)
        if (d.periodCode.trim().isNotEmpty) d.periodCode.trim() else current,
    };
    if (periods.length > 1) {
      return const Left(
        ServerFailure(
          'لا يمكن جمع تجديد الفترة الحالية والتجديد المقدَّم في طلب واحد. أكمل أحدهما ثم الآخر.',
        ),
      );
    }
    final period = periods.isEmpty ? current : periods.single;
    final isAdvancePeriod = period != current;
    if (!isAdvancePeriod &&
        SubscriptionCycleHelper.isFreePromotionActive(now, companyUID)) {
      return const Left(
        ServerFailure(
          'لا حاجة للتجديد خلال فترة العرض المجاني (حتى 31/12/2026).',
        ),
      );
    }
    final awaiting = delegates
        .where((d) => d.isAwaitingPayment)
        .map((d) => d.fullName)
        .toList();
    if (awaiting.isNotEmpty) {
      return Left(
        ServerFailure(
          'يوجد طلب تجديد بانتظار الدفع لكل من: ${awaiting.join('، ')}',
        ),
      );
    }
    try {
      // One subscription per uid, even if the caller passed the same
      // delegate once per chain.
      final unique = <String, RenewableDelegate>{};
      for (final d in delegates) {
        if (d.uid.trim().isEmpty) continue;
        unique.putIfAbsent(d.uid, () => d);
      }
      final selected = unique.values.toList();
      if (selected.isEmpty) {
        return const Left(
          ServerFailure('اختر مندوباً واحداً على الأقل للتجديد.'),
        );
      }
      final fee = SubscriptionCycleHelper.getFeeForPeriod(
        period,
        now,
        companyUID,
      );
      final items = selected
          .map((d) => RenewalItem(uid: d.uid, fullName: d.fullName, fee: fee))
          .toList();
      final total = SubscriptionCycleHelper.roundMoney(fee * items.length);
      final remaining = period == SubscriptionCycleHelper.getCycleCode(now)
          ? SubscriptionCycleHelper.getRemainingMonthsInCycle(now)
          : SubscriptionCycleHelper.monthsPerPeriod;
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
        fullName: items.length == 1
            ? items.first.fullName
            : 'تجديد ${items.length} مناديب',
        phoneNumber: '',
        nationalId: '',
        profileImageUrl: '',
        nationalIdFrontUrl: '',
        nationalIdBackUrl: '',
        paymentMethod: SubscriptionPaymentMethod.paymob,
        subscriptionCycle: period,
        cycleStartDate: SubscriptionCycleHelper.getCycleStartDateForCode(
          period,
        ),
        cycleEndDate: SubscriptionCycleHelper.getCycleEndDateForCode(period),
        fee: total,
        remainingMonths: remaining,
        status: SubscriptionRequestStatus.pending,
        requestType: kRequestTypeRenewal,
        createdAt: now,
        paymentStatus: SubscriptionPaymentStatus.pending,
        coveredDelegateUids: items.map((i) => i.uid).toList(),
        items: items,
      );
      await docRef.set({
        ...request.toMap(),
        'periodStart': SubscriptionCycleHelper.periodStartDayForCode(period),
        'periodEnd': SubscriptionCycleHelper.periodEndDayForCode(period),
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
      if (data == null)
        return const Left(ServerFailure('طلب التجديد غير موجود.'));
      if (data['paymentStatus'] == 'paid') {
        return const Left(ServerFailure('لا يمكن إلغاء طلب تم دفعه.'));
      }
      await ref.update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل إلغاء طلب التجديد: $e'));
    }
  }

  /// Live payment state of a renewal (set to paid/failed by the server only).
  Stream<SubscriptionPaymentStatus> watchPaymentStatus(String requestId) =>
      _requests
          .doc(requestId)
          .snapshots()
          .map(
            (s) => SubscriptionPaymentStatusX.parse(s.data()?['paymentStatus']),
          );

  Future<Either<Failure, RenewalReceipt?>> loadReceipt(String requestId) async {
    try {
      final snap = await _requests.doc(requestId).get();
      final data = snap.data();
      if (data == null) return const Right(null);
      return Right(_receiptFrom(requestId, data));
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل الإيصال: $e'));
    }
  }

  /// Paid renewals for this company (and org, when scoped), newest first.
  Future<Either<Failure, List<RenewalReceipt>>> loadPaidRenewals({
    required String companyUID,
    String? organizationUID,
  }) async {
    if (companyUID.trim().isEmpty) {
      return const Left(ServerFailure('لا توجد شركة مرتبطة بحسابك.'));
    }
    try {
      final org = organizationUID?.trim() ?? '';
      Query<Map<String, dynamic>> q = _requests
          .where('companyUID', isEqualTo: companyUID)
          .where('requestType', isEqualTo: kRequestTypeRenewal)
          .where('paymentStatus', isEqualTo: 'paid');
      if (org.isNotEmpty) {
        q = q.where('organizationUID', isEqualTo: org);
      }
      final snap = await q.get();
      final out = [for (final d in snap.docs) _receiptFrom(d.id, d.data())];
      out.sort((a, b) => (b.paidAt ?? '').compareTo(a.paidAt ?? ''));
      return Right(out);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل إيصالات التجديد: $e'));
    }
  }

  RenewalReceipt _receiptFrom(String id, Map<String, dynamic> data) {
    final items = <RenewalItem>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        items.add(
          RenewalItem(
            uid: (m['uid'] ?? '').toString(),
            fullName: (m['fullName'] ?? '').toString(),
            fee: (m['fee'] is num) ? (m['fee'] as num).toDouble() : 0,
          ),
        );
      }
    }
    final paymob = data['paymob'];
    String? txId;
    if (paymob is Map) {
      txId = paymob['transactionId']?.toString();
    }
    final amountRaw = data['amountPaid'] ?? data['amountDue'] ?? data['fee'];
    return RenewalReceipt(
      requestId: id,
      periodCode: (data['periodCode'] ?? data['subscriptionCycle'] ?? '')
          .toString(),
      amount: amountRaw is num ? amountRaw.toDouble() : 0,
      remainingMonths: data['remainingMonths'] is num
          ? (data['remainingMonths'] as num).toInt()
          : 0,
      items: items,
      paymentStatus: SubscriptionPaymentStatusX.parse(data['paymentStatus']),
      transactionId: (txId != null && txId.isNotEmpty) ? txId : null,
      paidAt: data['paidAt']?.toString(),
      companyName: (data['companyName'] ?? '').toString(),
      organizationName: (data['organizationName'] ?? '').toString(),
    );
  }
}
