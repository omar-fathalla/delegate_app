import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/services/branch_display_cache.dart';

/// Shows a branch's Arabic display name (falls back to [branchName]) with
/// the short address underneath in small grey text (hidden when empty).
class BranchNameLabel extends StatelessWidget {
  final String? branchName;
  final String fallback;
  final TextStyle? style;
  final bool showAddress;
  final String prefix;
  final String Function(String name)? transform;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  const BranchNameLabel({
    super.key,
    required this.branchName,
    this.fallback = 'غير محدد',
    this.style,
    this.showAddress = true,
    this.prefix = '',
    this.transform,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final cache0 = BranchDisplayCache.instance;
    if (!cache0.isLoaded) cache0.ensureLoaded();
    return ValueListenableBuilder<int>(
      valueListenable: cache0.version,
      builder: (context, v, c) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final cache = BranchDisplayCache.instance;
    final raw = cache.displayName(branchName, fallback: fallback);
    final name = '$prefix${transform != null ? transform!(raw) : raw}';
    final address = showAddress ? cache.addressFor(branchName) : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign),
        if (address.isNotEmpty)
          Text(
            address,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              color: Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
