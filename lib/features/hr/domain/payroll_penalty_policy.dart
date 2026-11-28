/// TAS-308: which penalty statuses the monthly payroll deducts.
///
/// Penalties are stored with upper-case workflow statuses (see
/// `PenaltyStatus.toFirestoreString`). A penalty counts once it is issued:
/// ISSUED, ACKNOWLEDGED (the delegate was notified) or DEDUCTED. Pending,
/// rejected, disputed and cancelled penalties are not deducted. The old
/// lower-case `approved` / `applied` values are still accepted for legacy docs.
bool isPayrollDeductiblePenaltyStatus(Object? status) {
  final s = (status ?? '').toString().trim().toUpperCase();
  if (s.isEmpty) return false;
  const deductible = {'ISSUED', 'ACKNOWLEDGED', 'DEDUCTED', 'APPLIED'};
  if (deductible.contains(s)) return true;
  // Legacy: "approved", "approved_by_gm", ... (but never "REJECTED_..." etc.).
  return s.startsWith('APPROVED');
}

/// TAS-365: whether a penalty document belongs to the payroll month
/// [year]/[month]. A penalty upheld after a dispute carries `deductionMonth`
/// ("YYYY-MM", the decision month, user decision 2026-11-27) and is deducted
/// in that month. Every other penalty counts in the month of `createdAt`
/// (a [DateTime], or anything with `toDate()` such as a Firestore Timestamp).
/// A document with neither counts (as before).
bool isPenaltyInPayrollMonth(
  Map<String, dynamic> data, {
  required int year,
  required int month,
}) {
  final dm = (data['deductionMonth'] ?? '').toString().trim();
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(dm);
  if (m != null) {
    return int.parse(m.group(1)!) == year && int.parse(m.group(2)!) == month;
  }
  final raw = data['createdAt'];
  DateTime? created;
  if (raw is DateTime) {
    created = raw;
  } else if (raw != null) {
    try {
      created = (raw as dynamic).toDate() as DateTime;
    } catch (_) {
      created = null;
    }
  }
  if (created == null) return true;
  return created.year == year && created.month == month;
}
