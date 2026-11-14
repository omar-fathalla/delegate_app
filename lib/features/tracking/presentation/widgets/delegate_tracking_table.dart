import 'package:flutter/material.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme/app_motion.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../../domain/utils/tracking_geofence_status.dart';

/// جدول بيانات تفصيلي لعرض تتبع نطاق المناديب (Live Tracking Table)
/// يدعم العرض المتجاوب على سطح المكتب والموبايل مع التمرير الأفقي السلس
class DelegateTrackingTable extends StatelessWidget {
  final List<DelegateTrackingSession> sessions;
  final void Function(DelegateTrackingSession session, bool enabled)
      onToggleTracking;
  final Future<void> Function(DelegateTrackingSession session) onRefreshPing;
  final void Function(DelegateTrackingSession session)? onSelectDelegate;

  const DelegateTrackingTable({
    super.key,
    required this.sessions,
    required this.onToggleTracking,
    required this.onRefreshPing,
    this.onSelectDelegate,
  });

  // عرض الجدول الأدنى للشاشات الصغيرة لتفعيل التمرير الأفقي
  // مجموع عرض الأعمدة (960.0) + الهامشين الجانبيين (24.0) + حدي الإطار الخارجي (2.0) = 986.0
  static const double _minTableWidth = 986.0;

  // نسب الأعمدة (Flex) للعرض على الشاشات الكبيرة
  static const int _flexIndex = 4;
  static const int _flexDelegate = 21;
  static const int _flexBranch = 13;
  static const int _flexCheckIn = 10;
  static const int _flexGeofence = 14;
  static const int _flexTracking = 10;
  static const int _flexTelemetry = 13;
  static const int _flexActions = 11;

  // العروض الثابتة للشاشات الضيقة / الموبايل
  static const double _colWidthIndex = 40.0;
  static const double _colWidthDelegate = 210.0;
  static const double _colWidthBranch = 130.0;
  static const double _colWidthCheckIn = 100.0;
  static const double _colWidthGeofence = 140.0;
  static const double _colWidthTracking = 100.0;
  static const double _colWidthTelemetry = 130.0;
  static const double _colWidthActions = 110.0;

