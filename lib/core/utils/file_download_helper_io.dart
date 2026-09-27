import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadFileImpl({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'text/csv;charset=utf-8',
  String? shareText,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes);

  // ignore: deprecated_member_use
  await Share.shareXFiles(
    [XFile(file.path)],
    text: shareText,
  );
}
