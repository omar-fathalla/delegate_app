// TAS-112: the delegate changes its own phone number. Step 1: new number +
// national ID (server checks both). Step 2: the code sent to the new number.
// The server then updates every copy of the delegate.
import 'package:delegate_app/core/widgets/phone_country_picker.dart';
import 'package:delegate_app/features/auth/domain/phone_country.dart';
import 'package:delegate_app/features/profile/data/phone_change/delegate_phone_change_api.dart';
import 'package:delegate_app/features/profile/data/phone_change/phone_change_otp_client.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Abstracts the OTP step so widget tests do not need Firebase Auth.
abstract class PhoneChangeOtp {
  Future<void> sendCode({
    required String e164Phone,
    bool resend,
    required void Function() onAutoVerified,
    required void Function(String code) onFailed,
  });
  Future<void> confirmCode(String smsCode);
}

class FirebasePhoneChangeOtp implements PhoneChangeOtp {
  FirebasePhoneChangeOtp([PhoneChangeOtpClient? client])
      : _client = client ?? PhoneChangeOtpClient(FirebaseAuth.instance);
  final PhoneChangeOtpClient _client;

  @override
  Future<void> sendCode({
    required String e164Phone,
    bool resend = false,
    required void Function() onAutoVerified,
    required void Function(String code) onFailed,
  }) =>
      _client.sendCode(
        e164Phone: e164Phone,
        resend: resend,
        onAutoVerified: onAutoVerified,
        onFailed: onFailed,
      );

  @override
  Future<void> confirmCode(String smsCode) => _client.confirmCode(smsCode);
}

Future<String?> showDelegatePhoneChangeSheet(
  BuildContext context, {
  DelegatePhoneChangeApi? api,
  PhoneChangeOtp? otp,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DelegatePhoneChangeSheet(api: api, otp: otp),
  );
}

class DelegatePhoneChangeSheet extends StatefulWidget {
  const DelegatePhoneChangeSheet({super.key, this.api, this.otp, this.refreshToken});

  final DelegatePhoneChangeApi? api;
  final PhoneChangeOtp? otp;

  /// Refreshes the ID token so the new phones claim is used. Tests stub it.
  final Future<void> Function()? refreshToken;

  @override
  State<DelegatePhoneChangeSheet> createState() => _DelegatePhoneChangeSheetState();
}

enum _Step { form, code }

class _DelegatePhoneChangeSheetState extends State<DelegatePhoneChangeSheet> {
  late final DelegatePhoneChangeApi _api = widget.api ?? DelegatePhoneChangeApi();
  late final PhoneChangeOtp _otp = widget.otp ?? FirebasePhoneChangeOtp();
  final _phone = TextEditingController();
  final _nationalId = TextEditingController();
  final _code = TextEditingController();

