import 'package:flutter/material.dart';

/// Body of the "select organization" bottom sheet shown at login when a
/// person is registered in more than one organization (TAS-296).
///
/// A smotchi delegate can be linked to ~39 chains. The old sheet put every
/// card in a plain [Column], so anything below the screen edge was cut off
/// and could never be reached. Here the header stays fixed and the cards
/// scroll inside a height-capped list.
class OrganizationSelectorSheet extends StatelessWidget {
  const OrganizationSelectorSheet({
    super.key,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    this.topRadius = 28,
    this.maxHeightFactor = 0.9,
  });

  /// Fixed widgets above the list (drag handle, title, subtitle).
  final List<Widget> header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double topRadius;

  /// Share of the screen height the sheet may take at most.
  final double maxHeightFactor;

  static const listKey = ValueKey('organization-selector-list');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = (media.size.height - media.padding.top) * maxHeightFactor;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...header,
          Flexible(
            child: Scrollbar(
              child: ListView.builder(
                key: listKey,
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: 36 + media.padding.bottom),
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Organizations sorted by name, so a long list is easy to scan (TAS-296).
/// Display order only; the caller's list is not changed.
List<T> sortedByOrganizationName<T>(List<T> items, String Function(T) name) =>
    [...items]..sort((a, b) => name(a).trim().compareTo(name(b).trim()));
