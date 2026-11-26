import 'package:material_ui/material_ui.dart';

import '../../../core/design/bidi.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/money.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/button_group.dart';

/// M3 density: the person picks it (here, as a setting would); the list,
/// table and field get shorter, the buttons and their 48dp targets don't.
class DensityDemo extends StatefulWidget {
  const DensityDemo({super.key});

  @override
  State<DensityDemo> createState() => _DensityDemoState();
}

class _DensityDemoState extends State<DensityDemo> {
  TashilDensity _d = TashilDensity.standard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The setting itself always stays at standard density.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ButtonGroup<TashilDensity>(
            variant: ButtonGroupVariant.connected,
            items: [
              for (final d in TashilDensity.values)
                ButtonGroupItem(value: d, label: d.label),
            ],
            selected: {_d},
            onSelectionChanged: (s) => setState(() => _d = s.first),
          ),
        ),
        const SizedBox(height: TashilSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(TashilRadius.medium),
          ),
          child: DensityScope(
            density: _d,
            child: Column(
              children: [
                for (final (name, qty) in const [
                  ('أرز 1 كيلو', 42),
                  ('سكر 1 كيلو', 7),
                  ('زيت 800 مل', 0),
                ])
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(name),
                    subtitle: Text('المخزون $qty'),
                    trailing: IconButton(
                      tooltip: 'تعديل',
                      onPressed: () {},
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(TashilSpacing.lg),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'بحث في الأصناف',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('الصنف')),
                      DataColumn(label: Text('السعر'), numeric: true),
                    ],
                    rows: [
                      for (final (n, p) in const [('أرز', 3250), ('سكر', 2800)])
                        DataRow(
                          cells: [
                            DataCell(Text(n)),
                            DataCell(Text(Money.format(p))),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mirroring in Arabic next to the same widgets in English order: what
/// flips (arrows, send, logout, badge, progress, chips, toolbar order) and
/// what stays LTR (clocks, refresh, media controls, phone and email runs).
class RtlDemo extends StatefulWidget {
  const RtlDemo({super.key});

  @override
  State<RtlDemo> createState() => _RtlDemoState();
}

class _RtlDemoState extends State<RtlDemo> {
  bool _rtl = true;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const phone = '+20 100 123 4567';
    const email = 'ali@tashil.app';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('من اليمين للشمال (عربي)'),
          value: _rtl,
          onChanged: (v) => setState(() => _rtl = v),
        ),
        Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: TashilSpacing.md,
            children: [
              Text('بتتعكس', style: text.labelLarge),
              Wrap(
                spacing: TashilSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Tooltip(message: 'رجوع', child: Icon(Icons.arrow_back)),
                  const Tooltip(message: 'إرسال', child: Icon(Icons.send)),
                  const Tooltip(
                    message: 'خروج',
                    child: MirroredIcon(Icons.logout),
                  ),
                  const Badge(
                    label: Text('7'),
                    child: Icon(Icons.inventory_2_outlined),
                  ),
                  InputChip(label: const Text('آجل'), onDeleted: () {}),
                ],
              ),
              const LinearProgressIndicator(value: 0.3),
              Text('ثابتة زي ما هي', style: text.labelLarge),
              const Wrap(
                spacing: TashilSpacing.sm,
                children: [
                  Tooltip(message: 'الوقت', child: Icon(Icons.schedule)),
                  Tooltip(message: 'تحديث', child: Icon(Icons.refresh)),
                  CircularProgressIndicator(value: 0.3),
                ],
              ),
              const LtrIsland(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.skip_previous),
                    Icon(Icons.play_arrow),
                    Icon(Icons.skip_next),
                  ],
                ),
              ),
              Text('أرقام وإيميلات جوه الكلام', style: text.labelLarge),
              Text('كلّم العميل على ${Bidi.ltr(phone)} أو ${Bidi.ltr(email)}'),
              const TextField(
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الموبايل',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
