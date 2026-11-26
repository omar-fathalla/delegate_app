import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';

/// A titled block in the playground: M3 component name, where its spec lives
/// on m3.material.io, the rule for using it in Tashil, then live examples.
class SpecSection extends StatelessWidget {
  const SpecSection({
    super.key,
    required this.title,
    this.m3,
    required this.spec,
    required this.children,
    this.rule,
  });

  final String title;

  /// English M3 component name, shown left-to-right next to the spec link.
  final String? m3;

  /// Path under https://m3.material.io/ (e.g. `components/buttons`).
  final String spec;

  /// One-line usage rule for this project.
  final String? rule;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TashilSpacing.page,
        TashilSpacing.xl,
        TashilSpacing.page,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          Text(
            [?m3, 'm3.material.io/$spec'].join('  ·  '),
            style: text.labelSmall?.copyWith(color: scheme.primary),
            textDirection: TextDirection.ltr,
          ),
          if (rule != null) ...[
            const SizedBox(height: TashilSpacing.xs),
            Text(
              rule!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: TashilSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// Wraps children with consistent spacing.
class Demo extends StatelessWidget {
  const Demo(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: TashilSpacing.sm,
    runSpacing: TashilSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

/// Scrollable list of sections with bottom padding for FABs.
class SectionList extends StatelessWidget {
  const SectionList(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
}
