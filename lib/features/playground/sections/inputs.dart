import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/chips.dart';
import '../../../core/design/widgets/date_time_fields.dart';
import '../../../core/design/widgets/menus.dart';
import 'common.dart';
import 'scroll_fields_demo.dart';
import 'search_demo.dart';
import 'sliders_demo.dart';
import 'text_fields_demo.dart';

class InputsSection extends StatefulWidget {
  const InputsSection({super.key});

  @override
  State<InputsSection> createState() => _InputsSectionState();
}

class _InputsSectionState extends State<InputsSection> {
  bool _check = true;
  bool _switch = true;
  String _unit = 'pcs';
  String _pay = 'cash';
  String? _vendor;
  final Set<String> _columns = {'الكمية', 'سعر البيع'};
  final Set<String> _filters = {'قليل المخزون'};
  String _choice = 'اليوم';
  final Set<String> _row = {'بقالة'};
  String? _category;
  String? _supplier;
  bool _saved = false;
  List<String> _barcodes = ['6221234567890'];
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? _invoiceDate = DateTime(2026, 11, 26);
  DateTime? _expiry;
  DateTimeRange? _range;
  TimeOfDay _shiftClose = const TimeOfDay(hour: 23, minute: 0);
  bool _time24 = false;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return SectionList([
      const SpecSection(
        title: 'حقول النص',
        m3: 'Text fields',
        spec: 'components/text-fields/guidelines',
        rule:
            'Outlined في كل الفورمات (مفيش خلط بين النوعين في نفس المكان). '
            'كل حقل ليه عنوان قصير ظاهر. المطلوب عليه * ومعاه ملاحظة واحدة '
            'فوق الفورم. الخطأ بياخد مكان النص المساعد ومعاه أيقونة خطأ. '
            'عداد حروف لو فيه حد أقصى. أيقونة المسح تظهر بس لما يكون فيه '
            'كلام. حقل للقراءة بس شكله عادي ومكتوب إنه للقراءة. من 600 '
            'الحقول ليها أقصى عرض. العرض المضغوط اختيار مش افتراضي.',
        children: [TextFieldsDemo()],
      ),
      const SpecSection(
        title: 'البحث',
        m3: 'Search',
        spec: 'components/search/guidelines',
        rule:
            'شريط البحث فوق المحتوى اللي بيدور فيه، وفيه أيقونة بحث في '
            'البداية وأيقونتين بالكتير في الآخر (الباركود). قبل الكتابة: '
            'الأخيرة. وانت بتكتب: نتايج في مجموعات بفواصل ومعاها فلاتر. '
            'ملء الشاشة على الموبايل، ومنسدل من 600. Enter بيبحث والكلمة '
            'بتفضل ظاهرة.',
        children: [SearchDemo()],
      ),
      SpecSection(
        title: 'القوائم',
        m3: 'Menus',
        spec: 'components/menus/guidelines',
        rule:
            'إجراءات مؤقتة من زرار النقط التلاتة أو ضغطة طويلة. الزرار يفضل pressed '
            'وهي مفتوحة. المجموعات بـ gap (واحد أو اتنين). العنصر اللي مش '
            'متاح يبان معطل مش يتشال. Vibrant للقوائم المهمة القليلة بس.',
        children: [
          Card.outlined(
            margin: EdgeInsets.zero,
            child: ContextMenuRegion(
              style: groupedMenuStyle,
              menuChildren: groupedMenuChildren(context, [
                [
                  MenuOption(
                    label: 'تعديل السعر',
                    icon: Icons.sell_outlined,
                    onPressed: () {},
                  ),
                  MenuOption(
                    label: 'طباعة باركود',
                    icon: Icons.qr_code_2,
                    onPressed: () {},
                  ),
                ],
                [
                  MenuOption(
                    label: 'إيقاف البيع',
                    icon: Icons.block,
                    onPressed: () {},
                  ),
                ],
              ]),
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('سكر أبيض 1 كجم'),
                subtitle: const Text('اضغط ضغطة طويلة: قائمة سياق'),
                trailing: MenuButton(
                  icon: Icons.more_vert,
                  tooltip: 'خيارات الصنف',
                  style: groupedMenuStyle,
                  menuChildren: groupedMenuChildren(context, [
                    [
                      MenuOption(
                        label: 'تعديل',
                        icon: Icons.edit_outlined,
                        onPressed: () {},
                      ),
                      MenuOption(
                        label: 'نسخ كصنف جديد',
                        icon: Icons.copy_outlined,
                        onPressed: () {},
                      ),
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.ios_share),
                        menuChildren: [
                          MenuItemButton(
                            onPressed: () {},
                            child: const Text('PDF'),
                          ),
                          MenuItemButton(
                            onPressed: () {},
                            child: const Text('Excel'),
                          ),
                        ],
                        child: const Text('تصدير'),
                      ),
                    ],
                    [
                      const MenuOption(
                        label: 'مرتجع',
                        icon: Icons.assignment_return_outlined,
                        supportingText: 'مفيش مبيعات للصنف ده النهارده',
                        onPressed: null,
                      ),
                      MenuOption(
                        label: 'حذف',
                        icon: Icons.delete_outline,
                        onPressed: () {},
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: TashilSpacing.md),
          Demo([
            MenuAnchor(
              style: groupedMenuStyle,
              menuChildren: groupedMenuChildren(context, [
                [
                  for (final (v, l) in const [
                    ('cash', 'نقدي'),
                    ('card', 'كارت'),
                    ('wallet', 'محفظة'),
                    ('credit', 'آجل'),
                  ])
                    MenuOption(
                      label: l,
                      style: MenuColorStyle.vibrant,
                      selected: _pay == v,
                      onPressed: () => setState(() => _pay = v),
                    ),
                ],
              ], style: MenuColorStyle.vibrant),
              builder: (context, c, _) => FilledButton.tonalIcon(
                onPressed: () => c.isOpen ? c.close() : c.open(),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('طريقة الدفع (vibrant)'),
              ),
            ),
          ]),
        ],
      ),
      SpecSection(
        title: 'قائمة اختيار',
        m3: 'Menus: select',
        spec: 'components/menus/guidelines#selecting',
        rule:
            'اختيار واحد: DropdownMenu، ولو القائمة طويلة اكتب للفلترة. '
            'اختيار متعدد: القائمة بتفضل مفتوحة لحد ما تقفلها.',
        children: [
          DropdownMenu<String>(
            initialSelection: _unit,
            label: const Text('الوحدة'),
            onSelected: (v) => setState(() => _unit = v ?? _unit),
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: 'pcs', label: 'قطعة'),
              DropdownMenuEntry(value: 'kg', label: 'كيلو'),
              DropdownMenuEntry(value: 'box', label: 'كرتونة'),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          DropdownMenu<String>(
            label: const Text('المورد'),
            hintText: 'اكتب للبحث',
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 260,
            leadingIcon: const Icon(Icons.search),
            initialSelection: _vendor,
            onSelected: (v) => setState(() => _vendor = v),
            dropdownMenuEntries: [
              for (final s in [
                'الأهرام للتوزيع',
                'النيل للتوريدات',
                'الدلتا للمواد الغذائية',
                'جهينة',
                'دومتي',
                'إيديتا',
                'شيبسي',
                'بيبسي',
                'كوكاكولا',
                'لبنيتا',
                'المراعي',
                'فرج الله',
              ])
                DropdownMenuEntry(value: s, label: s),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          MenuAnchor(
            menuChildren: [
              for (final c in const [
                'الكمية',
                'سعر الشراء',
                'سعر البيع',
                'الربح',
                'الباركود',
              ])
                CheckboxMenuButton(
                  value: _columns.contains(c),
                  closeOnActivate: false,
                  onChanged: (v) => setState(
                    () => v == true ? _columns.add(c) : _columns.remove(c),
                  ),
                  child: Text(c),
                ),
            ],
            builder: (context, c, _) => OutlinedButton.icon(
              onPressed: () => c.isOpen ? c.close() : c.open(),
              icon: const Icon(Icons.view_column_outlined),
              label: Text('أعمدة التقرير (${_columns.length})'),
            ),
          ),
        ],
      ),
      SpecSection(
        title: 'الشرايح: الأنواع الأربعة',
        m3: 'Chips',
        spec: 'components/chips/guidelines',
        rule:
            'Assist لإجراء حسب السياق، Filter للتصفية، Input لحاجة كتبها '
            'المستخدم، Suggestion لاقتراح من النظام. الشرايح دايماً مجموعة، '
            'والنص 20 حرف بالكتير. الخطوة الأساسية (إتمام البيع) زرار مش شريحة.',
        children: [
          Demo([
            ActionChip(
              avatar: const Icon(Icons.print_outlined),
              label: const Text('اطبع'),
              onPressed: () {},
            ),
            FilterChip(
              label: const Text('قليل المخزون'),
              selected: true,
              onSelected: (_) {},
            ),
            InputChip(label: const Text('مشروبات'), onDeleted: () {}),
            ActionChip(label: const Text('سكر'), onPressed: () {}),
          ]),
        ],
      ),
      SpecSection(
        title: 'شرايح الإجراء',
        m3: 'Assist chips',
        spec: 'components/chips/guidelines#assist-chips',
        rule:
            'تحت المحتوى الأساسي، بتبدأ بفعل وأيقونة. ممكن تعرض التقدم '
            'والتأكيد (احفظ ثم اتحفظت). Elevated بس فوق صورة.',
        children: [
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(TashilSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تم البيع: 245.00 ج.م',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  Demo([
                    ActionChip(
                      avatar: const Icon(Icons.print_outlined),
                      label: const Text('اطبع الإيصال'),
                      onPressed: () {},
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.share_outlined),
                      label: const Text('ابعت واتساب'),
                      onPressed: () {},
                    ),
                    ActionChip(
                      avatar: Icon(
                        _saved ? Icons.check : Icons.bookmark_add_outlined,
                      ),
                      label: Text(_saved ? 'اتحفظت' : 'احفظ للعميل'),
                      onPressed: () => setState(() => _saved = !_saved),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: TashilSpacing.md),
          Container(
            height: 140,
            alignment: AlignmentDirectional.bottomStart,
            padding: const EdgeInsets.all(TashilSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TashilRadius.medium),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8D6E63), Color(0xFF263238)],
              ),
            ),
            child: Demo([
              ActionChip.elevated(
                avatar: const Icon(Icons.photo_camera_outlined),
                label: const Text('غيّر الصورة'),
                onPressed: () {},
              ),
              ActionChip.elevated(
                avatar: const Icon(Icons.crop),
                label: const Text('قص'),
                onPressed: () {},
              ),
            ]),
          ),
        ],
      ),
      SpecSection(
        title: 'شرايح التصفية',
        m3: 'Filter chips',
        spec: 'components/chips/guidelines#filter-chips',
        rule:
            'علامة صح لما تتختار. المجموعة الواحدة يا اختيار واحد يا متعدد، '
            'مش الاتنين. لو زادت عن صفين تبقى صف واحد بيتسحب. '
            'ممنوع مجموعة فيها اختيار واحد بس. ChoiceChip ممنوع.',
        children: [
          Text('اختيار متعدد', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: TashilSpacing.sm),
          Demo([
            for (final f in const ['قليل المخزون', 'نفد', 'بدون باركود'])
              FilterChip(
                label: Text(f),
                selected: _filters.contains(f),
                onSelected: (v) =>
                    setState(() => v ? _filters.add(f) : _filters.remove(f)),
              ),
          ]),
          const SizedBox(height: TashilSpacing.md),
          Text('اختيار واحد', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: TashilSpacing.sm),
          Demo([
            for (final c in const ['اليوم', 'الأسبوع', 'الشهر'])
              FilterChip(
                label: Text(c),
                selected: _choice == c,
                onSelected: (_) => setState(() => _choice = c),
              ),
          ]),
          const SizedBox(height: TashilSpacing.md),
          Text(
            'بتفتح قائمة (الشريحة كلها بتفتحها)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: TashilSpacing.sm),
          Demo([
            MenuFilterChip<String>(
              label: 'التصنيف',
              value: _category,
              options: const {
                'drinks': 'مشروبات',
                'grocery': 'بقالة',
                'cleaning': 'منظفات',
              },
              onChanged: (v) => setState(() => _category = v),
            ),
            MenuFilterChip<String>(
              label: 'المورد',
              value: _supplier,
              options: const {'a': 'الأهرام', 'b': 'النيل للتوزيع'},
              onChanged: (v) => setState(() => _supplier = v),
            ),
          ]),
          const SizedBox(height: TashilSpacing.md),
          Text(
            'صف واحد بيتسحب بالعرض',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: TashilSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in const [
                  'مشروبات',
                  'بقالة',
                  'منظفات',
                  'ألبان',
                  'حلويات',
                  'مجمدات',
                  'خضار',
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: TashilSpacing.sm,
                    ),
                    child: FilterChip(
                      label: Text(c),
                      selected: _row.contains(c),
                      onSelected: (v) =>
                          setState(() => v ? _row.add(c) : _row.remove(c)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      SpecSection(
        title: 'شرايح الإدخال',
        m3: 'Input chips',
        spec: 'components/chips/guidelines#input-chips',
        rule:
            'جوه حقل الكتابة. Enter أو فاصلة تعمل شريحة. Backspace مرة '
            'تحدد آخر شريحة، ومرة تانية تمسحها. زرار المسح دايماً في آخر الشريحة.',
        children: [
          InputChipField(
            label: 'باركودات إضافية للصنف',
            hint: 'اكتب الباركود واضغط Enter',
            avatar: Icons.qr_code_2,
            values: _barcodes,
            onChanged: (v) => setState(() => _barcodes = v),
          ),
        ],
      ),
      SpecSection(
        title: 'شرايح الاقتراحات',
        m3: 'Suggestion chips',
        spec: 'components/chips/guidelines#suggestion-chips',
        rule:
            'اقتراحات من النظام (عمليات بحث سابقة، رد سريع). '
            'أسماء أو جمل قصيرة، من غير أيقونة.',
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'ابحث عن صنف',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: TashilSpacing.sm),
          Demo([
            for (final q in const ['سكر', 'زيت عباد', 'أرز 5 كجم'])
              ActionChip(label: Text(q), onPressed: () => _search.text = q),
          ]),
        ],
      ),
      SpecSection(
        title: 'الاختيارات',
        m3: 'Checkbox, Radio, Switch',
        spec: 'components/checkbox',
        children: [
          CheckboxListTile(
            value: _check,
            onChanged: (v) => setState(() => _check = v ?? false),
            title: const Text('طباعة الفاتورة تلقائياً'),
          ),
          SwitchListTile(
            value: _switch,
            onChanged: (v) => setState(() => _switch = v),
            title: const Text('تنبيه عند نفاد المخزون'),
          ),
          RadioGroup<String>(
            groupValue: _unit,
            onChanged: (v) => setState(() => _unit = v ?? _unit),
            child: const Column(
              children: [
                RadioListTile(value: 'pcs', title: Text('قطعة')),
                RadioListTile(value: 'kg', title: Text('كيلو')),
              ],
            ),
          ),
        ],
      ),
      const SpecSection(
        title: 'المنزلق',
        m3: 'Sliders',
        spec: 'components/sliders/guidelines',
        rule:
            'التغيير بيبان فوراً وانت بتحرك. Standard من الصفر، Centered '
            'لما الافتراضي في النص، Range لحد أدنى وأقصى (أفقي بس). نقط '
            'توقف قليلة. أيقونة جوه المسار من M وأكبر بس، ومش في centered '
            'أو range. XL للحظات المهمة بس.',
        children: [SlidersDemo()],
      ),
      SpecSection(
        title: 'التاريخ',
        m3: 'Date pickers',
        spec: 'components/date-pickers/guidelines',
        rule:
            'في الفورم: حقل تاريخ يتكتب بالكيبورد وجنبه زرار تقويم. على '
            'SUNMI (شاشة compact) التقويم بيفتح modal، ومن 600dp بيفتح تحت '
            'الحقل (docked). للتواريخ البعيدة زي الصلاحية الكتابة أسرع، '
            'والحقل بيقبل 15/4/2027 وبيقبل الأرقام العربية.',
        children: [
          DateField(
            label: 'تاريخ الفاتورة',
            value: _invoiceDate,
            firstDate: DateTime(2024),
            lastDate: DateTime(2030, 12, 31),
            onChanged: (d) => setState(() => _invoiceDate = d),
          ),
          const SizedBox(height: TashilSpacing.md),
          DateField(
            label: 'تاريخ الصلاحية (docked)',
            value: _expiry,
            docked: true,
            firstDate: DateTime(2024),
            lastDate: DateTime(2035, 12, 31),
            onChanged: (d) => setState(() => _expiry = d),
          ),
        ],
      ),
      SpecSection(
        title: 'فترة تاريخ',
        m3: 'Date range picker',
        spec: 'components/date-pickers/guidelines',
        rule:
            'للتقارير: الفترات الجاهزة (اليوم، الأسبوع، الشهر) ButtonGroup، '
            'و"فترة مخصصة" بتفتح منتقي الفترة بملء الشاشة على الموبايل.',
        children: [
          Demo([
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(
                _range == null
                    ? 'فترة مخصصة'
                    : '${loc.formatShortMonthDay(_range!.start)} – '
                          '${loc.formatShortMonthDay(_range!.end)}',
              ),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2030, 12, 31),
                  initialDateRange: _range,
                  initialEntryMode: DatePickerEntryMode.calendarOnly,
                );
                if (r != null) setState(() => _range = r);
              },
            ),
          ]),
        ],
      ),
      SpecSection(
        title: 'الوقت',
        m3: 'Time pickers',
        spec: 'components/time-pickers/guidelines',
        rule:
            'Scroll جوه الفورم (يفضل inline). الـ Dial في dialog بس. زرار '
            'الكيبورد لازم يبقى موجود. 12 أو 24 ساعة حسب إعداد الجهاز. لو '
            'الأوقات محددة (كل ربع ساعة) استخدم ButtonGroup أو قائمة.',
        children: [
          Text(
            'موعد قفل الوردية: ${_shiftClose.format(context)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: TashilSpacing.sm),
          ScrollTimePicker(
            value: _shiftClose,
            use24HourFormat: _time24,
            onChanged: (t) => setState(() => _shiftClose = t),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _time24,
            onChanged: (v) => setState(() => _time24 = v),
            title: const Text('نظام 24 ساعة'),
          ),
          Demo([
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: const Text('الساعة (Dial)'),
              onPressed: () => showTimePicker(
                context: context,
                initialTime: _shiftClose,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(alwaysUse24HourFormat: _time24),
                  child: child!,
                ),
              ),
            ),
          ]),
        ],
      ),
      const SpecSection(
        title: 'حقول التمرير',
        m3: 'Scroll fields',
        spec: 'components/scroll-fields/guidelines',
        rule:
            'لاختيار رقم أو وحدة (وزن، كمية، وحدة) من قائمة قصيرة. اسحب أو '
            'اضغط على الرقم اللي فوق أو تحت. زرار الكيبورد جنبهم دايماً. '
            'لحد 4 أرقام، وللقوائم الطويلة خطوات (الجرام كل 50). اسم فوق كل '
            'حقل لما يبقوا جنب بعض. للوقت استخدم منتقي الوقت.',
        children: [ScrollFieldsDemo()],
      ),
    ]);
  }
}
