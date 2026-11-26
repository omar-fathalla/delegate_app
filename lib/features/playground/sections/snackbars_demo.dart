import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/snackbars.dart';

/// Snackbar examples from Tashil, inside a small framed screen with a FAB
/// and a navigation bar so the snackbar can be seen above both: remove an
/// item with undo, print (disappears by itself), sync (the result replaces
/// the progress message), save (the button also says "اتحفظ") and a long
/// message whose action moves to its own line.
class SnackbarsDemo extends StatefulWidget {
  const SnackbarsDemo({super.key});

  @override
  State<SnackbarsDemo> createState() => _SnackbarsDemoState();
}

class _SnackbarsDemoState extends State<SnackbarsDemo> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  var _cart = 3;
  var _saved = false;
  Timer? _sync;

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  void _remove(BuildContext c) {
    if (_cart == 0) return;
    setState(() => _cart--);
    showTashilSnackBar(
      c,
      'اتشال صنف من السلة',
      actionLabel: 'تراجع',
      onAction: () => setState(() => _cart++),
    );
  }

  void _syncNow(BuildContext c) {
    showTashilSnackBar(c, 'جاري مزامنة الفواتير…');
    _sync?.cancel();
    _sync = Timer(const Duration(milliseconds: 1500), () {
      if (c.mounted) showTashilSnackBar(c, 'اتزامن 12 فاتورة');
    });
  }

  Future<void> _save(BuildContext c) async {
    setState(() => _saved = true);
    showTashilSnackBar(c, 'اتحفظت التعديلات');
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: 420,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        // The frame is its own small screen, so the snackbar measures
        // against the frame and not the whole window.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: Size(box.maxWidth, 420)),
          child: ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              floatingActionButton: FloatingActionButton(
                tooltip: 'فاتورة جديدة',
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              bottomNavigationBar: NavigationBar(
                height: 64,
                selectedIndex: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.point_of_sale_outlined),
                    label: 'البيع',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    label: 'المخزون',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    label: 'التقارير',
                  ),
                ],
              ),
              body: Builder(
                builder: (c) => ListView(
                  padding: const EdgeInsets.all(TashilSpacing.lg),
                  children: [
                    Text(
                      'في السلة: $_cart أصناف',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    const SizedBox(height: TashilSpacing.md),
                    Wrap(
                      spacing: TashilSpacing.sm,
                      runSpacing: TashilSpacing.sm,
                      children: [
                        OutlinedButton(
                          onPressed: _cart == 0 ? null : () => _remove(c),
                          child: const Text('شيل صنف (مع تراجع)'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              showTashilSnackBar(c, 'اتبعت للطابعة'),
                          child: const Text('اطبع (يختفي لوحده)'),
                        ),
                        OutlinedButton(
                          onPressed: () => _syncNow(c),
                          child: const Text('زامن (الجديد يشيل القديم)'),
                        ),
                        FilledButton.icon(
                          onPressed: _saved ? null : () => _save(c),
                          icon: Icon(_saved ? Icons.check : Icons.save),
                          label: Text(_saved ? 'اتحفظ' : 'احفظ'),
                        ),
                        TextButton(
                          onPressed: () => showTashilSnackBar(
                            c,
                            'الفاتورة اتحفظت على الجهاز ومش هتتزامن غير '
                            'لما النت يرجع',
                            actionLabel: 'عرض المعلقة',
                            onAction: () {},
                          ),
                          child: const Text('رسالة طويلة'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
