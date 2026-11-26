import 'dart:io' show Platform;

import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Why the delegate's location check failed (TAS-283).
enum LocationFailureKind {
  /// Location services (GPS) are off on the phone.
  serviceOff,

  /// The app was refused location permission this time.
  permissionDenied,

  /// The app is permanently refused location permission.
  permissionDeniedForever,

  /// No usable position in time (weak GPS, low accuracy).
  noFix,

  /// Any other error while reading the position.
  error;

  bool get isPermission =>
      this == permissionDenied || this == permissionDeniedForever;
}

typedef OpenSettingsCallback = Future<bool> Function();

/// Help shown when the delegate's location check fails: buttons that open
/// the phone's location or app settings, plus short steps that fix most
/// GPS problems on Android phones (TAS-283).
class LocationHelpCard extends StatelessWidget {
  const LocationHelpCard({
    super.key,
    required this.kind,
    this.onRetry,
    this.isAndroid,
    this.openLocationSettings,
    this.openAppSettings,
  });

  final LocationFailureKind kind;

  /// Re-runs the location check. When null the retry button is hidden.
  final VoidCallback? onRetry;

  /// Shows the Android-only steps (Google Location Accuracy, battery).
  /// Defaults to the running platform.
  final bool? isAndroid;

  /// Defaults to [Geolocator.openLocationSettings]; injectable for tests.
  final OpenSettingsCallback? openLocationSettings;

  /// Defaults to [Geolocator.openAppSettings]; injectable for tests.
  final OpenSettingsCallback? openAppSettings;

  static bool get _platformIsAndroid => !kIsWeb && Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final android = isAndroid ?? _platformIsAndroid;
    final openLocation =
        openLocationSettings ?? Geolocator.openLocationSettings;
    final openApp = openAppSettings ?? Geolocator.openAppSettings;

    final steps = <String>[
      if (android) l10n.locHelpStepGoogleAccuracy,
      l10n.locHelpStepPermission,
      if (android) l10n.locHelpStepBattery,
      onRetry != null
          ? l10n.locHelpStepMapsRetry
          : l10n.locHelpStepMapsTryAgain,
    ];

    final appSettingsButton = FilledButton.tonalIcon(
      key: const Key('locationHelp.openAppSettings'),
      onPressed: () => openApp(),
      icon: const Icon(Symbols.app_settings_alt_rounded, size: 18),
      label: Text(l10n.locHelpOpenAppSettings),
    );
    final locationSettingsButton = kind.isPermission
        ? OutlinedButton.icon(
            key: const Key('locationHelp.openLocationSettings'),
            onPressed: () => openLocation(),
            icon: const Icon(Symbols.location_on_rounded, size: 18),
            label: Text(l10n.locHelpOpenLocationSettings),
          )
        : FilledButton.tonalIcon(
            key: const Key('locationHelp.openLocationSettings'),
            onPressed: () => openLocation(),
            icon: const Icon(Symbols.location_on_rounded, size: 18),
            label: Text(l10n.locHelpOpenLocationSettings),
          );

    return Container(
      key: const Key('locationHelpCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.help_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.locHelpTitle,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (kind.isPermission) appSettingsButton,
              locationSettingsButton,
              if (onRetry != null)
                TextButton.icon(
                  key: const Key('locationHelp.retry'),
                  onPressed: onRetry,
                  icon: const Icon(Symbols.refresh_rounded, size: 18),
                  label: Text(l10n.locHelpRetry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