  String _cleanPhoneNumber(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('01') && p.length == 11) {
      p = '+20${p.substring(1)}';
    }
    return p;
  }

  Color _getBatteryColor(int? level) {
    if (level == null) return Colors.grey;
    if (level > 50) return const Color(0xFF2E7D32); // 🟢 Green
    if (level > 20) return const Color(0xFFEF6C00); // 🟠 Orange
    return const Color(0xFFD32F2F); // 🔴 Red
  }

  String _formatLastUpdated(DateTime? time) {
    if (time == null) return 'غير متصل';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 45) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} د';
    } else {
      return DateFormat('hh:mm a', 'ar').format(time);
    }
  }

  Future<void> _makeCall(BuildContext context, String phone) async {
    final clean = _cleanPhoneNumber(phone);
    if (clean.isEmpty) {
      AppSnackBar.showError(context, 'رقم الهاتف غير متوفر');
      return;
    }
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      AppSnackBar.showError(context, 'تعذر بدء المكالمة الهاتفية');
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String phone) async {
    var clean = _cleanPhoneNumber(phone).replaceAll('+', '');
    if (clean.isEmpty) {
      AppSnackBar.showError(context, 'رقم الهاتف غير متوفر');
      return;
    }
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      AppSnackBar.showError(context, 'تعذر فتح تطبيق واتساب');
    }
  }

  Future<void> _openMap(BuildContext context, double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) {
      AppSnackBar.showError(context, 'إحداثيات الموقع غير متوفرة لهذا المندوب');
      return;
    }
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      AppSnackBar.showError(context, 'تعذر فتح تطبيق الخرائط');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < _minTableWidth;
        final targetWidth = isNarrow ? _minTableWidth : constraints.maxWidth;

        final tableContent = Container(
          width: targetWidth,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              _buildHeaderRow(
                colorScheme: colorScheme,
                isNarrow: isNarrow,
              ),

              // Data Rows
              ...sessions.asMap().entries.map((entry) {
                final index = entry.key;
                final session = entry.value;
                return _DelegateTableRow(
                  index: index,
                  session: session,
                  isNarrow: isNarrow,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  isLast: index == sessions.length - 1,
                  onToggleTracking: (enabled) =>
                      onToggleTracking(session, enabled),
                  onMakeCall: () => _makeCall(context, session.delegatePhone),
                  onOpenWhatsApp: () =>
                      _openWhatsApp(context, session.delegatePhone),
                  onOpenMap: () => _openMap(
                    context,
                    session.lastLatitude ?? session.branchLat,
                    session.lastLongitude ?? session.branchLng,
                  ),
                  onSelectDelegate: onSelectDelegate != null
                      ? () => onSelectDelegate!(session)
                      : null,
                  onRefreshPing: () => onRefreshPing(session),
                  formatLastUpdated: _formatLastUpdated,
                  getBatteryColor: _getBatteryColor,
                );
              }),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Swipe hint for mobile
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(bottom: 8.0, start: 4.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.swipe_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'اسحب أفقياً لعرض كافة بيانات الجدول',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: tableContent,
              ),
            ],
          );
        }

        return tableContent;
      },
    );
  }

  Widget _buildHeaderRow({
    required ColorScheme colorScheme,
    required bool isNarrow,
  }) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsetsDirectional.only(start: 12.0, end: 12.0),
      child: Row(
        children: [
          _wrapCell(
            width: _colWidthIndex,
            flex: _flexIndex,
            isNarrow: isNarrow,
            child: _headerText('#', colorScheme, textAlign: TextAlign.center),
          ),
          _wrapCell(
            width: _colWidthDelegate,
            flex: _flexDelegate,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.person_outline_rounded,
              title: 'المندوب',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthBranch,
            flex: _flexBranch,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.storefront_rounded,
              title: 'الفرع',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthCheckIn,
            flex: _flexCheckIn,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.access_time_rounded,
              title: 'الحضور',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthGeofence,
            flex: _flexGeofence,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.radar_rounded,
              title: 'نطاق التواجد',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthTracking,
            flex: _flexTracking,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.toggle_on_rounded,
              title: 'حالة التتبع',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthTelemetry,
            flex: _flexTelemetry,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.speed_rounded,
              title: 'القياسات الحية',
              colorScheme: colorScheme,
            ),
          ),
          _wrapCell(
            width: _colWidthActions,
            flex: _flexActions,
            isNarrow: isNarrow,
            child: _headerTitle(
              icon: Icons.handyman_rounded,
              title: 'إجراءات',
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _wrapCell({
    required double width,
    required int flex,
    required bool isNarrow,
    required Widget child,
  }) {
    return Expanded(
      flex: flex,
      child: child,
    );
  }

  Widget _headerTitle({
    required IconData icon,
    required String title,
    required ColorScheme colorScheme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerText(String text, ColorScheme colorScheme,
      {TextAlign textAlign = TextAlign.start}) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DelegateTableRow extends StatefulWidget {
  final int index;
  final DelegateTrackingSession session;
  final bool isNarrow;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isLast;
  final ValueChanged<bool> onToggleTracking;
  final VoidCallback onMakeCall;
  final VoidCallback onOpenWhatsApp;
  final VoidCallback onOpenMap;
  final VoidCallback? onSelectDelegate;
  final VoidCallback onRefreshPing;
  final String Function(DateTime?) formatLastUpdated;
  final Color Function(int?) getBatteryColor;

  const _DelegateTableRow({
    required this.index,
    required this.session,
    required this.isNarrow,
    required this.colorScheme,
    required this.textTheme,
    required this.isLast,
    required this.onToggleTracking,
    required this.onMakeCall,
    required this.onOpenWhatsApp,
    required this.onOpenMap,
    this.onSelectDelegate,
    required this.onRefreshPing,
    required this.formatLastUpdated,
    required this.getBatteryColor,
  });

  @override
  State<_DelegateTableRow> createState() => _DelegateTableRowState();
}

class _DelegateTableRowState extends State<_DelegateTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colorScheme = widget.colorScheme;
    final geofenceStatus =
        TrackingGeofenceStatus.resolve(session, colorScheme);
    final statusColor = geofenceStatus.color;
    final statusBgColor = geofenceStatus.backgroundColor;
    final statusTitle = geofenceStatus.title;
    final statusIcon = geofenceStatus.icon;

    final checkInStr = session.checkInTime != null
        ? DateFormat('hh:mm a', 'ar').format(session.checkInTime!)
        : 'حاضر';

    final rowBgColor = _isHovered
        ? colorScheme.primary.withValues(alpha: 0.05)
        : (widget.index.isEven
            ? colorScheme.surface
            : colorScheme.surfaceContainerLowest);

    final isMoving = session.isMoving == true;
    final speed = session.speed ?? 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppMotionDurations.short2,
        curve: AppMotionCurves.standard,
        decoration: BoxDecoration(
          color: rowBgColor,
          border: BorderDirectional(
            start: BorderSide(
              color: statusColor,
              width: 3.5,
            ),
            bottom: widget.isLast
                ? BorderSide.none
                : BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
          ),
        ),
        padding: const EdgeInsetsDirectional.only(
          start: 8.5,
          end: 12.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Row Index (#)
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthIndex,
              flex: DelegateTrackingTable._flexIndex,
              isNarrow: widget.isNarrow,
              child: Text(
                '${widget.index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),

            // 2. Delegate Identity (Avatar, Name, Phone) - Tapping focuses live map on delegate
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthDelegate,
              flex: DelegateTrackingTable._flexDelegate,
              isNarrow: widget.isNarrow,
              child: Tooltip(
                message: 'عرض التتبع المباشر للمندوب على الخريطة',
                child: InkWell(
                  onTap: widget.onSelectDelegate ?? widget.onOpenMap,
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2.0,
                      horizontal: 3.0,
                    ),
                    child: Row(
                      children: [
                        AppAvatar(
                          imageUrl: session.avatarUrl,
                          fallbackText: session.delegateName.isNotEmpty
                              ? session.delegateName
                              : 'م',
                          radius: 17,
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                session.delegateName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              if (session.delegatePhone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  session.delegatePhone,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Branch
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthBranch,
              flex: DelegateTrackingTable._flexBranch,
              isNarrow: widget.isNarrow,
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      session.branchName.isNotEmpty
                          ? BranchDisplayCache.instance.displayName(session.branchName)
                          : 'غير محدد',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 4. Check-in Time
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthCheckIn,
              flex: DelegateTrackingTable._flexCheckIn,
              isNarrow: widget.isNarrow,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        checkInStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 5. Geofence Status Pill
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthGeofence,
              flex: DelegateTrackingTable._flexGeofence,
              isNarrow: widget.isNarrow,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          statusTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 6. Live Tracking Switch
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthTracking,
              flex: DelegateTrackingTable._flexTracking,
              isNarrow: widget.isNarrow,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: InkWell(
                  onTap: () =>
                      widget.onToggleTracking(!session.isTrackingEnabled),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: AppMotionDurations.short2,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: session.isTrackingEnabled
                          ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                          : colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: session.isTrackingEnabled
                            ? colorScheme.primary.withValues(alpha: 0.4)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          session.isTrackingEnabled
                              ? Icons.radar_rounded
                              : Icons.power_settings_new_rounded,
                          size: 13,
                          color: session.isTrackingEnabled
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          session.isTrackingEnabled ? 'تتبع نشط' : 'متوقف',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: session.isTrackingEnabled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 7. Telemetry Indicators (Battery, Speed, Last Update)
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthTelemetry,
              flex: DelegateTrackingTable._flexTelemetry,
              isNarrow: widget.isNarrow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (session.batteryLevel != null &&
                                session.batteryLevel! <= 20)
                            ? Icons.battery_alert_rounded
                            : Icons.battery_charging_full_rounded,
                        size: 13,
                        color: widget.getBatteryColor(session.batteryLevel),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        session.batteryLevel != null
                            ? '${session.batteryLevel}%'
                            : '—',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: widget.getBatteryColor(session.batteryLevel),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isMoving
                            ? Icons.directions_walk_rounded
                            : Icons.pan_tool_rounded,
                        size: 12,
                        color: isMoving
                            ? const Color(0xFF2E7D32)
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        isMoving ? '${speed.toInt()} كم/س' : 'متوقف',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isMoving
                              ? const Color(0xFF2E7D32)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 11,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.formatLastUpdated(session.lastUpdated),
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 8. Actions (Call, WhatsApp, Map, Ping)
            DelegateTrackingTable._wrapCell(
              width: DelegateTrackingTable._colWidthActions,
              flex: DelegateTrackingTable._flexActions,
              isNarrow: widget.isNarrow,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Call Button
                    _buildMiniAction(
                      icon: Icons.phone_rounded,
                      color: const Color(0xFF2E7D32),
                      tooltip: 'اتصال هاتفياً',
                      onTap: widget.onMakeCall,
                    ),
                    const SizedBox(width: 4),
                    // WhatsApp Button
                    _buildMiniAction(
                      icon: Icons.chat_bubble_rounded,
                      color: const Color(0xFF00897B),
                      tooltip: 'مراسلة عبر واتساب',
                      onTap: widget.onOpenWhatsApp,
                    ),
                    const SizedBox(width: 4),
                    // Map Button
                    _buildMiniAction(
                      icon: Icons.map_rounded,
                      color: colorScheme.primary,
                      tooltip: 'عرض التتبع المباشر على الخريطة',
                      onTap: widget.onSelectDelegate ?? widget.onOpenMap,
                    ),
                    const SizedBox(width: 4),
                    // Refresh Ping
                    _buildMiniAction(
                      icon: Icons.refresh_rounded,
                      color: colorScheme.primary,
                      tooltip: 'طلب تحديث الموقع',
                      onTap: widget.onRefreshPing,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}
