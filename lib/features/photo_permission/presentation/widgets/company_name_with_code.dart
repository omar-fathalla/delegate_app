import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class CompanyNameWithCode extends StatelessWidget {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final TextStyle? style;
  final TextStyle? codeStyle;
  final bool twoLines;

  const CompanyNameWithCode({
    super.key,
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    this.style,
    this.codeStyle,
    this.twoLines = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    String codeLabel(String c) => l10n?.codeLabel(c) ?? 'كود: $c';
    final effectiveCodeStyle = codeStyle ??
        TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
        );

    Widget buildTwoLines(String? code) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            companyName,
            style: style ?? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (code != null && code.isNotEmpty && code != '0') ...[
            const SizedBox(height: 2),
            Text(
              codeLabel(code),
              style: effectiveCodeStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      );
    }

    if (companyCode != null && companyCode != 0) {
      if (twoLines) {
        return buildTwoLines(companyCode.toString());
      }
      return Text(
        '$companyName - ${codeLabel(companyCode.toString())}',
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    Future<String?> fetchCompanyCode() async {
      try {
        if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final code = data?['companyCodeInOrg']?.toString() ??
                data?['companyCode']?.toString() ??
                data?['code']?.toString();
            if (code != null && code.isNotEmpty) return code;
          }
        }
        if (companyUID.isNotEmpty) {
          final query = await FirebaseFirestore.instance
              .collectionGroup('companies')
              .where(FieldPath.documentId, isEqualTo: companyUID)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final data = query.docs.first.data();
            final code = data['companyCodeInOrg']?.toString() ??
                data['companyCode']?.toString() ??
                data['code']?.toString();
            if (code != null && code.isNotEmpty) return code;
          }
        }
      } catch (_) {}
      return null;
    }

    return FutureBuilder<String?>(
      future: fetchCompanyCode(),
      builder: (context, snapshot) {
        final code = snapshot.data;
        if (twoLines) {
          return buildTwoLines(code);
        }
        String display = companyName;
        if (code != null && code.isNotEmpty && code != '0') {
          display = '$companyName - ${codeLabel(code)}';
        }
        return Text(
          display,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
