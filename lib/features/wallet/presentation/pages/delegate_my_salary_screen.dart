import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/money.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:delegate_app/features/hr/data/delegate_payroll_source.dart';
import 'package:delegate_app/features/hr/domain/services/delegate_payroll_calculator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-366 «مرتبي»: the delegate's (and the supervisor delegate's) expected
/// net for this month and the one before, from the same calculation as the
/// HR payroll screen. Labelled as an estimate: payroll is not stored, so HR
/// sets the final number (USER-ROLES-LOGIC.md 5.12).
class DelegateMySalaryScreen extends StatefulWidget {
  const DelegateMySalaryScreen({super.key, required this.delegate});

  final Delegate delegate;

  /// Tests swap in a fake Firestore / clock here.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;
  @visibleForTesting
  static DateTime Function()? debugNow;

  @override
  State<DelegateMySalaryScreen> createState() => _DelegateMySalaryScreenState();
}

/// Agreed text (USER-SCENARIOS/01-delegate-messages.md 8.5).
const kSalaryEstimateNote = 'ده تقدير، والرقم النهائي بيحدده الـ HR آخر الشهر';
const kPreviousMonthNote = 'تقديري، ممكن يختلف عن اللي اتصرف';

const _arabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _monthTitle(DateTime m) => '${_arabicMonths[m.month - 1]} ${m.year}';

class _DelegateMySalaryScreenState extends State<DelegateMySalaryScreen> {
  DelegatePayrollEstimate? _estimate;
  bool _loading = true;
  bool _failed = false;

  DateTime get _now => DelegateMySalaryScreen.debugNow?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _estimate == null;
      _failed = false;
    });
    try {
      final db = DelegateMySalaryScreen.debugFirestore?.call() ?? FirebaseFirestore.instance;
      final estimate = await DelegatePayrollSource(db).load(widget.delegate, now: _now);
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _loading = false;
      });
    } catch (e) {
      debugPrint('DelegateMySalaryScreen: load failed ($e)');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _estimate == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final current = DateTime(now.year, now.month);
    final previous = DateTime(now.year, now.month - 1);
    return Scaffold(
      appBar: AppBar(title: const Text('مرتبي')),
      body: _failed
          ? Center(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'فيه مشكلة عندنا',
                message: 'مش منك. جرّب تاني بعد دقيقة',
                action: FilledButton.tonal(onPressed: _load, child: const Text('جرّب تاني')),
              ),
            )
          : PullToRefresh(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsetsDirectional.all(TashilSpacing.page),
                children: [
                  SkeletonSwitcher(
                    loading: _loading,
                    skeleton: const Column(
                      children: [SummaryCardSkeleton(facts: 3), SummaryCardSkeleton(facts: 3)],
                    ),
                    child: _estimate == null
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              _MonthSalaryCard(
                                key: const Key('my_salary_current'),
                                title: _monthTitle(current),
                                item: _estimate!.current,
                              ),
                              const SizedBox(height: TashilSpacing.md),
                              _MonthSalaryCard(
                                key: const Key('my_salary_previous'),
                                title: _monthTitle(previous),
                                item: _estimate!.previous,
                                note: kPreviousMonthNote,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MonthSalaryCard extends StatelessWidget {
  const _MonthSalaryCard({super.key, required this.title, required this.item, this.note});

  final String title;
  final DelegatePayrollItem item;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hours = item.totalWorkMinutes ~/ 60;
    final minutes = (item.totalWorkMinutes % 60).toString().padLeft(2, '0');

    Widget row(String label, String value, {bool zero = false, Key? key}) => Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: TashilSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Text(
                value,
                key: key,
                style: tt.titleSmall?.copyWith(color: zero ? cs.onSurfaceVariant : cs.onSurface),
              ),
            ],
          ),
        );

    String days(int n) => n == 1 ? 'يوم واحد' : (n == 2 ? 'يومين' : '${Bidi.ltr('$n')} يوم');

    return Card.filled(
      margin: EdgeInsetsDirectional.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(TashilSpacing.sm),
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                  child: Icon(Icons.payments_rounded, size: 20, color: cs.onPrimary),
                ),
                const SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tt.titleMedium),
                      const SizedBox(height: TashilSpacing.xs),
                      SummaryLabel(
                        'تقديري',
                        container: cs.secondaryContainer,
                        onContainer: cs.onSecondaryContainer,
                      ),
                      if (note != null) ...[
                        const SizedBox(height: TashilSpacing.xs),
                        Text(note!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.lg),
            Text('الصافي المتوقع', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            Text(
              Bidi.ltr(Money.formatEgp(item.netSalary)),
              key: const Key('my_salary_net'),
              style: tt.headlineSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: TashilSpacing.xs),
            Text(kSalaryEstimateNote, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const Divider(height: TashilSpacing.xl),
            row('أيام الحضور', days(item.attendedDays), zero: item.attendedDays == 0),
            row('ساعات الشغل', Bidi.ltr('$hours:$minutes'), zero: item.totalWorkMinutes == 0),
            row('إجازات مدفوعة', days(item.approvedLeaveDays), zero: item.approvedLeaveDays == 0),
            if (item.unpaidLeaveDays > 0) row('إجازات من غير مرتب', days(item.unpaidLeaveDays)),
            row('الغياب', days(item.absentDays), zero: item.absentDays == 0),
            row(
              'الجزاءات اللي هتتخصم',
              Bidi.ltr(Money.formatEgp(item.penaltiesDeductions)),
              zero: item.penaltiesDeductions == 0,
              key: const Key('my_salary_penalties'),
            ),
            if (item.forgottenSessionDays > 0) ...[
              const SizedBox(height: TashilSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: TashilSpacing.sm),
                  Expanded(
                    child: Text(
                      // Message 3.17 (TAS-362): hours wait for HR.
                      '${days(item.forgottenSessionDays)} من غير انصراف، فساعاتهم مش محسوبة لحد ما الـ HR يسجلها. كلّم المشرف',
                      key: const Key('my_salary_forgotten'),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
