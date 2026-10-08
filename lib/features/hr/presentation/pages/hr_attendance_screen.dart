import 'package:flutter/material.dart';

import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// شاشة مستقلة لعرض ومتابعة سجل الحضور والانصراف
/// (تُستخدم عند فتح السجل من قائمة المشرف أو الأدمن دون استبدال شريط التنقل السفلي)
class HRAttendanceScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRAttendanceScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
  });

  @override
  State<HRAttendanceScreen> createState() => _HRAttendanceScreenState();
}

class _HRAttendanceScreenState extends State<HRAttendanceScreen> {
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
                    isArabic ? 'سجل الحضور والانصراف' : 'Attendance & Departure',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.hrDelegate.companyName.isNotEmpty)
                    Text(
                      widget.hrDelegate.companyName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: IconButton(
                    icon: const Icon(Icons.history_edu_rounded),
                    tooltip: isArabic
                        ? 'سجل تعديلات الحضور والانصراف'
                        : 'Attendance Adjustments Log',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HRAttendanceAdjustmentsScreen(
                            hrDelegate: widget.hrDelegate,
                            showAppBar: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : null,
      body: HRAttendanceTab(
        hrDelegate: widget.hrDelegate,
      ),
    );
  }
}
