import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class AddDelegateWebScreen extends StatefulWidget {
  const AddDelegateWebScreen({super.key});

  @override
  State<AddDelegateWebScreen> createState() => _AddDelegateWebScreenState();
}

class _AddDelegateWebScreenState extends State<AddDelegateWebScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://tashil.sw-point.com/login'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addDelegateViaWeb),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
