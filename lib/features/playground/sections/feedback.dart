import 'dart:async';

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/motion.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/dialogs.dart';
import '../../../core/design/widgets/loading_indicator.dart';
import '../../../core/design/widgets/snackbars.dart';
import 'common.dart';
import 'sheets_demo.dart';
import 'side_sheets_demo.dart';
import 'snackbars_demo.dart';
import 'tooltips_demo.dart';

class FeedbackSection extends StatelessWidget {
  const FeedbackSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionList([
      SpecSection(
        title: 'حوار أساسي',
        m3: 'Basic dialog',
        spec: 'components/dialogs/guidelines',
        rule:
            'للحاجات المهمة اللي بتوقف الشغل بس. عنوان واضح، أزرار نصية، '
            'زرار التأكيد بيقول هيحصل إيه وعلى الطرف (شمال في العربي). '
            'لو المعلومة مش مهمة استخدم Snackbar.',
        children: [
          Demo([
            OutlinedButton(
              onPressed: () => showTashilDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  icon: const Icon(Icons.receipt_long_outlined),
                  title: const Text('إلغاء الفاتورة رقم 1042؟'),
                  content: const Text(
                    'هيتعمل مرتجع للمخزون، والفاتورة هتفضل في السجل كملغاة.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('رجوع'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('إلغاء الفاتورة'),
                    ),
                  ],
                ),
              ),
              child: const Text('تأكيد'),
            ),
            OutlinedButton(
              onPressed: () => showTashilDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (c) => AlertDialog(
                  icon: const Icon(Icons.print_disabled_outlined),
                  title: const Text('الطابعة مفيهاش ورق'),
                  content: const Text(
                    'الفاتورة اتحفظت. حط رول ورق جديد واطبعها من السجل.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('حسنًا'),
                    ),
                  ],
                ),
              ),
              child: const Text('إقرار بزرار واحد'),
            ),
            OutlinedButton(
              onPressed: () async {
                final r = await showChoiceDialog<String>(
                  context: context,
                  title: 'سبب المرتجع',
                  confirmLabel: 'تسجيل المرتجع',
                  options: const {
                    'damaged': 'تالف',
                    'expired': 'منتهي الصلاحية',
                    'wrong': 'صنف غلط',
                    'customer': 'العميل غيّر رأيه',
                    'price': 'خطأ في السعر',
                    'duplicate': 'اتسجل مرتين',
                    'other': 'سبب تاني',
                  },
                );
                if (r != null && context.mounted) {
                  showTashilSnackBar(context, 'اتسجل المرتجع');
                }
              },
              child: const Text('اختيار من قائمة'),
            ),
          ]),
        ],
      ),
      SpecSection(
        title: 'حوار بملء الشاشة',
        m3: 'Full-screen dialog',
        spec: 'components/dialogs/guidelines#full-screen-dialog',
        rule:
            'لفورم فيه كتابة على الموبايل بس، ومن 600dp يبقى حوار أساسي. '
            'بيفتح من الزرار بـ container transform. أخطاء الحقول تحت '
            'الحقل، وفشل الحفظ بس هو اللي ياخد حوار. لو قفلت وفيه تعديلات '
            'بيسألك تتجاهلها ولا لأ.',
        children: [
          OpenContainer(
            transitionDuration: TashilTransitions.containerTransform(context),
            closedColor: Theme.of(context).colorScheme.primaryContainer,
            closedElevation: 3,
            closedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TashilRadius.large),
            ),
            openBuilder: (context, _) => const _NewProductDialog(),
            closedBuilder: (context, open) => InkWell(
              onTap: open,
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TashilSpacing.lg,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: TashilSpacing.sm),
                      Text(
                        'صنف جديد',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: TashilSpacing.sm),
          Text(
            'جرب: احفظ والاسم فاضي، اكتب حاجة واقفل، أو اكتب "فشل" في '
            'الاسم عشان تشوف حوار فشل الحفظ.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      const SpecSection(
        title: 'الورقة السفلية',
        m3: 'Bottom sheets',
        spec: 'components/bottom-sheets/guidelines',
        rule:
            'Modal على الموبايل بس: بدل القائمة لما الخيارات كتير أو محتاجة '
            'أيقونة ووصف. بتفتح على قد محتواها ومش أكتر من نص الشاشة، '
            'والطويلة تتسحب لملء الشاشة ويظهر زرار قفل. Standard للمحتوى '
            'اللي بيشتغل جنب الشاشة (السلة). دوسة على المقبض بتغير الارتفاع. '
            'من 840 بتبقى ورقة جانبية.',
        children: [SheetsDemo()],
      ),
      const SpecSection(
        title: 'الورقة الجانبية',
        m3: 'Side sheets',
        spec: 'components/side-sheets/guidelines',
        rule:
            'على الحافة (الشمال في العربي)، أقصى عرض 400. Modal على الموبايل '
            '(فوق المحتوى ولازم تتقفل)، وStandard من 840 (الصفحة بتضيق '
            'وتفضل شغالة). زرار قفل دايماً، والأزرار تحت بعد فاصل. اسحبها '
            'بالعرض عشان تقفلها (رجوع تنبؤي). سكرول رأسي بس.',
        children: [SideSheetsDemo()],
      ),
      const SpecSection(
        title: 'الإشعار السريع',
        m3: 'Snackbar',
        spec: 'components/snackbar/guidelines',
        rule:
            'رسالة قصيرة عن حاجة السيستم عملها، نص بس (سطرين بالكتير). '
            'زرار نصي واحد بالكتير، ومعاه زرار قفل والإشعار يفضل لحد ما '
            'يتقفل؛ من غيره يختفي بعد 4 ثواني. واحد بس في المرة، والجديد '
            'يشيل القديم. فوق الـ FAB وشريط التنقل، ومن 600 في النص. '
            'النتيجة تبان كمان مكان الإجراء نفسه.',
        children: [SnackbarsDemo()],
      ),
      const SpecSection(
        title: 'مؤشر التحميل',
        m3: 'Loading indicator',
        spec: 'components/loading-indicator/guidelines',
        rule:
            'الانتظار أقل من 200ms: ولا حاجة. من 200ms لـ 5 ثواني: مؤشر '
            'التحميل في نص المساحة الفاضية. أكتر من كده أو التقدم معروف: '
            'مؤشر تقدم. ما تبدلش من ده لده في نص العملية.',
        children: [
          Demo([
            LoadingIndicator(size: 24),
            LoadingIndicator(),
            LoadingIndicator(contained: true),
            LoadingIndicator(size: 96),
          ]),
          SizedBox(height: TashilSpacing.md),
          _LoadDemo(),
        ],
      ),
      const SpecSection(
        title: 'مؤشرات التقدم',
        m3: 'Progress indicators',
        spec: 'components/progress-indicators/guidelines',
        rule:
            'للعمليات الطويلة. Determinate لو نعرف النسبة (مزامنة 120 من '
            '300). الخطي على حافة الكارت أو تحت شريط التطبيق، والدائري '
            'الصغير جوه الزرار للعملية القصيرة.',
        children: [_ProgressDemo()],
      ),
      const SpecSection(
        title: 'السحب للتحديث',
        m3: 'Pull to refresh',
        spec: 'components/loading-indicator/guidelines#behavior',
        rule:
            'اسحب القائمة لتحت. مؤشر التحميل contained بيظهر فوق المحتوى '
            'لحد ما التحديث يخلص.',
        children: [_PullToRefreshDemo()],
      ),
      const SpecSection(
        title: 'التلميح',
        m3: 'Tooltip',
        spec: 'components/tooltips/guidelines',
        rule:
            'العادي: سطر قصير لأي زرار أيقونة بس، فوق العنصر بـ 4 (و8 من '
            'نص عادي)، وتحته في شريط التطبيق. الغني: عنوان سطر واحد + شرح + '
            'زرارين نصيين بالكتير جنب بعض، تحت العنصر ناحية النهاية ومش '
            'بيغطيه. الاتنين بيختفوا بعد 1.5 ثانية، وواحد بس في المرة. الثابت '
            'بيفتح بالضغط ومش على زرار أيقونة. مفيش معلومة مهمة في تلميح.',
        children: [TooltipsDemo()],
      ),
      SpecSection(
        title: 'اللافتة',
        m3: 'Banner',
        spec: 'components/banner',
        rule: 'لحالة مستمرة على مستوى الشاشة: الجهاز أوفلاين، الوردية مقفولة.',
        children: [
          MaterialBanner(
            leading: const Icon(Icons.cloud_off_outlined),
            content: const Text(
              'أنت شغال أوفلاين. المبيعات بتتحفظ وهتتزامن أول ما النت يرجع.',
            ),
            actions: [TextButton(onPressed: () {}, child: const Text('تمام'))],
          ),
        ],
      ),
    ]);
  }
}

