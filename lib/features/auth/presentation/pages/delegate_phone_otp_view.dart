import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pinput/pinput.dart';
import 'package:smart_auth/smart_auth.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/data/datasources/smart_auth_sms_retriever.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/injection_container.dart';

/// Arabic confirmation step shown after a delegate custom-token sign-in.
class DelegatePhoneOtpView extends StatefulWidget {
  final String phoneE164;
  final DelegatePhoneOtpClient? client;

  /// Android SMS Retriever used by [Pinput]. Tests pass a fake. Production
  /// uses [SmartAuthSmsRetriever], which Pinput disposes with the field.
  final SmsRetriever? smsRetriever;

  const DelegatePhoneOtpView({
    super.key,
    required this.phoneE164,
    this.client,
    this.smsRetriever,
  });

  @override
  State<DelegatePhoneOtpView> createState() => _DelegatePhoneOtpViewState();
}

class _DelegatePhoneOtpViewState extends State<DelegatePhoneOtpView>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late final AnimationController _enter;
  late final Animation<double> _fade;

  static const int _codeLength = 6;

  DelegatePhoneOtpClient? _client;
  late final SmsRetriever _smsRetriever;
  String? _verificationId;
  int? _resendToken;
  String? _error;
  String? _pendingAutoCode;
  bool _sending = true;
  bool _confirming = false;
  bool _finished = false;
  int _secondsLeft = 0;
  int _inputGeneration = 0;
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
    _smsRetriever =
        widget.smsRetriever ?? SmartAuthSmsRetriever(SmartAuth.instance);
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
      if (resend) {
        _pendingAutoCode = null;
        _codeController.clear();
        // A new Pinput starts a new SMS Retriever listen for the next SMS.
        _inputGeneration++;
      }
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
          final pending = _pendingAutoCode;
          if (pending != null && pending.length == _codeLength) {
            _pendingAutoCode = null;
            _codeController.text = pending;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_finished) _confirm();
            });
          }
        },
        onAutoVerified: _complete,
        onAutoRetrievalTimeout: () {
          // Automatic retrieval stopped. Keep the field for typing, paste,
          // or the iOS QuickType one-time-code suggestion.
          if (!mounted || _finished) return;
          setState(() => _sending = false);
        },
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

  void _onPinCompleted(String pin) {
    if (pin.length != _codeLength || _finished) return;
    if (_verificationId == null) {
      _pendingAutoCode = pin;
      return;
    }
    _confirm();
  }

  Future<void> _confirm() async {
    final client = _client;
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (client == null || verificationId == null || _finished || _confirming) {
      return;
    }
    if (code.length != _codeLength) {
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
                            'أدخل رمز التحقق المرسل إلى',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              widget.phoneE164,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_sending)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          // iOS maps AutofillHints.oneTimeCode to
                          // textContentType = oneTimeCode, so the code appears
                          // on the QuickType bar. One tap fills every box and
                          // onCompleted submits it. Android uses smsRetriever,
                          // which is Pinput's replacement for
                          // androidSmsAutofillMethod: smsRetrieverApi.
                          // Pinput disposes that listener with the field.
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: AutofillGroup(
                              child: Pinput(
                                key: ValueKey(_inputGeneration),
                                length: _codeLength,
                                controller: _codeController,
                                smsRetriever: _smsRetriever,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode,
                                ],
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofocus: true,
                                enabled: !_confirming,
                                closeKeyboardWhenCompleted: true,
                                pinAnimationType: PinAnimationType.none,
                                isCursorAnimationEnabled: false,
                                animationDuration: AppMotionDurations.short4,
                                animationCurve:
                                    AppMotionCurves.standardDecelerate,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
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
                                separatorBuilder: (_) =>
                                    const SizedBox(width: 8),
                                onChanged: (value) {
                                  if (_error != null &&
                                      value.length < _codeLength) {
                                    setState(() => _error = null);
                                  }
                                },
                                onCompleted: _onPinCompleted,
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
