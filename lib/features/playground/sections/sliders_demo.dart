import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/sliders.dart';

/// Slider examples from Tashil: invoice discount with stops, reorder level
/// with a synced text field, beep volume and print darkness with inset
/// icons, a centered price change, a price range, the five sizes and
/// vertical sliders.
class SlidersDemo extends StatefulWidget {
  const SlidersDemo({super.key});

  @override
  State<SlidersDemo> createState() => _SlidersDemoState();
}

class _SlidersDemoState extends State<SlidersDemo> {
  double _discount = 10;
  double _reorder = 40;
  late final _reorderText = TextEditingController(text: '40');
  double _volume = 0.6;
  double _dark = 0.5;
  double _change = 5;
  RangeValues _price = const RangeValues(50, 250);
  double _size = 0.4;
  double _vertical = 0.7;
  double _verticalCentered = -4;

  @override
  void dispose() {
    _reorderText.dispose();
    super.dispose();
  }

  Widget _caption(String s) => Padding(
    padding: const EdgeInsets.only(top: TashilSpacing.lg),
    child: Text(s, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption('خصم الفاتورة: ${_discount.round()}% (نقط توقف كل 5%)'),
        Row(
          children: [
            IconButton(
              tooltip: 'قلّل الخصم',
              icon: const Icon(Icons.remove),
              onPressed: _discount <= 0
                  ? null
                  : () => setState(() => _discount -= 5),
            ),
            Expanded(
              child: TashilSlider(
                value: _discount,
                max: 50,
                divisions: 10,
                label: (v) => '${v.round()}%',
                onChanged: (v) => setState(() => _discount = v),
              ),
            ),
            IconButton(
              tooltip: 'زوّد الخصم',
              icon: const Icon(Icons.add),
              onPressed: _discount >= 50
                  ? null
                  : () => setState(() => _discount += 5),
            ),
          ],
        ),
        _caption('حد إعادة الطلب: القيمة في حقل جنبه (Tab بيروح له)'),
        Row(
          children: [
            Expanded(
              child: TashilSlider(
                value: _reorder,
                max: 200,
                onChanged: (v) => setState(() {
                  _reorder = v.roundToDouble();
                  _reorderText.text = '${_reorder.round()}';
                }),
              ),
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _reorderText,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(isDense: true),
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) {
                    setState(() => _reorder = v.clamp(0, 200));
                  }
                },
              ),
            ),
          ],
        ),
        _caption('صوت البيب (L، أيقونة جوه المسار بتقلب صامت عند الصفر)'),
        TashilSlider(
          value: _volume,
          size: SliderSize.l,
          insetIcon: (v) => v == 0
              ? Icons.volume_off
              : v < 0.5
              ? Icons.volume_down
              : Icons.volume_up,
          semanticFormatter: (v) => '${(v * 100).round()}%',
          onChanged: (v) => setState(() => _volume = v),
        ),
        _caption('شدة الطباعة (M)'),
        TashilSlider(
          value: _dark,
          size: SliderSize.m,
          insetIcon: (_) => Icons.print_outlined,
          semanticFormatter: (v) => '${(v * 100).round()}%',
          onChanged: (v) => setState(() => _dark = v),
        ),
        _caption(
          'تعديل الأسعار (centered): ${_change > 0 ? '+' : ''}${_change.round()}%',
        ),
        CenteredSlider(
          value: _change,
          min: -20,
          max: 20,
          divisions: 8,
          label: (v) => '${v > 0 ? '+' : ''}${v.round()}%',
          onChanged: (v) => setState(() => _change = v),
        ),
        _caption(
          'نطاق السعر (range): ${_price.start.round()} لـ ${_price.end.round()} ج',
        ),
        SliderTheme(
          data: sliderThemeFor(context, SliderSize.xs),
          child: RangeSlider(
            values: _price,
            max: 500,
            divisions: 50,
            labels: RangeLabels(
              '${_price.start.round()}',
              '${_price.end.round()}',
            ),
            onChanged: (v) => setState(() => _price = v),
          ),
        ),
        _caption('المقاسات: XS 16، S 24، M 40، L 56، XL 96 (للحظات المهمة بس)'),
        for (final s in SliderSize.values)
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(s.name.toUpperCase(), style: text.labelMedium),
              ),
              Expanded(
                child: TashilSlider(
                  value: _size,
                  size: s,
                  onChanged: (v) => setState(() => _size = v),
                ),
              ),
            ],
          ),
        _caption('رأسي: الأصغر تحت دايماً. الـ range ما يتعملش رأسي.'),
        SizedBox(
          height: 200,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TashilSlider(
                value: _vertical,
                size: SliderSize.m,
                vertical: true,
                onChanged: (v) => setState(() => _vertical = v),
              ),
              CenteredSlider(
                value: _verticalCentered,
                min: -10,
                max: 10,
                vertical: true,
                onChanged: (v) => setState(() => _verticalCentered = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
