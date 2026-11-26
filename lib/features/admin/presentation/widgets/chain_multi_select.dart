import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// Multi-select chain picker with «اختيار الكل» for the add-delegate form.
class ChainMultiSelect extends StatelessWidget {
  const ChainMultiSelect({
    super.key,
    required this.chains,
    required this.selectedUids,
    required this.onChanged,
    this.duplicateUids = const {},
    this.maxSelection,
  });

  final List<ChainOption> chains;
  final Set<String> selectedUids;
  final ValueChanged<Set<String>> onChanged;
  final Set<String> duplicateUids;
  final int? maxSelection;

  static const selectAllKey = Key('chain_select_all');
  static Key optionKey(String uid) => Key('chain_option_$uid');
  static const warningKey = Key('chain_duplicate_warning');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final availableIds = chains.map((c) => c.uid).toSet();
    final allSelected =
        availableIds.isNotEmpty && availableIds.difference(selectedUids).isEmpty;
    final result = partitionSelectedChains(
      all: chains,
      selectedUids: selectedUids,
      duplicateUids: duplicateUids,
      max: maxSelection,
    );
    final warning = result.warningAr;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.corporate_fare_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.chainPickerTitle ?? 'المنظمة / السلسلة التجارية المستهدفة',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n?.chainPickerOneSubscriptionNote ??
                  'طلب واحد، موافقة واحدة، واشتراك واحد. لا تُحتسب رسوم لكل سلسلة.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: selectAllKey,
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n?.chainPickerSelectAll ?? 'اختيار الكل',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              value: allSelected,
              tristate: false,
              onChanged: chains.isEmpty
                  ? null
                  : (_) => onChanged(toggleSelectAll(all: chains, selectedUids: selectedUids)),
            ),
            const Divider(height: 8),
            ...chains.map((chain) {
              final selected = selectedUids.contains(chain.uid);
              final max = maxSelection;
              final atCap = !selected && max != null && result.kept.length >= max
                  && !duplicateUids.contains(chain.uid);
              return CheckboxListTile(
                key: optionKey(chain.uid),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(chain.name, style: const TextStyle(fontSize: 13)),
                value: selected,
                onChanged: atCap
                    ? null
                    : (checked) {
                        final next = {...selectedUids};
                        if (checked == true) {
                          next.add(chain.uid);
                        } else {
                          next.remove(chain.uid);
                        }
                        onChanged(next);
                      },
              );
            }),
            if (warning != null) ...[
              const SizedBox(height: 8),
              Text(
                key: warningKey,
                warning,
                style: TextStyle(fontSize: 12.5, color: colorScheme.error, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
