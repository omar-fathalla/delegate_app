import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Blocking "update required" page (TAS-66). Shown instead of the splash
/// when [AppVersionGate] decides the running build is below the minimum.
/// It cannot be popped; the only way forward is the store.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    this.decision,
    this.openUrl = _launchExternal,
  });

  /// Defaults to the live gate decision.
  final AppVersionGateDecision? decision;

  /// Injectable for tests.
  final Future<bool> Function(Uri uri) openUrl;

  static Future<bool> _launchExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = decision ?? AppVersionGate.decision.value;
    final brand = kTashilBrandScheme;

    return PopScope(
      canPop: false,
      child: Theme(
        data: tashilAuthTheme(context),
        child: Builder(
          builder: (context) {
            final text = Theme.of(context).textTheme;
            return Scaffold(
              backgroundColor: brand.primary,
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const TashilLogoTile(size: 96),
                          const SizedBox(height: 24),
                          Icon(
                            Icons.system_update_rounded,
                            size: 40,
                            color: brand.onPrimary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.updateRequiredTitle,
                            textAlign: TextAlign.center,
                            style: text.headlineSmall?.copyWith(
                              color: brand.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.updateRequiredBody,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(
                              color: brand.onPrimary.withValues(alpha: 0.9),
                            ),
                          ),
                          if (current.minVersion.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.updateRequiredVersions(
                                current.currentVersion,
                                current.minVersion,
                              ),
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: brand.onPrimary.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          if (current.storeUrl.isNotEmpty)
                            FilledButton.icon(
                              key: const Key('update_required_store_button'),
                              style: FilledButton.styleFrom(
                                backgroundColor: brand.onPrimary,
                                foregroundColor: brand.primary,
                                minimumSize: const Size(220, 48),
                              ),
                              onPressed: () async {
                                final ok =
                                    await openUrl(Uri.parse(current.storeUrl));
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(l10n.updateRequiredOpenFailed),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: Text(l10n.updateRequiredButton),
                            )
                          else
                            Text(
                              l10n.updateRequiredNoStoreLink,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: brand.onPrimary.withValues(alpha: 0.9),
                              ),
                            ),
                          const SizedBox(height: 32),
                          TashilVersionText(
                            color: brand.onPrimary.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
