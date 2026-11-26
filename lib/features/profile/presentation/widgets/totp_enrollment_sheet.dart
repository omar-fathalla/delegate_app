import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/totp_mfa.dart';
import 'package:delegate_app/features/auth/presentation/widgets/totp_code_form.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// TOTP two-step verification enrollment from the profile (TAS-207).

const String twoStepTitle = 'التحقق بخطوتين';

/// Only super admins enroll from the app (user decision on TAS-207: not
/// technical support, not organization admins).
bool canEnrollTwoStep(UserRole? role, String? rawRole) {
  if (role == UserRole.superAdmin) return true;
  final norm = (rawRole ?? '').trim().toLowerCase().replaceAll('-', '_');
  return norm == 'super_admin' || norm == 'superadmin';
}

/// Profile security entry next to «تغيير كلمة المرور». Renders nothing for
/// roles that cannot enroll.
class TwoStepVerificationButton extends StatelessWidget {
  const TwoStepVerificationButton({
    super.key,
    required this.role,
    this.rawRole,
    this.clientFactory,
  });

  final UserRole? role;
  final String? rawRole;

  /// Test seam. Production uses Firebase Auth.
  final TotpEnrollmentClient Function()? clientFactory;

  @override
  Widget build(BuildContext context) {
    if (!canEnrollTwoStep(role, rawRole)) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          key: const ValueKey('two_step_verification_button'),
          onPressed: () => showTotpEnrollmentSheet(
            context,
            client:
                clientFactory?.call() ??
                FirebaseTotpEnrollmentClient(FirebaseAuth.instance),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text(
            twoStepTitle,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

Future<void> showTotpEnrollmentSheet(
  BuildContext context, {
  required TotpEnrollmentClient client,
}) {
  return showTotpAdaptiveSheet<void>(
    context,
    builder: (sheetContext) => TotpEnrollmentPanel(
      client: client,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

enum _Step { loading, enrolled, setup, failed, done }

/// Body of the enrollment sheet: already-enrolled state, or QR + secret +
/// code confirmation.
class TotpEnrollmentPanel extends StatefulWidget {
  const TotpEnrollmentPanel({
    super.key,
    required this.client,
    required this.onClose,
  });

  final TotpEnrollmentClient client;
  final VoidCallback onClose;

  @override
  State<TotpEnrollmentPanel> createState() => _TotpEnrollmentPanelState();
}

class _TotpEnrollmentPanelState extends State<TotpEnrollmentPanel> {
  _Step _step = _Step.loading;
  TotpEnrollmentStart? _start;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _step = _Step.loading;
      _error = null;
    });
    try {
      if (await widget.client.isEnrolled()) {
        if (mounted) setState(() => _step = _Step.enrolled);
        return;
      }
      final start = await widget.client.start();
      if (!mounted) return;
      setState(() {
        _start = start;
        _step = _Step.setup;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = totpGenericMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onSurfaceVariant,
    );
    final children = <Widget>[
      Icon(Icons.verified_user_rounded, color: colorScheme.primary, size: 36),
      const SizedBox(height: 12),
      Text(
        twoStepTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      const SizedBox(height: 16),
    ];

    switch (_step) {
      case _Step.loading:
        children.add(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      case _Step.enrolled:
      case _Step.done:
        children.addAll([
          Icon(
            Icons.check_circle_rounded,
            color: colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            _step == _Step.done
                ? 'تم تفعيل التحقق بخطوتين. من الدخول القادم هيُطلب منك الرمز من تطبيق المصادقة.'
                : 'التحقق بخطوتين مفعّل على حسابك.',
            key: const ValueKey('totp_enrolled_message'),
            textAlign: TextAlign.center,
            style: textStyle,
          ),
          const SizedBox(height: 20),
          _closeButton(colorScheme),
        ]);
      case _Step.failed:
        children.addAll([
          Text(
            _error ?? totpGenericMessage,
            key: const ValueKey('totp_enroll_error'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colorScheme.error),
          ),
          const SizedBox(height: 20),
          _connectedButtons(
            colorScheme,
            leftLabel: 'إغلاق',
            onLeft: widget.onClose,
            rightLabel: 'إعادة المحاولة',
            onRight: _load,
          ),
        ]);
      case _Step.setup:
        final start = _start!;
        children.addAll([
          Text(
            '1. امسح الرمز ده من تطبيق المصادقة (مثل Google Authenticator)، '
            'أو انسخ المفتاح وأضفه يدوياً.',
            style: textStyle,
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: QrImageView(
                key: const ValueKey('totp_qr'),
                data: start.qrCodeUrl,
                size: 184,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      start.secretKey,
                      key: const ValueKey('totp_secret'),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('totp_copy_secret'),
                    tooltip: 'نسخ المفتاح',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: start.secretKey),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('تم نسخ المفتاح'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('2. $totpCodeHint', style: textStyle),
          const SizedBox(height: 12),
          TotpCodeForm(
            autofocus: false,
            confirmLabel: 'تفعيل',
            onSubmit: widget.client.finish,
            onVerified: () => setState(() => _step = _Step.done),
            onCancel: widget.onClose,
          ),
        ]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _closeButton(ColorScheme colorScheme) {
    return Center(
      child: OutlinedButton(
        key: const ValueKey('totp_enroll_close'),
        onPressed: widget.onClose,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(120, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: const Text('إغلاق'),
      ),
    );
  }

  Widget _connectedButtons(
    ColorScheme colorScheme, {
    required String leftLabel,
    required VoidCallback onLeft,
    required String rightLabel,
    required VoidCallback onRight,
  }) {
    return DecoratedBox(
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
                onPressed: onLeft,
                child: Text(
                  leftLabel,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: TextButton(
                key: const ValueKey('totp_enroll_retry'),
                onPressed: onRight,
                child: Text(
                  rightLabel,
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
    );
  }
}
