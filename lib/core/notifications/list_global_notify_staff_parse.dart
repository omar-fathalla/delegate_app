/// Parses `users` from the `listGlobalNotifyStaff` callable (TA-35).
List<Map<String, dynamic>> parseListGlobalNotifyStaffUsers(Object? raw) {
  if (raw is! List) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final row = Map<String, dynamic>.from(entry);
    final uid = (row['uid'] ?? '').toString().trim();
    if (uid.isEmpty) continue;
    final phone = (row['phoneNumber'] ?? row['phone'])?.toString();
    final role = (row['role'] ?? '').toString();
    rows.add({
      'uid': uid,
      if (phone != null && phone.trim().isNotEmpty) 'phoneNumber': phone.trim(),
      if (role.isNotEmpty) 'role': role,
    });
  }
  return rows;
}