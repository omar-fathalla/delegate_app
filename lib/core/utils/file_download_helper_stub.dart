Future<void> downloadFileImpl({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'text/csv;charset=utf-8',
  String? shareText,
}) async {
  throw UnsupportedError('Platform not supported for file download');
}
