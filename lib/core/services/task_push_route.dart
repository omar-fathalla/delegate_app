/// Route opened when the user taps a system (or local) task push.
///
/// Returns `/tasks/<id>` when [data] carries a non-empty `taskId`, otherwise
/// null so the app stays where it is (typically home).
String? taskPushRoute(Map<String, dynamic> data) {
  final raw = data['taskId'];
  if (raw == null) return null;
  final taskId = raw.toString().trim();
  if (taskId.isEmpty) return null;
  return '/tasks/$taskId';
}
