import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// Search that follows m3.material.io/components/search/guidelines, built
/// on Flutter's official [SearchAnchor] + [SearchBar] (focused search,
/// full-screen and docked views, back to release focus, clear button).
/// What this adds is the arrangement the page asks for:
///
/// * **Entry points:** a search bar over the content it searches, or a
///   search icon button when search is secondary ([asIconButton]).
/// * **Focused search:** full-screen on compact (< 600dp), docked with a
///   scrim from 600dp.
/// * **Before typing:** recent searches under a "الأخيرة" label.
/// * **While typing:** results in groups with category labels, separated
///   by gaps, with leading icons or thumbnails, and optional filter chips to
///   narrow them. A status line ("نتايج سريعة: 3") tells screen readers that
///   results are showing.
/// * **Submit:** Enter (or a barcode scanner, which types and presses
///   Enter) runs the search; the query stays visible in the bar, not
///   focused.
/// * **Bar:** a non-functional search icon at the start, at most two
///   trailing icons, short hint ("ابحث في الأصناف"), colour
///   `surfaceContainerHigh` (do not put it on a `surfaceContainer`
///   background).
class SearchResult {
  const SearchResult({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Object? value;
}

/// Results of one category ("الأصناف", "الموردين").
class SearchResultGroup {
  const SearchResultGroup(this.label, this.items);
  final String label;
  final List<SearchResult> items;
}

class TashilSearch extends StatefulWidget {
  const TashilSearch({
    super.key,
    required this.hintText,
    required this.search,
    this.recent = const [],
    this.filters = const [],
    this.trailing = const [],
    this.onSelected,
    this.onSubmitted,
    this.asIconButton = false,
    this.tooltip = 'بحث',
  }) : assert(trailing.length <= 2, 'M3: at most two trailing icons');

  /// Short description of what can be searched: "ابحث في الأصناف".
  final String hintText;

  /// Results for a query, limited to [filter] when one is chosen.
  final List<SearchResultGroup> Function(String query, String? filter) search;

  /// Shown before anything is typed, newest first.
  final List<String> recent;

  /// Filter chip labels to narrow results ("أصناف", "عملاء"). Empty: none.
  final List<String> filters;

  /// Up to two trailing icon buttons in the bar (barcode scan, overflow).
  final List<Widget> trailing;
  final ValueChanged<SearchResult>? onSelected;

  /// Enter pressed: the query is searched; it is also added to [recent].
  final ValueChanged<String>? onSubmitted;

  /// Search as a secondary action: an icon button that opens focused
  /// search.
  final bool asIconButton;
  final String tooltip;

  @override
  State<TashilSearch> createState() => _TashilSearchState();
}

class _TashilSearchState extends State<TashilSearch> {
  final _controller = SearchController();
  late final List<String> _recent = [...widget.recent];
  String? _filter;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    setState(() {
      _recent
        ..remove(query)
        ..insert(0, query);
      if (_recent.length > 5) _recent.removeLast();
    });
    _controller.closeView(query);
    widget.onSubmitted?.call(query);
  }

  void _select(SearchResult r) {
    _controller.closeView(r.title);
    widget.onSelected?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < TashilSizes.compactMax;
    return SearchAnchor(
      searchController: _controller,
      isFullScreen: compact,
      viewHintText: widget.hintText,
      viewConstraints: const BoxConstraints(minHeight: 240, maxHeight: 480),
      viewOnSubmitted: _submit,
      viewTrailing: [
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: MaterialLocalizations.of(context)
                      .deleteButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: _controller.clear,
                ),
        ),
        ...widget.trailing.take(1),
      ],
      builder: (context, controller) => widget.asIconButton
          ? IconButton(
              tooltip: widget.tooltip,
              icon: const Icon(Icons.search),
              onPressed: controller.openView,
            )
          : SearchBar(
              controller: controller,
              hintText: widget.hintText,
              leading: const ExcludeSemantics(child: Icon(Icons.search)),
              trailing: widget.trailing,
              onTap: controller.openView,
              onChanged: (_) => controller.openView(),
            ),
      suggestionsBuilder: (context, controller) => [
        StatefulBuilder(
          builder: (context, setLocal) => _Suggestions(
            query: controller.text,
            recent: _recent,
            filters: widget.filters,
            filter: _filter,
            onFilter: (f) => setLocal(() => _filter = f),
            groups: controller.text.trim().isEmpty
                ? const []
                : widget.search(controller.text.trim(), _filter),
            onRecent: (q) {
              controller.text = q;
              _submit(q);
            },
            onRemoveRecent: (q) => setLocal(
              () => setState(() {
                _recent.remove(q);
              }),
            ),
            onSelected: _select,
          ),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.query,
    required this.recent,
    required this.filters,
    required this.filter,
    required this.onFilter,
    required this.groups,
    required this.onRecent,
    required this.onRemoveRecent,
    required this.onSelected,
  });

  final String query;
  final List<String> recent;
  final List<String> filters;
  final String? filter;
  final ValueChanged<String?> onFilter;
  final List<SearchResultGroup> groups;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onRemoveRecent;
  final ValueChanged<SearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget label(String s) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.lg,
        TashilSpacing.md,
        TashilSpacing.lg,
        TashilSpacing.xs,
      ),
      child: Text(s, style: text.labelLarge?.copyWith(color: scheme.primary)),
    );

    /// A group on its own rounded surface; groups are separated by gaps.
    Widget group(List<Widget> tiles) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: TashilSpacing.sm),
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TashilRadius.large),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: tiles),
      ),
    );

    if (query.trim().isEmpty) {
      if (recent.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('الأخيرة'),
          group([
            for (final r in recent)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(r),
                onTap: () => onRecent(r),
                trailing: IconButton(
                  tooltip: 'شيل من الأخيرة',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemoveRecent(r),
                ),
              ),
          ]),
        ],
      );
    }

    final count = groups.fold(0, (n, g) => n + g.items.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filters.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              TashilSpacing.lg,
              TashilSpacing.sm,
              TashilSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: TashilSpacing.sm,
                    ),
                    child: FilterChip(
                      label: Text(f),
                      selected: filter == f,
                      onSelected: (on) => onFilter(on ? f : null),
                    ),
                  ),
              ],
            ),
          ),
        Semantics(
          liveRegion: true,
          child: label(
            count == 0 ? 'مفيش نتايج لـ "$query"' : 'نتايج سريعة: $count',
          ),
        ),
        for (final (i, g)
            in groups.where((g) => g.items.isNotEmpty).indexed) ...[
          if (i > 0) const SizedBox(height: TashilSpacing.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: TashilSpacing.lg,
              bottom: TashilSpacing.xs,
            ),
            child: Text(
              g.label,
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          group([
            for (final r in g.items)
              ListTile(
                leading: r.leading,
                title: Text(r.title),
                subtitle: r.subtitle == null ? null : Text(r.subtitle!),
                trailing: r.trailing,
                onTap: () => onSelected(r),
              ),
          ]),
        ],
        const SizedBox(height: TashilSpacing.lg),
      ],
    );
  }
}
