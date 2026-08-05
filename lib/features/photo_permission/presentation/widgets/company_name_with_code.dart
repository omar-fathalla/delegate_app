import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CompanyNameWithCode extends StatelessWidget {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final TextStyle? style;

  const CompanyNameWithCode({
    super.key,
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      // Caching is handled by Firestore's offline cache automatically for read-heavy operations,
      // but if we want to avoid flicker, we just show the companyName while loading.
      future: FirebaseFirestore.instance
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .get(const GetOptions(source: Source.cache)) // try cache first to avoid flicker
          .catchError((_) => FirebaseFirestore.instance
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .get()),
      builder: (context, snapshot) {
        String display = companyName;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            final code = data['companyCodeInOrg']?.toString() ?? data['code']?.toString();
            if (code != null && code.isNotEmpty) {
              display = '$companyName - كود: $code';
            }
          }
        }
        return Text(
          display,
          style: style,
        );
      },
    );
  }
}
