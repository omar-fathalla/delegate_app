import 'dart:developer';

void main() {
  final data1 = {'companyCodeInOrg': 4818, 'code': '4818'};
  try {
    // We simulate what it does
    final companyCodeInOrg1 = data1['companyCodeInOrg'] ?? '';
    log("Assigning int to String? ${companyCodeInOrg1.runtimeType}");
    String s = companyCodeInOrg1 as String; // This fails!
    log(s);
  } catch (e) {
    log("Error 1: $e");
  }

  final data2 = {'code': '123'};
  try {
    final code = data2['code'] as int?; // This fails!
    log(code.toString());
  } catch (e) {
    log("Error 2: $e");
  }
}
