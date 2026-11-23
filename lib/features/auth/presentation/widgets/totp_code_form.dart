import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';

/// TOTP two-step verification step (TAS-207): a 6-digit code from the
/// user's authenticator app.

const int totpCodeLength = 6;
const String totpCodeHint =
    'أدخل الرمز المكوّن من 6 أرقام من تطبيق المصادقة '
    '(مثل Google Authenticator).';
const String totpCodeLengthError = 'أدخل الرمز المكوّن من 6 أرقام';
const String _totpGenericError =
    'تعذر التحقق من الرمز حالياً. تأكد من الاتصال بالإنترنت وحاول مرة أخرى.';

/// True when [code] is exactly six digits.
bool isValidTotpCode(String code) => RegExp(r'^\d{6}$').hasMatch(code.trim());

/// The code field with a connected Cancel / Confirm button group.
///
/// [onSubmit] checks the code. It throws an [AuthFailure] whose message is
/// shown under the field, so the user can retry. When it completes,
/// [onVerified] runs.
class TotpCodeForm extends StatefulWidget {
  const TotpCodeForm({
    super.key,
    required this.onSubmit,
    required this.onVerified,
    required this.onCancel,
    this.confirmLabel = 'تأكيد',
    this.autofocus = true,
  });

  final Future<void> Function(String code) onSubmit;
  final VoidCallback onVerified;
  final VoidCallback onCancel;
  final String confirmLabel;
  final bool autofocus;

  @override
  State<TotpCodeForm> createState() => _TotpCodeFormState();
}

class _TotpCodeFormState extends State<TotpCodeForm> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _done) return;
    final code = _controller.text.trim();
    if (!isValidTotpCode(code)) {
      setState(() => _error = totpCodeLengthError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (!mounted) return;
      _done = true;
      setState(() => _busy = false);
      widget.onVerified();
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message.isEmpty ? _totpGenericError : failure.message;
        _controller.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _totpGenericError;
        _controller.clear();
      });
    }
  }

  PinTheme _pinTheme(ColorScheme colorScheme, {Color? borderColor}) {
    return PinTheme(
      width: 44,
      height: 48,
      textStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? colorScheme.outlineVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: AutofillGroup(
            child: Pinput(
              key: const ValueKey('totp_code_input'),
              length: totpCodeLength,
              controller: _controller,
              autofillHints: const [AutofillHints.oneTimeCode],
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofocus: widget.autofocus,
              enabled: !_busy,
              closeKeyboardWhenCompleted: true,
              pinAnimationType: PinAnimationType.none,
              isCursorAnimationEnabled: false,
              animationDuration: AppMotionDurations.short4,
              animationCurve: AppMotionCurves.standardDecelerate,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              defaultPinTheme: _pinTheme(colorScheme),
              focusedPinTheme: _pinTheme(
                colorScheme,
                borderColor: colorScheme.primary,
              ),
              submittedPinTheme: _pinTheme(colorScheme),
              errorPinTheme: _pinTheme(
                colorScheme,
                borderColor: colorScheme.error,
              ),
              forceErrorState: _error != null,
              separatorBuilder: (_) => const SizedBox(width: 8),
              onChanged: (value) {
                if (_error != null && value.isNotEmpty) {
                  setState(() => _error = null);
                }
              },
              onCompleted: (_) => _confirm(),
              onSubmitted: (_) => _confirm(),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  key: const ValueKey('totp_code_error'),
                  style: TextStyle(fontSize: 13, color: colorScheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('totp_cancel'),
                    onPressed: _busy ? null : widget.onCancel,
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: colorScheme.outlineVariant),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('totp_confirm'),
                    onPressed: _busy ? null : _confirm,
                    child: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Text(
                            widget.confirmLabel,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Heading used by the login step and the re-auth sheet.
class TotpCodeHeader extends StatelessWidget {
  const TotpCodeHeader({super.key, this.subtitle = totpCodeHint});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_user_rounded, color: colorScheme.primary, size: 36),
        const SizedBox(height: 12),
        Text(
          'التحقق بخطوتين',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Full-screen login step after a right staff password on an account with
/// two-step verification (TAS-207). Same frame as the delegate phone step.
class TotpLoginView extends StatelessWidget {
  const TotpLoginView({
    super.key,
    required this.onSubmit,
    required this.onVerified,
    required this.onCancel,
  });

  final Future<void> Function(String code) onSubmit;
  final VoidCallback onVerified;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TotpCodeHeader(),
                        TotpCodeForm(
                          onSubmit: onSubmit,
                          onVerified: onVerified,
                          onCancel: onCancel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [child] as a Material 3 bottom sheet on mobile and a centered
/// dialog on wide web windows (AGENTS.md sheet rules).
Future<T?> showTotpAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final wide = WebRuntimePolicy.isWeb && MediaQuery.sizeOf(context).width > 768;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: builder(dialogContext),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                builder(sheetContext),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Asks for a TOTP code in a sheet and checks it with [onSubmit]. True once
/// the code is accepted, false when the user cancels.
Future<bool> showTotpCodeSheet(
  BuildContext context, {
  required Future<void> Function(String code) onSubmit,
  String subtitle = totpCodeHint,
}) async {
  final verified = await showTotpAdaptiveSheet<bool>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TotpCodeHeader(subtitle: subtitle),
        TotpCodeForm(
          onSubmit: onSubmit,
          onVerified: () => Navigator.of(sheetContext).pop(true),
          onCancel: () => Navigator.of(sheetContext).pop(false),
        ),
      ],
    ),
  );
  return verified ?? false;
}
