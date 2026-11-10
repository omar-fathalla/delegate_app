import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_profile_edit_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Supervisor submits a national-ID change for super-admin / tech approval.
class UpdateNationalIdRequestSheet extends StatefulWidget {
  final Delegate supervisor;
  final String currentNationalId;
  final String companyUID;
  final String? delegateUid;
  final String? requestId;
  final String delegateName;

  const UpdateNationalIdRequestSheet({
    super.key,
    required this.supervisor,
    required this.currentNationalId,
    required this.companyUID,
    required this.delegateName,
    this.delegateUid,
    this.requestId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Delegate supervisor,
    required String currentNationalId,
    required String companyUID,
    required String delegateName,
    String? delegateUid,
    String? requestId,
  }) {
    final sheet = UpdateNationalIdRequestSheet(
      supervisor: supervisor,
      currentNationalId: currentNationalId,
      companyUID: companyUID,
      delegateName: delegateName,
      delegateUid: delegateUid,
      requestId: requestId,
    );
    final isDesktop = MediaQuery.of(context).size.width > 768;
    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: sheet,
          ),
        ),
      );
    }
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  @override
  State<UpdateNationalIdRequestSheet> createState() =>
      _UpdateNationalIdRequestSheetState();
}

class _UpdateNationalIdRequestSheetState
    extends State<UpdateNationalIdRequestSheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await DelegateProfileEditRepository().submitNationalIdUpdate(
        companyUID: widget.companyUID,
        newNationalId: _controller.text.trim(),
        delegateUid: widget.delegateUid,
        requestId: widget.requestId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DelegateProfileEditException catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'تعذر إرسال الطلب. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final content = Material(
      color: colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'طلب تعديل الرقم القومي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'المندوب: ${widget.delegateName}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                'الرقم الحالي: ${widget.currentNationalId.isEmpty ? "غير متوفر" : widget.currentNationalId}',
                style: const TextStyle(fontSize: 14, letterSpacing: 0.5),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(14),
                ],
                decoration: InputDecoration(
                  labelText: 'الرقم القومي الجديد',
                  helperText: '14 رقمًا. سيُراجع الطلب من الإدارة العليا أو الدعم الفني.',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length != 14) return 'الرقم القومي يجب أن يكون 14 رقمًا';
                  if (t == widget.currentNationalId.trim()) {
                    return 'أدخل رقماً مختلفاً عن الرقم الحالي';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'جاري الإرسال...' : 'إرسال الطلب للاعتماد'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );

    final isSheet = MediaQuery.of(context).size.width <= 768 &&
        context.findAncestorWidgetOfExactType<Dialog>() == null;
    if (isSheet) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(top: false, child: content),
      );
    }
    return content;
  }
}
