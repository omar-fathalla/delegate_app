import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/injection_container.dart';

/// Arabic confirmation step shown after a delegate custom-token sign-in.
class DelegatePhoneOtpView extends StatefulWidget {
  final String phoneE164;
  final DelegatePhoneOtpClient? client;

  const DelegatePhoneOtpView({super.key, required this.phoneE164, this.client});

  @override
  State<DelegatePhoneOtpView> createState() => _DelegatePhoneOtpViewState();
}

class _DelegatePhoneOtpViewState extends State<DelegatePhoneOtpView>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late final AnimationController _enter;
  late final Animation<double> _fade;

  DelegatePhoneOtpClient? _client;
  String? _verificationId;
  int? _resendToken;
  String? _error;
  bool _sending = true;
  bool _confirming = false;
  bool _finished = false;
  int _secondsLeft = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: AppMotionDurations.medium2,
    );
    _fade = CurvedAnimation(
      parent: _enter,
      curve: AppMotionCurves.standardDecelerate,
    );
    _enter.forward();
    _client = widget.client ?? sl<DelegatePhoneOtpClient>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _armCooldownTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, 9999);
        if (_secondsLeft == 0) {
          _ticker?.cancel();
        }
      });
    });
  }

  Future<void> _send({bool resend = false}) async {
    final client = _client;
    if (client == null || _finished) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await client.sendCode(
        e164Phone: widget.phoneE164,
        forceResendingToken: resend ? _resendToken : null,
        onCodeSent: (sent) {
          if (!mounted || _finished) return;
          setState(() {
            _verificationId = sent.verificationId;
            _resendToken = sent.resendToken ?? _resendToken;
            _sending = false;
            _secondsLeft = DelegateOtpConfig.resendCooldown.inSeconds;
          });
          _armCooldownTicker();
        },
        onAutoVerified: _complete,
        onFailed: (error) {
          if (!mounted || _finished) return;
          setState(() {
            _sending = false;
            _error = error.failure == PhoneOtpLinkFailure.other
                ? phoneOtpSendFailedMessage
                : error.message;
          });
          if (error.failure == PhoneOtpLinkFailure.expired) {
            _ticker?.cancel();
            setState(() => _secondsLeft = 0);
          }
        },
      );
    } catch (_) {
      if (!mounted || _finished) return;
      setState(() {
        _sending = false;
        _error = phoneOtpSendFailedMessage;
      });
    }
  }

  Future<void> _confirm() async {
    final client = _client;
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (client == null || verificationId == null || _finished || _confirming) {
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = 'أدخل رمز التحقق');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await client.confirmCode(verificationId: verificationId, smsCode: code);
      _complete();
    } on PhoneOtpLinkException catch (error) {
      if (!mounted || _finished) return;
      setState(() {
        _confirming = false;
        _error = error.message;
        if (error.failure == PhoneOtpLinkFailure.expired) {
          _secondsLeft = 0;
        }
      });
      if (error.failure == PhoneOtpLinkFailure.expired) {
        _ticker?.cancel();
      }
    } catch (_) {
      if (!mounted || _finished) return;
      setState(() {
        _confirming = false;
        _error = phoneOtpGenericMessage;
      });
    }
  }

  void _complete() {
    if (!mounted || _finished) return;
    _finished = true;
    context.read<AuthBloc>().add(const PhoneOtpVerified());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canResend =
        !_sending &&
        !_confirming &&
        _secondsLeft == 0 &&
        _verificationId != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
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
                          Icon(
                            Icons.sms_rounded,
                            color: colorScheme.primary,
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'تأكيد رقم الجوال',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'أدخل رمز التحقق المرسل إلى ${widget.phoneE164}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_sending)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              autofocus: true,
                              maxLength: 8,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 4,
                                color: colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'رمز التحقق',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 0,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _confirm(),
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton.icon(
                              onPressed: canResend
                                  ? () => _send(resend: true)
                                  : null,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                _secondsLeft > 0
                                    ? 'إعادة الإرسال بعد $_secondsLeft ث'
                                    : 'إعادة إرسال الرمز',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: _confirming
                                          ? null
                                          : () => context.read<AuthBloc>().add(
                                              const PhoneOtpCancelled(),
                                            ),
                                      child: Text(
                                        'إلغاء',
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 1,
                                    color: colorScheme.outlineVariant,
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      onPressed:
                                          (_sending ||
                                              _confirming ||
                                              _verificationId == null)
                                          ? null
                                          : _confirm,
                                      child: _confirming
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: colorScheme.primary,
                                              ),
                                            )
                                          : Text(
                                              'تأكيد',
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
                      ),
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
