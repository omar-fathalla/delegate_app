/// User-facing copy for [checkDelegateDuplicate].
///
/// Cross-company wording is copied from the web admin key
/// `form.nationalityIDExistsInCompany` in youssefathalla/tashil
/// `src/assets/i18n/ar.json` (line 773), used by
/// `personal-info-step.ts` (getNationalityIdErrorMessage, lines 160–164).
/// Mohamed asked to also tell the user to delete the delegate from that
/// company first, so that sentence is appended.
class DelegateDuplicateResult {
  final bool duplicate;
  final String? reason;
  final String? companyName;

  const DelegateDuplicateResult({
    required this.duplicate,
    this.reason,
    this.companyName,
  });

  factory DelegateDuplicateResult.fromMap(Map<dynamic, dynamic> data) {
    return DelegateDuplicateResult(
      duplicate: data['duplicate'] == true,
      reason: data['reason']?.toString(),
      companyName: data['companyName']?.toString(),
    );
  }

  /// Arabic message to show in the app. Returns null when not a duplicate.
  String? message() {
    if (!duplicate) return null;
    if (reason == 'another_company') {
      final name = (companyName ?? '').trim();
      if (name.isNotEmpty) {
        return 'مسجل بالفعل في شركة: $name. يرجى حذفه منها أولاً.';
      }
      return 'مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً.';
    }
    return 'يوجد مندوب بهذا الرقم القومي أو رقم الهاتف مسجل بالفعل في هذه الشركة.';
  }
}
