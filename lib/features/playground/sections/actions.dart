import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/button_group.dart';
import '../../../core/design/widgets/fab_menu.dart';
import '../../../core/design/widgets/snackbars.dart';
import 'common.dart';

enum _Pay { cash, card, credit }

class ActionsSection extends StatefulWidget {
  const ActionsSection({super.key});

  @override
  State<ActionsSection> createState() => _ActionsSectionState();
}

class _ActionsSectionState extends State<ActionsSection> {
  Set<_Pay> _pay = {_Pay.cash};
  bool _fav = false;
  Set<String> _toggles = {'print', 'scan'};
  Set<String> _range = {'day'};
  Set<int> _qty = {1};

  @override
  Widget build(BuildContext context) {
    void tap() {}
    return SectionList([
      SpecSection(
        title: 'الأزرار',
        m3: 'Common buttons',
        spec: 'components/buttons',
        rule:
            'زر Filled واحد بس لكل شاشة للإجراء الأساسي (دفع، حفظ). '
            'Tonal للثانوي، Outlined للبديل، Text للإلغاء.',
        children: [
          Demo([
            FilledButton(onPressed: tap, child: const Text('Filled')),
            FilledButton.tonal(onPressed: tap, child: const Text('Tonal')),
            ElevatedButton(onPressed: tap, child: const Text('Elevated')),
            OutlinedButton(onPressed: tap, child: const Text('Outlined')),
            TextButton(onPressed: tap, child: const Text('Text')),
          ]),
          const SizedBox(height: 8),
          Demo([
            FilledButton.icon(
              onPressed: tap,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ'),
            ),
            OutlinedButton.icon(
              onPressed: tap,
              icon: const Icon(Icons.print_outlined),
              label: const Text('طباعة'),
            ),
            const FilledButton(onPressed: null, child: Text('معطّل')),
          ]),
        ],
      ),
      SpecSection(
        title: 'أزرار الأيقونات',
        m3: 'Icon buttons',
        spec: 'components/icon-buttons',
        children: [
          Demo([
            IconButton(
              tooltip: 'Standard',
              onPressed: tap,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton.filled(
              tooltip: 'Filled',
              onPressed: tap,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton.filledTonal(
              tooltip: 'Tonal',
              onPressed: tap,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton.outlined(
              tooltip: 'Outlined',
              onPressed: tap,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton(
              tooltip: 'Toggle',
              isSelected: _fav,
              onPressed: () => setState(() => _fav = !_fav),
              icon: const Icon(Icons.star_outline),
              selectedIcon: const Icon(Icons.star),
            ),
          ]),
        ],
      ),
      SpecSection(
        title: 'الزر العائم',
        m3: 'FAB',
        spec: 'components/floating-action-button',
        rule: 'FAB للإجراء الأهم في الشاشة: مسح باركود أو إضافة صنف.',
        children: [
          Demo([
            FloatingActionButton.small(
              heroTag: 'fab-s',
              onPressed: tap,
              child: const Icon(Icons.add),
            ),
            FloatingActionButton(
              heroTag: 'fab-m',
              onPressed: tap,
              child: const Icon(Icons.qr_code_scanner),
            ),
            FloatingActionButton.large(
              heroTag: 'fab-l',
              onPressed: tap,
              child: const Icon(Icons.qr_code_scanner),
            ),
            FloatingActionButton.extended(
              heroTag: 'fab-e',
              onPressed: tap,
              icon: const Icon(Icons.add),
              label: const Text('صنف جديد'),
            ),
          ]),
        ],
      ),
      const SpecSection(
        title: 'الزر العائم الممتد',
        m3: 'Extended FAB',
        spec: 'components/extended-fab/guidelines',
        rule:
            'للإجراء الأساسي لما الأيقونة لوحدها مش كفاية (صنف جديد، فاتورة '
            'جديدة). بيتقفل لأيقونة بس لما تنزل في القائمة ويرجع يفتح لما '
            'تطلع. مكانه تحت على الطرف (يسار في العربي) فوق شريط التنقل.',
        children: [_ExtendedFabDemo()],
      ),
      const SpecSection(
        title: 'قائمة الزر العائم',
        m3: 'FAB menu',
        spec: 'components/fab-menu/accessibility',
        rule:
            'من 2 لـ 6 إجراءات مرتبطة ببعض بتطلع من الـ FAB، زي (فاتورة، '
            'صنف، استلام بضاعة). الفوكس بيبدأ على زرار الإغلاق، وEsc بيقفل.',
        children: [_FabMenuDemo()],
      ),
      SpecSection(
        title: 'مجموعات الأزرار',
        m3: 'Button groups (standard)',
        spec: 'components/button-groups',
        rule:
            'أزرار مرتبطة ببعض في صف واحد، زي أدوات الصنف أو اختيارات '
            'متعددة. الزرار اللي بتدوس عليه بيعرض وشكله بيتغير.',
        children: [
          ButtonGroup<String>(
            size: ButtonGroupSize.m,
            multiSelect: true,
            selectionRequired: false,
            selected: _toggles,
            onSelectionChanged: (v) => setState(() => _toggles = v),
            items: const [
              ButtonGroupItem(
                value: 'print',
                icon: Icons.print_outlined,
                tooltip: 'طباعة تلقائية',
              ),
              ButtonGroupItem(
                value: 'sound',
                icon: Icons.volume_up_outlined,
                tooltip: 'صوت المسح',
              ),
              ButtonGroupItem(
                value: 'scan',
                icon: Icons.qr_code_scanner,
                label: 'مسح',
              ),
              ButtonGroupItem(
                value: 'flash',
                icon: Icons.flashlight_on_outlined,
                tooltip: 'فلاش الكاميرا',
              ),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          ButtonGroup<String>(
            size: ButtonGroupSize.s,
            onPressed: (_) {},
            items: const [
              ButtonGroupItem(
                value: 'edit',
                icon: Icons.edit_outlined,
                tooltip: 'تعديل',
              ),
              ButtonGroupItem(
                value: 'dup',
                icon: Icons.copy_outlined,
                label: 'تكرار',
              ),
              ButtonGroupItem(
                value: 'del',
                icon: Icons.delete_outline,
                tooltip: 'حذف',
              ),
            ],
          ),
        ],
      ),
      SpecSection(
        title: 'مجموعة أزرار متصلة',
        m3: 'Button groups (connected)',
        spec: 'components/button-groups',
        rule:
            'لاختيار من 2 لـ 5 بدائل، زي طريقة الدفع أو فترة التقرير. '
            'دي بديل Segmented button، وممنوع نستخدم SegmentedButton.',
        children: [
          ButtonGroup<_Pay>(
            variant: ButtonGroupVariant.connected,
            size: ButtonGroupSize.m,
            expand: true,
            selected: _pay,
            onSelectionChanged: (v) => setState(() => _pay = v),
            items: const [
              ButtonGroupItem(
                value: _Pay.cash,
                label: 'كاش',
                icon: Icons.payments_outlined,
              ),
              ButtonGroupItem(
                value: _Pay.card,
                label: 'فيزا',
                icon: Icons.credit_card,
              ),
              ButtonGroupItem(
                value: _Pay.credit,
                label: 'آجل',
                icon: Icons.schedule,
              ),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          ButtonGroup<String>(
            variant: ButtonGroupVariant.connected,
            size: ButtonGroupSize.s,
            expand: true,
            selected: _range,
            onSelectionChanged: (v) => setState(() => _range = v),
            items: const [
              ButtonGroupItem(value: 'day', label: 'اليوم'),
              ButtonGroupItem(value: 'week', label: 'الأسبوع'),
              ButtonGroupItem(value: 'month', label: 'الشهر'),
              ButtonGroupItem(value: 'year', label: 'السنة'),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          Text(
            'الأحجام: XS · S · M',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: TashilSpacing.sm),
          for (final size in const [
            ButtonGroupSize.xs,
            ButtonGroupSize.s,
            ButtonGroupSize.m,
          ]) ...[
            ButtonGroup<int>(
              variant: ButtonGroupVariant.connected,
              size: size,
              selected: _qty,
              onSelectionChanged: (v) => setState(() => _qty = v),
              items: const [
                ButtonGroupItem(value: 1, label: '1'),
                ButtonGroupItem(value: 5, label: '5'),
                ButtonGroupItem(value: 10, label: '10'),
                ButtonGroupItem(value: 12, label: '12'),
              ],
            ),
            const SizedBox(height: TashilSpacing.sm),
          ],
        ],
      ),
    ]);
  }
}

/// Extended FAB that collapses to an icon-only FAB while the list scrolls
/// down and expands again when it scrolls up (M3 extended FAB guidelines).
class _ExtendedFabDemo extends StatefulWidget {
  const _ExtendedFabDemo();

  @override
  State<_ExtendedFabDemo> createState() => _ExtendedFabDemoState();
}

class _ExtendedFabDemoState extends State<_ExtendedFabDemo> {
  bool _extended = true;

  static const _items = [
    'سكر أبيض 1 كجم',
    'زيت عباد الشمس',
    'أرز مصري 5 كجم',
    'شاي ليبتون 100 فتلة',
    'مكرونة 400 جم',
    'جبنة دومتي 500 جم',
    'لبن جهينة 1 لتر',
    'عدس أصفر 1 كجم',
    'صلصة طماطم',
    'بسكويت شاي',
    'مياه معدنية 1.5 لتر',
    'تونة قطع',
  ];

  bool _onScroll(UserScrollNotification n) {
    final extend = switch (n.direction) {
      ScrollDirection.reverse => false, // scrolling down the list
      ScrollDirection.forward => true,
      ScrollDirection.idle => n.metrics.pixels <= 0 ? true : _extended,
    };
    if (extend != _extended) setState(() => _extended = extend);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 320,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: Scaffold(
        body: NotificationListener<UserScrollNotification>(
          onNotification: _onScroll,
          // Same-format rows: spacing is enough, no dividers (M3).
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_items[i]),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fab-demo',
          isExtended: _extended,
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('صنف جديد'),
          tooltip: 'صنف جديد',
        ),
      ),
    );
  }
}

class _FabMenuDemo extends StatelessWidget {
  const _FabMenuDemo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void done(String what) => showTashilSnackBar(context, what);
    return Container(
      height: 380,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: Scaffold(
        body: const Center(child: Text('اضغط + تحت')),
        floatingActionButton: FabMenu(
          items: [
            FabMenuItem(
              icon: Icons.point_of_sale_outlined,
              label: 'فاتورة بيع',
              onPressed: () => done('فاتورة بيع'),
            ),
            FabMenuItem(
              icon: Icons.inventory_2_outlined,
              label: 'صنف جديد',
              onPressed: () => done('صنف جديد'),
            ),
            FabMenuItem(
              icon: Icons.local_shipping_outlined,
              label: 'استلام بضاعة',
              onPressed: () => done('استلام بضاعة'),
            ),
            FabMenuItem(
              icon: Icons.receipt_long_outlined,
              label: 'مصروف',
              onPressed: () => done('مصروف'),
            ),
          ],
        ),
      ),
    );
  }
}
