import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// نافذة أمان مخصصة عند محاولة الدخول من جهاز غير مطابق لجهاز المندوب المعتمد
class DeviceLockDialog extends StatefulWidget {
  final String? boundDeviceModel;
  final String? currentDeviceModel;
  final String? delegateName;
  final Delegate? delegate;
  final bool requestAlreadyFiled;

  const DeviceLockDialog({
    super.key,
    this.boundDeviceModel,
    this.currentDeviceModel,
    this.delegateName,
    this.delegate,
    this.requestAlreadyFiled = false,
  });

  static Future<void> show(
    BuildContext context, {
    String? boundDeviceModel,
    String? currentDeviceModel,
    String? delegateName,
    Delegate? delegate,
    bool requestAlreadyFiled = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeviceLockDialog(
        boundDeviceModel: boundDeviceModel,
        currentDeviceModel: currentDeviceModel,
        delegateName: delegateName,
        delegate: delegate,
        requestAlreadyFiled: requestAlreadyFiled,
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
    if (widget.requestAlreadyFiled) {
      if (mounted) {
        setState(() {
          _isPending = true;
          _isChecking = false;
        });
      }
      return;
    }
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

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  void _closeWithSubmittedMessage() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final message = _l10n.deviceLockRequestSent;
    Navigator.of(context).pop();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
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
  }

  Future<void> _handleSendUnbindRequest() async {
    // Idempotent with delegateLoginV2, which already upserts a pending
    // unbind request on a device mismatch. If a request is already filed
    // (or the dialog was opened from AuthError(device_mismatch) without a
    // Delegate), just close and confirm — do not create a second doc.
    if (widget.delegate == null) {
      if (widget.requestAlreadyFiled || _isPending) {
        _closeWithSubmittedMessage();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.deviceLockCannotIdentifyDelegate)),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await DeviceBindingService.submitUnbindRequest(
        delegate: widget.delegate!,
        currentDeviceModel: widget.currentDeviceModel,
      );
      if (!mounted) return;
      _closeWithSubmittedMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.deviceLockSendError('$e')),
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
      canPop: false,
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
                _l10n.deviceLockTitle,
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

              // 5. Mandatory unbind-request button (not dismissible).
              if (_isChecking)
                const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator.adaptive()),
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
                        : Icon(
                            _isPending
                                ? Icons.hourglass_top_rounded
                                : Icons.phonelink_erase_rounded,
                            size: 20,
                          ),
                    label: Text(
                      _isSubmitting
                          ? _l10n.deviceLockSubmitting
                          : (_isPending
                              ? _l10n.deviceLockPendingUnbindButton
                              : _l10n.deviceLockSendUnbindButton),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
