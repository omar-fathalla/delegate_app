import '../../../core/design/widgets/summary_card.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/bidi.dart';
import '../../../core/design/tokens.dart';
import '../sample_widgets.dart';
import 'common.dart';

class ContainmentSection extends StatelessWidget {
  const ContainmentSection({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget cardBody(String t, String v) => Padding(
      padding: const EdgeInsets.all(TashilSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: text.labelLarge),
          Text(v, style: text.headlineSmall),
        ],
      ),
    );

    return SectionList([
      SpecSection(
        title: 'الكروت',
        m3: 'Cards',
        spec: 'components/cards',
        rule: 'Filled لمؤشرات الداشبورد، Outlined للعناصر القابلة للضغط.',
        children: [
          Row(
            children: [
              Expanded(child: Card(child: cardBody('Elevated', '12 فاتورة'))),
              Expanded(
                child: Card.filled(child: cardBody('Filled', '3,450 ج.م')),
              ),
              Expanded(
                child: Card.outlined(child: cardBody('Outlined', '5 أصناف')),
              ),
            ],
          ),
        ],
      ),
      // P-07 (TAS-387): a card whose content fills its width.
      SpecSection(
        title: 'كارت الملخص',
        m3: 'Cards (summary pattern)',
        spec: 'components/cards',
        children: [
          SummaryCard(
            icon: Icons.storefront_rounded,
            title: 'فرع المعادي',
            subtitle: 'سلسلة تجريبية',
            trailingValue: Bidi.ltr('07:45'),
            trailingCaption: 'المدة',
            trailingIcon: Icons.timer_outlined,
            labels: [
              SummaryLabel(
                'نشط',
                container: Theme.of(context).colorScheme.tertiaryContainer,
                onContainer: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ],
            facts: const [
              SummaryFact(icon: Icons.login_rounded, label: 'الدخول', value: '09:02 ص'),
              SummaryFact(icon: Icons.logout_rounded, label: 'الخروج', value: '04:47 م'),
            ],
          ),
        ],
      ),
      SpecSection(
        title: 'القوائم',
        m3: 'Lists',
        spec: 'components/lists',
        children: [
          Card.outlined(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('أحمد محمود'),
                  subtitle: Text('رصيد آجل'),
                  trailing: MoneyText(125000),
                ),
                const Divider(
                  indent: TashilDividerInset.afterIcon,
                  endIndent: TashilDividerInset.both,
                ),
                ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('شركة النيل للتوريدات'),
                  subtitle: const Text('آخر توريد من 3 أيام'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () {},
                ),
                const Divider(
                  indent: TashilDividerInset.afterIcon,
                  endIndent: TashilDividerInset.both,
                ),
                ExpansionTile(
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('فاتورة ${Bidi.ltr('SUNMI01-20261125-0042')}'),
                  children: const [
                    ListTile(title: Text('سكر ×2'), trailing: MoneyText(9100)),
                    ListTile(title: Text('شاي ×1'), trailing: MoneyText(6500)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      SpecSection(
        title: 'جدول البيانات',
        m3: 'Data table',
        spec: 'components/lists',
        rule:
            'M3 مالوش DataTable رسمي. نستخدمه في التقارير بس، '
            'وعلى الموبايل جوه scroll أفقي.',
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('الصنف')),
                DataColumn(label: Text('الكمية'), numeric: true),
                DataColumn(label: Text('الإجمالي'), numeric: true),
              ],
              rows: const [
                DataRow(
                  cells: [
                    DataCell(Text('سكر أبيض')),
                    DataCell(Text('34')),
                    DataCell(MoneyText(154700)),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('زيت عباد')),
                    DataCell(Text('12')),
                    DataCell(MoneyText(102000)),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('أرز مصري')),
                    DataCell(Text('8')),
                    DataCell(MoneyText(76000)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      SpecSection(
        title: 'الشارات',
        m3: 'Badges',
        spec: 'components/badges',
        children: [
          const Demo([
            Badge(child: Icon(Icons.notifications_outlined)),
            Badge(label: Text('7'), child: Icon(Icons.inventory_2_outlined)),
            Badge(label: Text('99+'), child: Icon(Icons.cloud_upload_outlined)),
          ]),
        ],
      ),
      SpecSection(
        title: 'الفواصل',
        m3: 'Divider',
        spec: 'components/divider/guidelines',
        rule:
            'بعرض كامل بين أقسام مختلفة (أو بين المحتوى والأزرار). Inset بين '
            'عناصر مرتبطة، ويبدأ عند النص مش تحت الأيقونة. بالراحة: '
            'القوائم المتشابهة المسافة بتكفي. الرأسي للشاشات الواسعة بس.',
        children: [
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupTitle('الطباعة'),
                SwitchListTile(
                  secondary: const Icon(Icons.print_outlined),
                  value: true,
                  onChanged: (_) {},
                  title: const Text('اطبع الفاتورة تلقائياً'),
                ),
                const Divider(
                  indent: TashilDividerInset.afterIcon,
                  endIndent: TashilDividerInset.both,
                ),
                const ListTile(
                  leading: Icon(Icons.straighten),
                  title: Text('عرض الورق'),
                  trailing: Text('58 مم'),
                ),
                // Full width: a different group starts.
                const Divider(),
                const _GroupTitle('المزامنة'),
                const ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('آخر مزامنة'),
                  trailing: Text('منذ 5 دقائق'),
                ),
                const Divider(
                  indent: TashilDividerInset.afterIcon,
                  endIndent: TashilDividerInset.both,
                ),
                const ListTile(
                  leading: Icon(Icons.wifi_off_outlined),
                  title: Text('في الانتظار'),
                  trailing: Text('3 فواتير'),
                ),
                // Full width: content above, actions below.
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(TashilSpacing.sm),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('زامن الآن'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TashilSpacing.lg),
          Text(
            'رأسي (شاشة واسعة: قائمة + تفاصيل)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: TashilSpacing.sm),
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 120,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: const [
                        ListTile(dense: true, title: Text('فاتورة 1041')),
                        ListTile(
                          dense: true,
                          selected: true,
                          title: Text('فاتورة 1042'),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(TashilSpacing.md),
                      child: Text(
                        'فاتورة 1042\n3 أصناف · 245.00 ج.م',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ]);
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      TashilSpacing.lg,
      TashilSpacing.lg,
      TashilSpacing.lg,
      TashilSpacing.xs,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
