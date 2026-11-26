import 'package:material_ui/material_ui.dart';

import '../../../core/design/layout.dart';
import '../../../core/design/money.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/button_group.dart';
import '../../../core/design/widgets/toolbar.dart';

/// Preview of the M3 layout scaffold: pick a breakpoint and see the same
/// invoices screen as a scaled-down window of that width.
class LayoutDemo extends StatefulWidget {
  const LayoutDemo({super.key});

  @override
  State<LayoutDemo> createState() => _LayoutDemoState();
}

class _LayoutDemoState extends State<LayoutDemo> {
  static const _widths = {
    TashilBreakpoint.compact: 360.0,
    TashilBreakpoint.medium: 700.0,
    TashilBreakpoint.expanded: 1000.0,
    TashilBreakpoint.large: 1360.0,
    TashilBreakpoint.extraLarge: 1760.0,
  };

  TashilBreakpoint _b = TashilBreakpoint.expanded;
  int? _open = 0;
  bool _contained = false;
  bool _grid = false;
  PaneSplit _split = PaneSplit.fixedFlexible;

  /// Persistent resizing: the width you drag to stays when you switch
  /// breakpoints.
  final _panes = PaneLayoutController();

  @override
  void dispose() {
    _panes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final window = TashilBreakpoint.of(context);
    final b = _b;
    final width = _widths[b]!;
    final compact = b == TashilBreakpoint.compact;
    final panes = switch (b) {
      TashilBreakpoint.compact || TashilBreakpoint.medium => 1,
      TashilBreakpoint.extraLarge => 3,
      _ => 2,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الشاشة دي دلوقتي: ${window.label} '
          '(${MediaQuery.sizeOf(context).width.round()}dp)',
          style: text.labelLarge,
        ),
        const SizedBox(height: TashilSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ButtonGroup<TashilBreakpoint>(
            variant: ButtonGroupVariant.connected,
            items: [
              for (final v in TashilBreakpoint.values)
                ButtonGroupItem(value: v, label: v.label),
            ],
            selected: {b},
            onSelectionChanged: (s) => setState(() => _b = s.first),
          ),
        ),
        const SizedBox(height: TashilSpacing.sm),
        Text(
          'من ${b.minWidth.round()}dp · هامش ${b.margin.round()} · '
          '${panes == 1 ? 'جزء واحد' : '$panes أجزاء، بينهم ${b.spacer.round()}'}'
          '${b.fixedPaneWidth == null ? '' : ' · القايمة ${b.fixedPaneWidth!.round()}dp'}',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: TashilSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ButtonGroup<PaneSplit>(
            variant: ButtonGroupVariant.connected,
            items: const [
              ButtonGroupItem(
                value: PaneSplit.fixedFlexible,
                label: 'ثابت + مرن',
              ),
              ButtonGroupItem(
                value: PaneSplit.flexibleFixed,
                label: 'مرن + ثابت',
              ),
              ButtonGroupItem(value: PaneSplit.split, label: 'نص بنص'),
            ],
            selected: {_split},
            onSelectionChanged: (s) => setState(() {
              _split = s.first;
              _panes.reset();
            }),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('أجزاء بخلفية (تجميع صريح)'),
          value: _contained,
          onChanged: (v) => setState(() => _contained = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'إظهار الأعمدة (${b.columns} عمود، بينهم ${b.gutter.round()})',
          ),
          value: _grid,
          onChanged: (v) => setState(() => _grid = v),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(TashilRadius.medium),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TashilRadius.medium),
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: width,
                height: 460,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: Size(width, 460)),
                  child: Material(
                    color: scheme.surface,
                    child: Stack(
                      children: [
                        Padding(
                          // Trailing rail region for the vertical toolbar.
                          padding: EdgeInsetsDirectional.only(
                            top: TashilSpacing.lg,
                            bottom: TashilSpacing.lg,
                            end: compact ? 0 : _rail,
                          ),
                          child: PaneLayout(
                            controller: _panes,
                            split: _split,
                            breakpoint: b,
                            contained: _contained,
                            showSecond: _open != null,
                            first: _List(
                              selected: _open,
                              onOpen: (i) => setState(() => _open = i),
                            ),
                            second: _open == null
                                ? null
                                : _Detail(
                                    index: _open!,
                                    onBack: b < TashilBreakpoint.expanded
                                        ? () => setState(() => _open = null)
                                        : null,
                                  ),
                            placeholder: const Center(
                              child: Text('اختار فاتورة من القايمة'),
                            ),
                            third: const _Filters(),
                          ),
                        ),
                        if (_grid)
                          Positioned.fill(
                            child: ColumnGridOverlay(breakpoint: b),
                          ),
                        if (compact)
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: TashilSpacing.lg,
                            child: Center(
                              child: TashilToolbar(actions: _tools),
                            ),
                          )
                        else
                          const PositionedDirectional(
                            end: 0,
                            top: 0,
                            bottom: 0,
                            width: _rail,
                            child: Center(
                              child: TashilToolbar(
                                axis: Axis.vertical,
                                actions: _tools,
                              ),
                            ),
                          ),
                        PositionedDirectional(
                          end: b.margin + (compact ? 0 : _rail),
                          bottom: TashilSpacing.lg,
                          child: AdaptiveFab(
                            breakpoint: b,
                            icon: Icons.add,
                            label: 'فاتورة جديدة',
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _rail = 88.0;

const _tools = [
  ToolbarAction(icon: Icons.print_outlined, label: 'طباعة', onPressed: _noop),
  ToolbarAction(icon: Icons.share_outlined, label: 'مشاركة', onPressed: _noop),
  ToolbarAction(icon: Icons.filter_list, label: 'تصفية', onPressed: _noop),
];

void _noop() {}

const _customers = ['محل الأمل', 'سوبر ماركت النور', 'عم سيد', 'بقالة الخير'];

class _List extends StatelessWidget {
  const _List({required this.selected, required this.onOpen});

  final int? selected;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (var i = 0; i < _customers.length; i++)
        ListTile(
          selected: i == selected,
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(_customers[i]),
          subtitle: Text('فاتورة ${1041 + i}'),
          trailing: Text(Money.format(12550 * (i + 1))),
          onTap: () => onOpen(i),
        ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.index, this.onBack});

  final int index;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(TashilSpacing.lg),
      children: [
        Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: 'رجوع',
                onPressed: onBack,
                icon: const BackButtonIcon(),
              ),
            Expanded(
              child: Text('فاتورة ${1041 + index}', style: text.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: TashilSpacing.sm),
        Text(_customers[index], style: text.titleMedium),
        const SizedBox(height: TashilSpacing.md),
        ReadingWidth(
          child: Text(
            'في الشاشات الكبيرة الفاتورة بتفتح جنب القايمة، وفي الموبايل '
            'بتاخد الشاشة كلها وفيه زرار رجوع. السطر مش بيعدّي 60 حرف '
            'عشان يتقري بسهولة.',
            style: text.bodyLarge,
          ),
        ),
        const SizedBox(height: TashilSpacing.md),
        Text(
          'الإجمالي ${Money.format(12550 * (index + 1))}',
          style: text.titleLarge,
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(TashilSpacing.lg),
    children: [
      Text('تصفية', style: Theme.of(context).textTheme.titleMedium),
      for (final f in ['مدفوعة', 'آجل', 'مرتجع'])
        CheckboxListTile(
          value: f != 'مرتجع',
          onChanged: (_) {},
          title: Text(f),
        ),
    ],
  );
}
