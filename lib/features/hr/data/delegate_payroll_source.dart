import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:delegate_app/features/hr/data/models/company_payroll_config_model.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/hr/domain/services/delegate_payroll_calculator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/foundation.dart';

/// The delegate's own payroll estimate for this month and the one before.
@immutable
class DelegatePayrollEstimate {
  const DelegatePayrollEstimate({required this.current, required this.previous});

  final DelegatePayrollItem current;
  final DelegatePayrollItem previous;
}

/// TAS-366: reads only the delegate's own documents (the rules allow
/// nothing else) and runs the same [DelegatePayrollCalculator] as the HR
/// payroll screen.
///
/// Same scoping as the HR screen: the wallet counts only when it belongs to
/// the delegate's company, and attendance / penalties of another company
/// are dropped.
class DelegatePayrollSource {
  DelegatePayrollSource(this._db);

  final FirebaseFirestore _db;

  Future<DelegatePayrollEstimate> load(Delegate delegate, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final company = delegate.companyUID;
    final currentMonth = DateTime(at.year, at.month);
    final previousMonth = DateTime(at.year, at.month - 1);

    await MissingCheckOutRule.ensureLoaded(_db);

    final results = await Future.wait<Object?>([
      _config(company),
      _wallet(delegate),
      _db
          .collection(kAttendanceCollection)
          .where('delegateId', isEqualTo: delegate.uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(previousMonth))
          .get(),
      _db
          .collection('leave_requests')
          .where('companyUID', isEqualTo: company)
          .where('delegateUid', isEqualTo: delegate.uid)
          .get(),
      _db.collection('penalties').where('targetDelegateId', isEqualTo: delegate.uid).get(),
    ]);

    final config = results[0] as CompanyPayrollConfig;
    final wallet = results[1] as Map<String, dynamic>;
    final attendance = [
      for (final d in (results[2] as QuerySnapshot<Map<String, dynamic>>).docs)
        if (d.data()['companyId'] == company) d.data(),
    ];
    final leaves = [
      for (final d in (results[3] as QuerySnapshot<Map<String, dynamic>>).docs) d.data(),
    ];
    final penalties = [
      for (final d in (results[4] as QuerySnapshot<Map<String, dynamic>>).docs)
        if (d.data()['companyId'] == company) d.data(),
    ];

    DelegatePayrollItem month(DateTime m) => DelegatePayrollCalculator.compute(
          delegate: delegate,
          config: config,
          wallet: wallet,
          attendance: attendance,
          leaves: leaves,
          penalties: penalties,
          month: m,
          now: at,
        );

    return DelegatePayrollEstimate(current: month(currentMonth), previous: month(previousMonth));
  }

  /// Company policy; the default policy when it is missing (as on the HR
  /// screen). A read error is not hidden: the estimate would be wrong.
  Future<CompanyPayrollConfig> _config(String company) async {
    if (company.isEmpty) return DelegatePayrollCalculator.defaultConfig(company);
    final doc = await _db.collection('company_payroll_configs').doc(company).get();
    if (!doc.exists || doc.data() == null) return DelegatePayrollCalculator.defaultConfig(company);
    return CompanyPayrollConfigModel.fromFirestore(doc);
  }

  Future<Map<String, dynamic>> _wallet(Delegate delegate) async {
    final doc = await _db.collection('user_wallets').doc(delegate.uid).get();
    final data = doc.data();
    if (data == null || data['companyUID'] != delegate.companyUID) return const {};
    return data;
  }
}
