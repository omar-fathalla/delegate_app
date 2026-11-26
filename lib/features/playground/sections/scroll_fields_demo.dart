import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/scroll_field.dart';

/// Scroll field examples for the playground: a weight in kilos and grams
/// (grams in steps of 50, so the list stays short), a quantity with its
/// unit (strings auto-complete), and the three sizes.
class ScrollFieldsDemo extends StatefulWidget {
  const ScrollFieldsDemo({super.key});

  @override
  State<ScrollFieldsDemo> createState() => _ScrollFieldsDemoState();
}

class _ScrollFieldsDemoState extends State<ScrollFieldsDemo> {
  static final _kilos = List.generate(51, (i) => i);
  static final _grams = List.generate(20, (i) => i * 50);
  static final _qty = List.generate(999, (i) => i + 1);
  static const _units = ['قطعة', 'علبة', 'كرتونة', 'كيس', 'كيلو'];
  static final _reorder = List.generate(100, (i) => i);
  static final _years = List.generate(21, (i) => 2020 + i);

  int _kg = 2;
  int _g = 350;
  int _q = 12;
  String _unit = 'كرتونة';
  bool _weightKeyboard = false;
  bool _qtyKeyboard = false;
  int _min = 5;
  int _q2 = 120;
  int _year = 2027;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget caption(String s) => Padding(
      padding: const EdgeInsets.only(
        top: TashilSpacing.md,
        bottom: TashilSpacing.sm,
      ),
      child: Text(s, style: text.titleSmall),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        caption('وزن صنف سايب: ${'$_kg.${'$_g'.padLeft(3, '0')}'} كجم'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ScrollField<int>(
              label: 'كيلو',
              values: _kilos,
              value: _kg,
              format: (v) => '$v',
              parse: parseTypedInt,
              textInput: _weightKeyboard,
              onChanged: (v) => setState(() => _kg = v),
            ),
            const SizedBox(width: TashilSpacing.sm),
            ScrollField<int>(
              label: 'جرام',
              size: ScrollFieldSize.medium,
              values: _grams,
              value: _g,
              format: (v) => '$v',
              parse: parseTypedInt,
              textInput: _weightKeyboard,
              onChanged: (v) => setState(() => _g = v),
            ),
            const SizedBox(width: TashilSpacing.xs),
            ScrollFieldInputToggle(
              textInput: _weightKeyboard,
              onChanged: (v) => setState(() => _weightKeyboard = v),
            ),
          ],
        ),
        caption('كمية الاستلام: $_q $_unit'),
        Row(
          children: [
            ScrollField<int>(
              label: 'الكمية',
              size: ScrollFieldSize.medium,
              values: _qty,
              value: _q,
              format: (v) => '$v',
              parse: parseTypedInt,
              textInput: _qtyKeyboard,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(width: TashilSpacing.sm),
            ScrollField<String>(
              label: 'الوحدة',
              width: 124,
              values: _units,
              value: _unit,
              format: (v) => v,
              textInput: _qtyKeyboard,
              onChanged: (v) => setState(() => _unit = v),
            ),
            const SizedBox(width: TashilSpacing.xs),
            ScrollFieldInputToggle(
              textInput: _qtyKeyboard,
              onChanged: (v) => setState(() => _qtyKeyboard = v),
            ),
          ],
        ),
        caption('المقاسات: صغير (1-2 رقم) ومتوسط (3) وكبير (4)'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ScrollField<int>(
                label: 'حد الطلب',
                values: _reorder,
                value: _min,
                height: 136,
                format: (v) => '$v',
                parse: parseTypedInt,
                onChanged: (v) => setState(() => _min = v),
              ),
              const SizedBox(width: TashilSpacing.sm),
              ScrollField<int>(
                label: 'الكمية',
                size: ScrollFieldSize.medium,
                values: _qty,
                value: _q2,
                height: 136,
                format: (v) => '$v',
                parse: parseTypedInt,
                onChanged: (v) => setState(() => _q2 = v),
              ),
              const SizedBox(width: TashilSpacing.sm),
              ScrollField<int>(
                label: 'السنة',
                size: ScrollFieldSize.large,
                values: _years,
                value: _year,
                height: 136,
                format: (v) => '$v',
                parse: parseTypedInt,
                onChanged: (v) => setState(() => _year = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
