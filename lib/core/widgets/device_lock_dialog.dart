import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
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
    // TAS-349 (C-27): kit dialog transition.
    return showTashilDialog<void>(
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
    final message = _l10n.deviceLockRequestSent;
    Navigator.of(context).pop();
    // TAS-349 (C-30): text only, styled by the theme like showTashilSnackBar
    // (the dialog context is gone after pop, so the messenger is used).
    scaffoldMessenger.removeCurrentSnackBar();
    scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
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
      showTashilSnackBar(context, _l10n.deviceLockSendError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final boundModel = (widget.boundDeviceModel != null && widget.boundDeviceModel!.trim().isNotEmpty)
        ? widget.boundDeviceModel!
        : 'جهاز معتمد سابق';

    final tt = theme.textTheme;
    final sem = theme.extension<TashilSemanticColors>();
    // TAS-349: kit dialog shape and colours from the theme; the lock is a
    // warning (not an error); text from the textTheme; theme buttons.
    Widget deviceRow(IconData icon, Color iconColor, String label, String value) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: TashilSpacing.sm),
                Text(label, style: tt.labelLarge),
              ],
            ),
            const SizedBox(height: TashilSpacing.xs),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 26),
              child: Text(
                value,
                style: tt.bodyMedium?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        );

    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(TashilSpacing.lg),
                decoration: BoxDecoration(
                  color: sem?.warningContainer ?? colorScheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.phonelink_lock_rounded,
                  color: sem?.onWarningContainer ??
                      colorScheme.onTertiaryContainer,
                  size: 36,
                ),
              ),
              const SizedBox(height: TashilSpacing.lg),
              Text(
                _l10n.deviceLockTitle,
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(color: colorScheme.onSurface),
              ),
              const SizedBox(height: TashilSpacing.sm),
              Text(
                'عزيزي المندوب، هذا الحساب مصرح له بالعمل فقط من خلال جهازك المعتمد المسجل مسبقاً لدى النظام.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: TashilSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    deviceRow(
                      Icons.check_circle_rounded,
                      colorScheme.primary,
                      'الجهاز المعتمد للحساب:',
                      boundModel,
                    ),
                    if (widget.currentDeviceModel != null &&
                        widget.currentDeviceModel!.isNotEmpty) ...[
                      const Divider(height: TashilSpacing.lg),
                      deviceRow(
                        Icons.cancel_rounded,
                        colorScheme.onSurfaceVariant,
                        'الجهاز الحالي المستخدم:',
                        widget.currentDeviceModel!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: TashilSpacing.md),
              Text(
                'إذا قمت بتغيير هاتفك أو استبداله، يمكنك إرسال طلب لفك ارتباط جهازك القديم ليتم اعتماده من قِبل الإدارة.',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: TashilSpacing.lg),
              // Mandatory unbind-request button (not dismissible).
              if (_isChecking)
                const SizedBox(
                  height: 48,
                  child: Center(child: LoadingIndicator(size: 32)),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _handleSendUnbindRequest,
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isPending
                                ? Icons.hourglass_top_rounded
                                : Icons.phonelink_erase_rounded,
                          ),
                    label: Text(
                      _isSubmitting
                          ? _l10n.deviceLockSubmitting
                          : (_isPending
                              ? _l10n.deviceLockPendingUnbindButton
                              : _l10n.deviceLockSendUnbindButton),
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
