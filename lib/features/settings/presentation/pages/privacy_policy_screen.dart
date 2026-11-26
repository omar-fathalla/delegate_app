import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // TAS-358 (F-18): the official BackButton (named for screen readers),
    // Card.filled sections, text from the textTheme, contact rows as
    // ListTiles with the card-icon rule (primary + onPrimary).
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    Widget section(IconData icon, String title, String description) =>
        Card.filled(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(TashilSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: cs.primary, size: 20),
                    const SizedBox(width: TashilSpacing.sm),
                    Expanded(
                      child: Text(
                        title,
                        style: tt.titleSmall?.copyWith(color: cs.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TashilSpacing.md),
                Text(
                  description,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );

    Widget contact(
      IconData icon,
      String title,
      String value, {
      VoidCallback? onTap,
    }) => ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(TashilSpacing.sm),
        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        child: Icon(icon, color: cs.onPrimary, size: 20),
      ),
      title: Text(title),
      // URL / e-mail / phone are LTR runs (bidi fix in RTL).
      subtitle: Text(value, textDirection: TextDirection.ltr),
      trailing: onTap == null ? null : const Icon(Icons.open_in_new),
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const BackButton(),
        title: Text(l10n.privacyPolicy),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: TashilSpacing.page,
            vertical: TashilSpacing.lg,
          ),
          children: [
            Card.filled(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(TashilSpacing.lg),
                child: Text(
                  l10n.privacyPolicyDesc,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: TashilSpacing.lg),
            section(Icons.location_on, l10n.locationData, l10n.locationDataDesc),
            const SizedBox(height: TashilSpacing.lg),
            section(Icons.camera_alt, l10n.cameraAccess, l10n.cameraAccessDesc),
            const SizedBox(height: TashilSpacing.lg),
            section(Icons.security, l10n.dataSecurity, l10n.dataSecurityDesc),
            const SizedBox(height: TashilSpacing.xl),
            Text(l10n.contactUs, style: tt.titleMedium),
            const SizedBox(height: TashilSpacing.md),
            Card.filled(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  contact(
                    Icons.language,
                    l10n.website,
                    l10n.swPointWebsite,
                    onTap: () => _launchURL(l10n.swPointWebsite),
                  ),
                  const Divider(height: 1),
                  contact(Icons.email, l10n.emailAddress, l10n.swPointEmail),
                  const Divider(height: 1),
                  contact(
                    Icons.location_city,
                    l10n.egyptOffice,
                    l10n.swPointEgyptPhone,
                  ),
                  const Divider(height: 1),
                  contact(Icons.chat_bubble, l10n.uaeOffice, l10n.swPointUaePhone),
                ],
              ),
            ),
            const SizedBox(height: TashilSpacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    await launchUrl(url);
  }
}
