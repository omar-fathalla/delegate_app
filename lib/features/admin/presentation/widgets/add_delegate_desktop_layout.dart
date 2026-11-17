import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// Desktop web pieces of «إضافة مندوب لمنظمة جديدة» (MD3 Model 1).
///
/// Only [AddDelegateFormScreen] uses these, and only when
/// [AddDelegateDesktopBreakpoints.useDesktop] is true (web, wider than the
/// HR shell's mobile breakpoint). The mobile app keeps its original layout.
class AddDelegateDesktopBreakpoints {
  AddDelegateDesktopBreakpoints._();

  /// Same cut as the HR shell: at or below this the web shows the app layout.
  static const double shellWide = 768;

  /// Two columns (form + sticky summary) from here.
  static const double twoColumns = 1024;

  /// The side navigation is expanded from here; below it is the rail.
  static const double expandedNav = 1200;

  static bool useDesktop({required bool isWeb, required double width}) =>
      isWeb && width > shellWide;
}

/// Content card used for every form section on desktop.
class AddDelegateSectionCard extends StatelessWidget {
  const AddDelegateSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// «3/10 مختارة» pill.
class AddDelegateChainCounter extends StatelessWidget {
  const AddDelegateChainCounter({
    super.key,
    required this.count,
    this.max = kMaxOrganizationsPerRequest,
  });

  final int count;
  final int max;

  static const counterKey = Key('add_delegate_chain_counter');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: counterKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count/$max مختارة',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Desktop chain picker: search + «اختيار الكل» + a 3-column checkbox grid.
///
/// Same rules as [ChainMultiSelect]: «اختيار الكل» uses [toggleSelectAll] on
/// every chain, the cap is [kMaxOrganizationsPerRequest], and the warning is
/// [ChainSelectionResult.warningAr]. Chains found as duplicates by the submit
/// check are shown disabled with a neutral note instead of a red one.
class AddDelegateChainGrid extends StatefulWidget {
  const AddDelegateChainGrid({
    super.key,
    required this.chains,
    required this.selectedUids,
    required this.onChanged,
    this.duplicateUids = const {},
    this.maxSelection = kMaxOrganizationsPerRequest,
  });

  final List<ChainOption> chains;
  final Set<String> selectedUids;
  final ValueChanged<Set<String>> onChanged;
  final Set<String> duplicateUids;
  final int maxSelection;

  static const selectAllKey = Key('chain_select_all');
  static Key optionKey(String uid) => Key('chain_option_$uid');
  static const warningKey = Key('chain_duplicate_warning');
  static const searchKey = Key('chain_search');

  @override
  State<AddDelegateChainGrid> createState() => _AddDelegateChainGridState();
}

class _AddDelegateChainGridState extends State<AddDelegateChainGrid> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final chains = widget.chains;
    final selectedUids = widget.selectedUids;
    final availableIds = chains.map((c) => c.uid).toSet();
    final allSelected =
        availableIds.isNotEmpty && availableIds.difference(selectedUids).isEmpty;
    final result = partitionSelectedChains(
      all: chains,
      selectedUids: selectedUids,
      duplicateUids: widget.duplicateUids,
      max: widget.maxSelection,
    );
    final warning = result.warningAr;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? chains
        : chains.where((c) => c.name.toLowerCase().contains(q)).toList();

    return AddDelegateSectionCard(
      icon: Symbols.storefront_rounded,
      title: l10n?.chainPickerTitle ?? 'المنظمة / السلسلة التجارية المستهدفة',
      subtitle: l10n?.chainPickerOneSubscriptionNote ??
          'طلب واحد، موافقة واحدة، واشتراك واحد. لا تُحتسب رسوم لكل سلسلة.',
      trailing: AddDelegateChainCounter(
        count: result.kept.length,
        max: widget.maxSelection,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBar(
                  key: AddDelegateChainGrid.searchKey,
                  controller: _search,
                  hintText: 'ابحث باسم السلسلة',
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor:
                      WidgetStatePropertyAll(cs.surfaceContainerHigh),
                  constraints:
                      const BoxConstraints(minHeight: 48, maxHeight: 48),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16),
                  ),
                  leading: Icon(
                    Symbols.search_rounded,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .deleteButtonTooltip,
                        icon: const Icon(Symbols.close_rounded, size: 20),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                  hintStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 14),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 12),
              _CheckRow(
                key: AddDelegateChainGrid.selectAllKey,
                label: l10n?.chainPickerSelectAll ?? 'اختيار الكل',
                value: allSelected,
                bold: true,
                onChanged: chains.isEmpty
                    ? null
                    : (_) => widget.onChanged(
                        toggleSelectAll(all: chains, selectedUids: selectedUids),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              const gap = 8.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 0,
                children: [
                  for (final chain in visible)
                    SizedBox(
                      width: itemWidth,
                      child: _chainTile(chain, result),
                    ),
                ],
              );
            },
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.info_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      key: AddDelegateChainGrid.warningKey,
                      warning,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chainTile(ChainOption chain, ChainSelectionResult result) {
    final selected = widget.selectedUids.contains(chain.uid);
    final duplicate = widget.duplicateUids.contains(chain.uid);
    final atCap = !selected &&
        result.kept.length >= widget.maxSelection &&
        !duplicate;
    return _CheckRow(
      key: AddDelegateChainGrid.optionKey(chain.uid),
      label: chain.name,
      value: selected,
      expand: true,
      trailingIcon: duplicate ? Symbols.info_rounded : null,
      onChanged: (atCap || duplicate)
          ? null
          : (checked) {
              final next = {...widget.selectedUids};
              if (checked == true) {
                next.add(chain.uid);
              } else {
                next.remove(chain.uid);
              }
              widget.onChanged(next);
            },
    );
  }
}

/// 48dp checkbox row (checkbox at the start, label after it).
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.bold = false,
    this.expand = false,
    this.trailingIcon,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool bold;
  final bool expand;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: onChanged),
            const SizedBox(width: 2),
            if (expand) Flexible(child: text) else text,
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 18, color: cs.onSurfaceVariant),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// One of the three image slots, laid out side by side on desktop.
class AddDelegateImageSlot extends StatelessWidget {
  const AddDelegateImageSlot({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.image,
    required this.onPick,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// Preview of the picked file, or null when nothing is picked yet.
  final ImageProvider? image;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = image != null;
    return Material(
      color: has ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: has ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            children: [
              SizedBox(
                height: 72,
                child: has
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _preview(cs),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 28,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              if (has)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onRemove,
                  icon: const Icon(Symbols.close_rounded, size: 18),
                  label: const Text('حذف'),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onPick,
                  icon: const Icon(Symbols.add_photo_alternate_rounded, size: 18),
                  label: const Text('اختيار'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(ColorScheme cs) {
    return Image(
      image: image!,
      width: 96,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: 72,
        height: 72,
        color: cs.secondaryContainer,
        child: Icon(
          Symbols.check_circle_rounded,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// A label / value line in «ملخص الطلب».
class AddDelegateSummaryLine extends StatelessWidget {
  const AddDelegateSummaryLine({
    super.key,
    required this.label,
    required this.value,
    this.ltrValue = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool ltrValue;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: ltrValue ? TextDirection.ltr : null,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: emphasize ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
