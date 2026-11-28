import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:delegate_app/features/branch_reports/domain/branch_location_report.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Why a report could not be sent, in words the delegate can act on.
class BranchReportException implements Exception {
  const BranchReportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Which reports a staff member works on (TAS-397, user decision 28 Nov).
enum BranchReportViewer {
  /// Company supervisor (staff account, company admin roles): its company's
  /// reports; forwards or rejects open ones.
  companySupervisor,

  /// Chain admin: forwarded reports of its chain; closes them.
  chainAdmin,

  /// Super admin / technical support: every forwarded report; closes them.
  globalStaff,

  /// Anyone else (HR, accountant, a delegate with position supervisor, ...).
  none;

  static BranchReportViewer of(Delegate d) => switch (d.role) {
    UserRole.admin => BranchReportViewer.companySupervisor,
    UserRole.organizationAdmin => BranchReportViewer.chainAdmin,
    UserRole.superAdmin ||
    UserRole.technicalSupport => BranchReportViewer.globalStaff,
    _ => BranchReportViewer.none,
  };
}

/// Firestore access for «مكان الفرع غلط» reports. Nothing here writes a
/// branch: fixing the branch stays a manual edit on the branches screens.
class BranchLocationReportRepository {
  BranchLocationReportRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(kBranchLocationReportsCollection);

  /// Files (or refiles, once the old one is closed) the delegate's report.
  /// `set` without merge: a reopened report starts clean, and the rules
  /// refuse it while the previous one is still open or forwarded.
  Future<void> submit(NewBranchLocationReport r) async {
    try {
      await _col.doc(r.id).set({
        ...r.toFields(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const BranchReportException(
          'عندك بلاغ مفتوح عن الفرع ده. استنى رد المشرف.',
        );
      }
      throw const BranchReportException(
        'البلاغ ماتبعتش. اتأكد من النت وجرّب تاني.',
      );
    }
  }

  /// The reports [viewer] works on, newest first.
  Stream<List<BranchLocationReport>> watch(Delegate viewer) {
    final Query<Map<String, dynamic>> q;
    switch (BranchReportViewer.of(viewer)) {
      case BranchReportViewer.companySupervisor:
        if (viewer.companyUID.trim().isEmpty) return Stream.value(const []);
        q = _col.where('companyUID', isEqualTo: viewer.companyUID.trim());
      case BranchReportViewer.chainAdmin:
        if (viewer.organizationUID.trim().isEmpty) {
          return Stream.value(const []);
        }
        q = _col
            .where('organizationUID', isEqualTo: viewer.organizationUID.trim())
            .where('status', isEqualTo: BranchReportStatus.forwarded.name);
      case BranchReportViewer.globalStaff:
        q = _col.where('status', isEqualTo: BranchReportStatus.forwarded.name);
      case BranchReportViewer.none:
        return Stream.value(const []);
    }
    return q.limit(200).snapshots().map((s) {
      final list = [
        for (final d in s.docs) BranchLocationReport.fromMap(d.id, d.data()),
      ];
      // Company scoping again in memory (AGENTS.md: dual-layer).
      if (BranchReportViewer.of(viewer) ==
          BranchReportViewer.companySupervisor) {
        list.removeWhere((r) => r.companyUID != viewer.companyUID.trim());
      }
      list.sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  /// Company supervisor: send an open report to whoever edits branches.
  Future<void> forward(String reportId, Delegate reviewer) =>
      _col.doc(reportId).update({
        'status': BranchReportStatus.forwarded.name,
        'reviewedBy': reviewer.uid,
        'reviewedByName': reviewer.fullName,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Company supervisor rejects an open report, or the chain admin /
  /// global staff reject a forwarded one; always with a reason.
  Future<void> reject(
    BranchLocationReport report,
    Delegate reviewer,
    String reason,
  ) {
    final r = reason.trim();
    if (report.status == BranchReportStatus.open) {
      return _col.doc(report.id).update({
        'status': BranchReportStatus.rejected.name,
        'rejectReason': r,
        'reviewedBy': reviewer.uid,
        'reviewedByName': reviewer.fullName,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return _col.doc(report.id).update({
      'status': BranchReportStatus.rejected.name,
      'rejectReason': r,
      'fixedBy': reviewer.uid,
      'fixedByName': reviewer.fullName,
      'fixedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Chain admin / global staff: the branch was edited by hand; close it.
  Future<void> markFixed(String reportId, Delegate fixer, {String note = ''}) =>
      _col.doc(reportId).update({
        'status': BranchReportStatus.fixed.name,
        'fixedBy': fixer.uid,
        'fixedByName': fixer.fullName,
        'fixedAt': FieldValue.serverTimestamp(),
        if (note.trim().isNotEmpty) 'fixNote': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
