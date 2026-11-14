import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/network/connectivity_status.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

/// M3 offline banner: shows when there is no connection, with the last
/// time we were online and a retry action. Collapses with a size animation.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final _status = ConnectivityStatus.instance;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _status.start();
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    final online = await _status.recheck();
    if (!mounted) return;
    setState(() => _checking = false);
    if (online) widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ValueListenableBuilder<bool>(
      valueListenable: _status.isOffline,
      builder: (context, offline, _) {
        return AnimatedSize(
          duration: reduce ? Duration.zero : AppMotionDurations.medium1,
          curve: AppMotionCurves.emphasized,
          child: !offline
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: cs.secondaryContainer,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          Icon(Symbols.cloud_off_rounded,
                              color: cs.onSecondaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ValueListenableBuilder<DateTime?>(
                              valueListenable: _status.lastOnlineAt,
                              builder: (context, at, _) {
                                final locale =
                                    Localizations.localeOf(context).toString();
                                final sub = at == null
                                    ? l10n.offlineNoSyncYet
                                    : l10n.offlineLastSync(
                                        DateFormat.jm(locale).format(at));
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(l10n.offlineBannerTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                color: cs.onSecondaryContainer)),
                                    Text(sub,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: cs.onSecondaryContainer)),
                                  ],
                                );
                              },
                            ),
                          ),
                          TextButton(
                            onPressed: _checking ? null : _retry,
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