/// Full-screen "new product" form used by the dialogs demo.
class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog();

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  String? _nameError;
  String? _priceError;
  bool _saving = false;

  bool get _dirty => _name.text.isNotEmpty || _price.text.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'اكتب اسم الصنف' : null;
      _priceError = double.tryParse(_price.text) == null
          ? 'اكتب السعر بالأرقام، مثلاً 12.50'
          : null;
    });
    if (_nameError != null || _priceError != null) return;
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _saving = false);
    if (_name.text.contains('فشل')) {
      await showTashilDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تعذّر الحفظ'),
          content: const Text(
            'مساحة التخزين على الجهاز خلصت. امسح صور أو ملفات قديمة '
            'وجرب تاني. البيانات اللي كتبتها لسه موجودة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    showTashilSnackBar(context, 'اتضاف "${_name.text}"');
    _name.clear();
    _price.clear();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'صنف جديد',
      saveLabel: 'حفظ',
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() => _nameError = null),
            decoration: InputDecoration(
              labelText: 'اسم الصنف',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: TashilSpacing.md),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _priceError = null),
            decoration: InputDecoration(
              labelText: 'سعر البيع',
              suffixText: 'ج.م',
              errorText: _priceError,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading a short list: nothing for 200ms, then the loading indicator in
/// the middle of the empty space, then the content.
class _LoadDemo extends StatefulWidget {
  const _LoadDemo();

  @override
  State<_LoadDemo> createState() => _LoadDemoState();
}

class _LoadDemoState extends State<_LoadDemo> {
  bool _loading = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _load() {
    setState(() => _loading = true);
    _t = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card.outlined(
          margin: EdgeInsets.zero,
          child: SizedBox(
            height: 152,
            child: _loading
                ? const Center(child: DelayedLoadingIndicator())
                : const Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('أحمد محمود'),
                        subtitle: Text('رصيد آجل'),
                      ),
                      ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('منى السيد'),
                        subtitle: Text('عميل نقدي'),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: TashilSpacing.sm),
        OutlinedButton(
          onPressed: _loading ? null : _load,
          child: const Text('حمّل العملاء'),
        ),
      ],
    );
  }
}

