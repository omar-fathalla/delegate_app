import 'package:flutter/material.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// نافذة أمان مخصصة عند محاولة الدخول من جهاز غير مطابق لجهاز المندوب المعتمد
class DeviceLockDialog extends StatefulWidget {
  final String? boundDeviceModel;
  final String? currentDeviceModel;
  final String? delegateName;
  final Delegate? delegate;

  const DeviceLockDialog({
    super.key,
    this.boundDeviceModel,
    this.currentDeviceModel,
    this.delegateName,
    this.delegate,
  });

  static Future<void> show(
    BuildContext context, {
    String? boundDeviceModel,
    String? currentDeviceModel,
    String? delegateName,
    Delegate? delegate,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeviceLockDialog(
        boundDeviceModel: boundDeviceModel,
        currentDeviceModel: currentDeviceModel,
        delegateName: delegateName,
        delegate: delegate,
      ),
    );
  }

  @override
  State<DeviceLockDialog> createState() => _DeviceLockDialogState();
}

class _DeviceLockDialogState extends State<DeviceLockDialog> {
  bool _isChecking = true;
  bool _isPending = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
  }

  Future<void> _checkExistingRequest() async {
    if (widget.delegate != null && widget.delegate!.uid.isNotEmpty) {
      final pending = await DeviceBindingService.hasPendingUnbindRequest(widget.delegate!.uid);
      if (mounted) {
        setState(() {
          _isPending = pending;
          _isChecking = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _handleSendUnbindRequest() async {
    if (widget.delegate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد بيانات المندوب لإرسال الطلب')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final success = await DeviceBindingService.submitUnbindRequest(
        delegate: widget.delegate!,
        currentDeviceModel: widget.currentDeviceModel,
      );

      if (!mounted) return;

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final primaryColor = Theme.of(context).colorScheme.primary;

      // إغلاق النافذة المنبثقة تلقائياً فور إرسال الطلب كما طلب المستخدم
      Navigator.of(context).pop();

      final message = success
          ? 'تم إرسال طلب فك الارتباط بنجاح، وسيتم فك الارتباط خلال 5 دقائق لتتمكن من تسجيل الدخول.'
          : 'طلب فك الارتباط قيد المراجعة لدى الإدارة بالفعل، وسيتم فك الارتباط خلال 5 دقائق.';

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء إرسال الطلب: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final boundModel = (widget.boundDeviceModel != null && widget.boundDeviceModel!.trim().isNotEmpty)
        ? widget.boundDeviceModel!
        : 'جهاز معتمد سابق';

    return PopScope(
      canPop: true,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerHigh,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header Shield / Lock Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Icon(
                  Icons.phonelink_lock_rounded,
                  color: colorScheme.error,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),

              // 2. Title
              Text(
                'تنبيه أمان: الحساب مقترن بجهاز آخر',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),

              // 3. Explanation
              Text(
                'عزيزي المندوب، هذا الحساب مصرح له بالعمل فقط من خلال جهازك المعتمد المسجل مسبقاً لدى النظام.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // 4. Device Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'الجهاز المعتمد للحساب:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 26),
                        child: Text(
                          boundModel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    if (widget.currentDeviceModel != null && widget.currentDeviceModel!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.cancel_rounded, color: colorScheme.error, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'الجهاز الحالي المستخدم:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 26),
                          child: Text(
                            widget.currentDeviceModel!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Text(
                'إذا قمت بتغيير هاتفك أو استبداله، يمكنك إرسال طلب لفك ارتباط جهازك القديم ليتم اعتماده من قِبل الإدارة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              // 5. Action: Send Unbind Request OR Pending Status
              if (_isChecking)
                const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (_isPending)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طلب فك الارتباط قيد المراجعة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'تم استلام طلبك وبانتظار موافقة الإدارة. سيتم فك الارتباط خلال 5 دقائق لتتمكن من تسجيل الدخول.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _handleSendUnbindRequest,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.phonelink_erase_rounded, size: 20),
                    label: Text(
                      _isSubmitting ? 'جاري إرسال الطلب...' : 'إرسال طلب لفك الارتباط',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // 6. Close Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إغلاق',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
