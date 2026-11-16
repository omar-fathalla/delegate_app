// WEB-ONLY: sends a company supervisor or HR account that reaches a
// mobile-style home route (/admin/home, /home) to the HR desktop system.
// go_router drops `extra` on redirects, so the move happens after the first
// frame with the signed-in delegate attached.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class WebHrSystemRedirect extends StatefulWidget {
  final Delegate delegate;

  const WebHrSystemRedirect({super.key, required this.delegate});

  /// True when [delegate] must not see a mobile-style home on this platform.
  static bool appliesTo(Delegate delegate) =>
      usesWebHrSystem(delegate.role, isWeb: WebRuntimePolicy.isWeb);

  /// Test hook: replaces the `/hr/home` screen (it needs a live Firestore).
  /// Always null in the app.
  static Widget Function(Delegate delegate)? debugHrSystemBuilder;

  @override
  State<WebHrSystemRedirect> createState() => _WebHrSystemRedirectState();
}

class _WebHrSystemRedirectState extends State<WebHrSystemRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(kWebHrSystemPath, extra: widget.delegate);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}
