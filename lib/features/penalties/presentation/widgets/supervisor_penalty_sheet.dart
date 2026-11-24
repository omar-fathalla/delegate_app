import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';

/// TAS-320: a supervisor delegate records a penalty on a delegate of its
/// company. The server (`createSupervisorPenalty`) checks the supervisor and
/// the company, issues the penalty at once and the payroll deducts it.
class SupervisorPenaltySheet extends StatefulWidget {
  final Delegate delegate;
  final Delegate supervisor;

  /// Test seam: replaces the callable.
  final Future<void> Function(Map<String, dynamic> payload)? submitOverride;

  const SupervisorPenaltySheet({
    super.key,
    required this.delegate,
    required this.supervisor,
    this.submitOverride,
  });

  static const double maxFine = 10000;

  /// Who sees «إضافة جزاء»: a supervisor delegate, on another delegate of its
  /// own company.
  static bool canAdd({required Delegate? viewer, required Delegate target}) {
    if (viewer == null) return false;
    if (viewer.position != DelegatePosition.supervisor) return false;
    if (viewer.companyUID.isEmpty || viewer.companyUID != target.companyUID) {
      return false;
    }
    return viewer.uid != target.uid;
  }

  static Future<bool?> show(
    BuildContext context, {
    required Delegate delegate,
    required Delegate supervisor,
  }) {
    final isDesktop = MediaQuery.of(context).size.width > 768;
    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SupervisorPenaltySheet(
              delegate: delegate,
              supervisor: supervisor,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SupervisorPenaltySheet(delegate: delegate, supervisor: supervisor),
    );
  }

  @override
  State<SupervisorPenaltySheet> createState() => _SupervisorPenaltySheetState();
}

class _SupervisorPenaltySheetState extends State<SupervisorPenaltySheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  ViolationCategory _category = ViolationCategory.protocolBreach;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;
    setState(() => _submitting = true);
    final payload = <String, dynamic>{
      'organizationUID': widget.delegate.organizationUID,
      'companyUID': widget.delegate.companyUID,
      'targetDelegateId': widget.delegate.uid,
      'title': _title.text.trim(),
      'category': _category.toFirestoreString(),
      'incidentDescription': _description.text.trim(),
      'fineAmount': double.parse(_amount.text.trim()),
    };
    try {
      if (widget.submitOverride != null) {
        await widget.submitOverride!(payload);
      } else {
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('createSupervisorPenalty').call(payload);
      }
      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        'تم تسجيل الجزاء، وهيتخصم من مرتب الشهر.',
      );
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackBar.showError(context, e.message ?? 'تعذر تسجيل الجزاء.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackBar.showError(context, 'تعذر تسجيل الجزاء. حاول تاني.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 768;
    final name = widget.delegate.fullName.isNotEmpty
        ? widget.delegate.fullName
        : '${widget.delegate.firstName} ${widget.delegate.lastName}'.trim();

    final body = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إضافة جزاء: $name',
                  key: const Key('supervisor_penalty_title_text'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'الجزاء بيتسجل على طول ويتخصم من مرتب الشهر الحالي.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ViolationCategory>(
            key: const Key('supervisor_penalty_category'),
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'نوع المخالفة',
              prefixIcon: Icon(Icons.category_rounded),
            ),
            items: [
              for (final c in ViolationCategory.values)
                DropdownMenuItem(value: c, child: Text(c.displayName)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('supervisor_penalty_title'),
            controller: _title,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'سبب الجزاء',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.length < 2) return 'اكتب سبب الجزاء';
              if (t.length > 120) return 'السبب طويل (أقصى 120 حرف)';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('supervisor_penalty_amount'),
            controller: _amount,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'قيمة الجزاء (ج.م)',
              prefixIcon: Icon(Icons.payments_rounded),
            ),
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              if (n == null || n <= 0) return 'اكتب قيمة أكبر من صفر';
              if (n > SupervisorPenaltySheet.maxFine) {
                return 'أقصى قيمة ${SupervisorPenaltySheet.maxFine.toStringAsFixed(0)} ج.م';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('supervisor_penalty_description'),
            controller: _description,
            enabled: !_submitting,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'تفاصيل (اختياري)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('supervisor_penalty_submit'),
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gavel_rounded),
                    label: const Text('تسجيل الجزاء'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(child: body),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}
