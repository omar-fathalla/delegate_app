import 'package:flutter/material.dart';

import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// شاشة مستقلة لعرض الصور والزيارات الميدانية وأذونات التصوير
/// (تُستخدم عند فتح الأرشيف من قائمة المشرف أو الأدمن دون استبدال شريط التنقل السفلي)
class HRFieldPhotosScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRFieldPhotosScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
  });

  @override
  State<HRFieldPhotosScreen> createState() => _HRFieldPhotosScreenState();
}

class _HRFieldPhotosScreenState extends State<HRFieldPhotosScreen> {
  final GlobalKey<HRPhotosTabState> _photosTabKey = GlobalKey<HRPhotosTabState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: colorScheme.surfaceContainer,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 2.0,
              shape: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic ? 'الصور والزيارات الميدانية' : 'Field Photos & Visits',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: HrFont.body,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.hrDelegate.companyName.isNotEmpty)
                    Text(
                      widget.hrDelegate.companyName,
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: isArabic ? 'تحديث البيانات' : 'Refresh',
                  onPressed: () {
                    _photosTabKey.currentState?.refreshData();
                  },
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: HRPhotosTab(
        key: _photosTabKey,
        hrDelegate: widget.hrDelegate,
      ),
    );
  }
}
