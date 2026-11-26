// TAS-112: country picker shown at the start of a phone field (the left side
// in the Arabic layout, as the field's suffix). Egypt is the default.
import 'package:delegate_app/features/auth/domain/phone_country.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

class PhoneCountryPicker extends StatelessWidget {
  const PhoneCountryPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final PhoneCountry value;
  final ValueChanged<PhoneCountry> onChanged;
  final bool enabled;

  static String nameOf(AppLocalizations l10n, PhoneCountry c) =>
      c == PhoneCountry.egypt ? l10n.countryEgypt : l10n.countryUae;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<PhoneCountry>(
      key: const ValueKey('phone_country_picker'),
      enabled: enabled,
      tooltip: l10n.phoneCountryLabel,
      initialValue: value,
      onSelected: onChanged,
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      itemBuilder: (_) => [
        for (final c in PhoneCountry.values)
          PopupMenuItem<PhoneCountry>(
            key: ValueKey('phone_country_${c.name}'),
            value: c,
            child: Row(
              children: [
                Icon(Icons.public_rounded, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(nameOf(l10n, c))),
                Text(c.dialCode, textDirection: TextDirection.ltr),
                if (c == value) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 20, color: cs.primary),
                ],
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 1, height: 24, color: cs.outlineVariant),
            const SizedBox(width: 8),
            Text(
              value.dialCode,
              key: const ValueKey('phone_country_dial_code'),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 16, color: cs.onSurface, fontWeight: FontWeight.w600),
            ),
            Icon(Icons.expand_more_rounded, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
