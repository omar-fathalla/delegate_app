/// TAS-270: Arabic labels for the sector keys a task can be assigned to.
/// Some tasks carry the raw key (e.g. `all_marketing_promotion`) as their
/// `assignedToName`, which the task list used to show as-is.
const Map<String, String> taskSectorAssigneeLabels = {
  'all': 'جميع المناديب',
  'all_branch_marketing': 'قطاع تسويق الفروع',
  'all_marketing_promotion': 'قطاع تسويق العروض',
  'all_company_supervisors': 'جميع مشرفي الشركة',
};

/// The text to show for a task's assignee: a sector label when the task is
/// assigned to a sector (or its stored name is a raw sector key), otherwise
/// the stored person name.
String taskAssigneeLabel({
  required String assignedTo,
  required String assignedToName,
}) {
  final name = assignedToName.trim();
  final byName = taskSectorAssigneeLabels[name];
  if (byName != null) return byName;
  final bySector = taskSectorAssigneeLabels[assignedTo.trim()];
  if (bySector != null) return bySector;
  return name.isNotEmpty ? name : assignedTo.trim();
}
