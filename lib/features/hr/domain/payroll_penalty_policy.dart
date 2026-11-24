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
