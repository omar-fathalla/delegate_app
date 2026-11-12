/// Per-uploader proof-of-work photos on a task (Phase 4).
class TaskProof {
  const TaskProof({
    required this.uploaderUid,
    required this.imagePaths,
    this.uploadedByName = '',
    this.companyUID = '',
  });

  final String uploaderUid;
  final List<String> imagePaths;
  final String uploadedByName;
  final String companyUID;

  bool get isEmpty => imagePaths.isEmpty;
}