/// Determinate sync with a known count, indeterminate edge bar, and a
/// short task inside a button.
class _ProgressDemo extends StatefulWidget {
  const _ProgressDemo();

  @override
  State<_ProgressDemo> createState() => _ProgressDemoState();
}

class _ProgressDemoState extends State<_ProgressDemo> {
  static const _total = 300;
  int _done = 120;
  bool _printing = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _sync() {
    _t?.cancel();
    setState(() => _done = 0);
    _t = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (!mounted) return t.cancel();
      setState(() => _done = (_done + 6).clamp(0, _total));
      if (_done >= _total) t.cancel();
    });
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _printing = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Indeterminate, on the top edge of its container.
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(TashilSpacing.lg),
                child: Text('بيحمّل تقرير الشهر…', style: text.bodyMedium),
              ),
            ],
          ),
        ),
        const SizedBox(height: TashilSpacing.lg),
        // Determinate with a stop dot at the end of the track.
        Text('مزامنة الفواتير: $_done من $_total', style: text.labelLarge),
        const SizedBox(height: TashilSpacing.sm),
        LinearProgressIndicator(
          value: _done / _total,
          semanticsLabel: 'مزامنة الفواتير',
        ),
        const SizedBox(height: TashilSpacing.md),
        Demo([
          SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(value: _done / _total),
          ),
          const SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(),
          ),
          OutlinedButton(onPressed: _sync, child: const Text('زامن')),
        ]),
        const SizedBox(height: TashilSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.print_outlined),
            label: Text(_printing ? 'بيطبع…' : 'اطبع الإيصال'),
          ),
        ),
      ],
    );
  }
}

/// Pull to refresh with the official RefreshIndicator (no spinner) and a
/// contained loading indicator on top, as in the M3 guidelines.
class _PullToRefreshDemo extends StatefulWidget {
  const _PullToRefreshDemo();

  @override
  State<_PullToRefreshDemo> createState() => _PullToRefreshDemoState();
}

class _PullToRefreshDemoState extends State<_PullToRefreshDemo> {
  RefreshIndicatorStatus? _status;
  int _version = 1;

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final showing =
        _status == RefreshIndicatorStatus.armed ||
        _status == RefreshIndicatorStatus.refresh;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            RefreshIndicator.noSpinner(
              onRefresh: _refresh,
              onStatusChange: (s) => setState(() => _status = s),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 6; i++)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('فاتورة ${1040 + i}'),
                      subtitle: Text('تحديث رقم $_version'),
                    ),
                ],
              ),
            ),
            Positioned(
              top: TashilSpacing.md,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedScale(
                  scale: showing ? 1 : 0,
                  duration: TashilMotion.scaled(
                    context,
                    TashilMotion.fast.duration,
                  ),
                  curve: TashilMotion.fast.curve,
                  child: showing
                      ? const LoadingIndicator(contained: true)
                      : const SizedBox.square(dimension: 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