  _Step _step = _Step.form;
  PhoneCountry _country = PhoneCountry.egypt;
  String _e164 = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _nationalId.dispose();
    _code.dispose();
    super.dispose();
  }

  String _failureText(AppLocalizations l10n, PhoneChangeFailure f) {
    switch (f) {
      case PhoneChangeFailure.badPhone:
        return l10n.phoneChangeErrBadPhone;
      case PhoneChangeFailure.nationalIdMismatch:
        return l10n.phoneChangeErrNationalId;
      case PhoneChangeFailure.samePhone:
        return l10n.phoneChangeErrSamePhone;
      case PhoneChangeFailure.phoneTaken:
        return l10n.phoneChangeErrTaken;
      case PhoneChangeFailure.tooMany:
        return l10n.phoneChangeErrTooMany;
      case PhoneChangeFailure.expired:
        return l10n.phoneChangeErrExpired;
      case PhoneChangeFailure.notVerified:
        return l10n.phoneChangeErrWrongCode;
      case PhoneChangeFailure.other:
        return l10n.phoneChangeErrGeneric;
    }
  }

  String _authErrorText(AppLocalizations l10n, String code) {
    switch (code) {
      case 'invalid-verification-code':
      case 'invalid-verification-id':
      case 'session-expired':
        return l10n.phoneChangeErrWrongCode;
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return l10n.phoneChangeErrTaken;
      case 'too-many-requests':
        return l10n.phoneChangeErrTooMany;
      case 'invalid-phone-number':
        return l10n.phoneChangeErrBadPhone;
      default:
        return l10n.phoneChangeErrGeneric;
    }
  }

  Future<void> _send({bool resend = false}) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!resend) {
        _e164 = await _api.request(
          newPhone: composePhone(_country, _phone.text),
          nationalId: _nationalId.text,
        );
      }
      await _otp.sendCode(
        e164Phone: _e164,
        resend: resend,
        onAutoVerified: _finish,
        onFailed: (code) {
          if (mounted) setState(() => _error = _authErrorText(l10n, code));
        },
      );
      if (mounted) setState(() => _step = _Step.code);
    } on PhoneChangeException catch (e) {
      if (mounted) setState(() => _error = _failureText(l10n, e.failure));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.phoneChangeErrGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCode() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _otp.confirmCode(_code.text);
      await _finish();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authErrorText(l10n, e.code));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.phoneChangeErrGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final phone = await _api.confirm();
      try {
        final refresh = widget.refreshToken;
        if (refresh != null) {
          await refresh();
        } else {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        }
      } catch (_) {}
      if (mounted) Navigator.of(context).pop(phone);
    } on PhoneChangeException catch (e) {
      if (mounted) setState(() => _error = _failureText(l10n, e.failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TAS-355 (C-28): the drag handle comes from the theme.
            Text(l10n.phoneChangeTitle,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _step == _Step.form ? l10n.phoneChangeIntro : l10n.phoneChangeCodeSent(_e164),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (_step == _Step.form) ...[
              TextField(
                key: const Key('phone_change_new_phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                decoration: InputDecoration(
                  labelText: l10n.phoneChangeNewPhone,
                  prefixIcon: const Icon(Icons.phone_iphone_rounded),
                  // TAS-112: country picked, not typed (left side in RTL).
                  suffixIcon: PhoneCountryPicker(
                    value: _country,
                    enabled: !_busy,
                    onChanged: (c) => setState(() => _country = c),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('phone_change_national_id'),
                controller: _nationalId,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.phoneChangeNationalId,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ] else
              TextField(
                key: const Key('phone_change_code'),
                controller: _code,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: l10n.phoneChangeCodeLabel,
                  prefixIcon: const Icon(Icons.sms_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: const Key('phone_change_error'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.error)),
            ],
            const SizedBox(height: 20),
            _ActionPair(
              secondaryLabel: _step == _Step.form
                  // TAS-355: «إلغاء» like the rest of the app, not «الإلغاء».
                  ? l10n.cancel
                  : l10n.phoneChangeResend,
              onSecondary: _busy
                  ? null
                  : (_step == _Step.form
                      ? () => Navigator.of(context).pop()
                      : () => _send(resend: true)),
              primaryLabel: _step == _Step.form ? l10n.phoneChangeSendCode : l10n.phoneChangeConfirm,
              primaryKey: const Key('phone_change_primary'),
              busy: _busy,
              onPrimary: _busy ? null : (_step == _Step.form ? _send : _confirmCode),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connected two-button group (AGENTS.md: height 48, radius 24, divider).
class _ActionPair extends StatelessWidget {
  const _ActionPair({
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
    required this.busy,
    this.primaryKey,
  });

  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool busy;
  final Key? primaryKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSecondary,
              child: Center(child: Text(secondaryLabel)),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: cs.outline),
          Expanded(
            child: Material(
              color: onPrimary == null ? cs.surfaceContainerHighest : cs.primary,
              child: InkWell(
                key: primaryKey,
                onTap: onPrimary,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : Text(primaryLabel,
                          style: TextStyle(
                            color: onPrimary == null ? cs.onSurfaceVariant : cs.onPrimary,
                            fontWeight: FontWeight.bold,
                          )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
