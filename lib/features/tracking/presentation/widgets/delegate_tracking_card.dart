import 'package:flutter/material.dart';
import 'package:delegate_app/core/widgets/branch_name_label.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme/app_motion.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../../domain/utils/tracking_geofence_status.dart';

class DelegateTrackingCard extends StatefulWidget {
  final DelegateTrackingSession session;
  final ValueChanged<bool> onToggleTracking;
  final VoidCallback? onRefreshPing;
  final VoidCallback? onClose;
  final VoidCallback? onFocusOnMap;

  const DelegateTrackingCard({
    super.key,
    required this.session,
    required this.onToggleTracking,
    this.onRefreshPing,
    this.onClose,
    this.onFocusOnMap,
  });

  @override
  State<DelegateTrackingCard> createState() => _DelegateTrackingCardState();
}

class _DelegateTrackingCardState extends State<DelegateTrackingCard> {
  bool _isHovered = false;

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

  String _formatLastUpdated(DateTime time) {
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

  Future<void> _makeCall(BuildContext context) async {
    final clean = _cleanPhoneNumber(widget.session.delegatePhone);
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر بدء المكالمة الهاتفية.')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    var clean = _cleanPhoneNumber(widget.session.delegatePhone).replaceAll('+', '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق واتساب.')),
      );
    }
  }

  Future<void> _openMap(BuildContext context) async {
    final lat = widget.session.lastLatitude ?? widget.session.branchLat;
    final lng = widget.session.lastLongitude ?? widget.session.branchLng;
    final googleMapsUrl =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق الخرائط.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final session = widget.session;
    final geofenceStatus =
        TrackingGeofenceStatus.resolve(session, colorScheme);
    final statusColor = geofenceStatus.color;
    final statusBgColor = geofenceStatus.backgroundColor;
    final statusTitle = geofenceStatus.title;
    final statusIcon = geofenceStatus.icon;

    final checkInStr = session.checkInTime != null
        ? DateFormat('hh:mm a', 'ar').format(session.checkInTime!)
        : 'حاضر';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppMotionDurations.short3,
        curve: AppMotionCurves.standard,
        margin: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: _isHovered
              ? colorScheme.primary.withValues(alpha: 0.035)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isHovered
                ? colorScheme.primary.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: _isHovered ? 1.2 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: BorderDirectional(
              start: BorderSide(
                color: statusColor,
                width: 3.5,
              ),
            ),
          ),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14.0, vertical: 9.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 960;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Delegate Identity (Avatar + Name + Branch + Check-in)
                    Expanded(
                      flex: 23,
                      child: _buildDelegateIdentity(
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        checkInStr: checkInStr,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 2. Geofence Status Pill
                    Expanded(
                      flex: 15,
                      child: _buildGeofencePill(
                        statusColor: statusColor,
                        statusBgColor: statusBgColor,
                        statusTitle: statusTitle,
                        statusIcon: statusIcon,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 3. Telemetry Indicators Strip
                    Expanded(
                      flex: 27,
                      child: _buildTelemetryBar(colorScheme: colorScheme),
                    ),
                    const SizedBox(width: 10),

                    // 4. Tracking Switch Control (Pill container, NO overflow)
                    _buildTrackingSwitch(
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                    const SizedBox(width: 10),

                    // 5. Actions (Call, WhatsApp, Map, Ping)
                    _buildActions(context: context, colorScheme: colorScheme),
                  ],
                );
              }

              if (constraints.maxWidth < 650) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Identity + Tracking switch
                    Row(
                      children: [
                        Expanded(
                          child: _buildDelegateIdentity(
                            colorScheme: colorScheme,
                            textTheme: textTheme,
                            checkInStr: checkInStr,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildTrackingSwitch(
                          colorScheme: colorScheme,
                          textTheme: textTheme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 2: Status Pill + Actions (Call, WhatsApp, Map, Ping, Close)
                    Row(
                      children: [
                        Flexible(
                          child: _buildGeofencePill(
                            statusColor: statusColor,
                            statusBgColor: statusBgColor,
                            statusTitle: statusTitle,
                            statusIcon: statusIcon,
                            colorScheme: colorScheme,
                          ),
                        ),
                        const Spacer(),
                        _buildActions(context: context, colorScheme: colorScheme),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Row 3: Telemetry bar spanning cleanly across the card
                    _buildTelemetryBar(colorScheme: colorScheme),
                  ],
                );
              }

              // Tablet layout (650 <= width < 960)
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDelegateIdentity(
                          colorScheme: colorScheme,
                          textTheme: textTheme,
                          checkInStr: checkInStr,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTrackingSwitch(
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildGeofencePill(
                        statusColor: statusColor,
                        statusBgColor: statusBgColor,
                        statusTitle: statusTitle,
                        statusIcon: statusIcon,
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTelemetryBar(colorScheme: colorScheme)),
                      const SizedBox(width: 8),
                      _buildActions(context: context, colorScheme: colorScheme),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDelegateIdentity({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String checkInStr,
  }) {
    final session = widget.session;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppAvatar(
          imageUrl: session.avatarUrl,
          fallbackText: session.delegateName.isNotEmpty ? session.delegateName : 'م',
          radius: 19,
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.delegateName,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: BranchNameLabel(
                      branchName: session.branchName,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      checkInStr,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeofencePill({
    required Color statusColor,
    required Color statusBgColor,
    required String statusTitle,
    required IconData statusIcon,
    required ColorScheme colorScheme,
  }) {
    final session = widget.session;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    statusTitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (session.isMockLocationDetected) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'تم رصد استخدام تطبيق موقع وهمي!',
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.gpp_bad_rounded,
                size: 14,
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTelemetryBar({required ColorScheme colorScheme}) {
    final session = widget.session;
    final batteryLvl = session.batteryLevel;
    final speed = session.speed;
    final isMoving = session.isMoving == true;
    final timeStr = _formatLastUpdated(session.lastUpdated);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
          // Battery
          Tooltip(
            message: 'نسبة شحن البطارية: ${batteryLvl != null ? "$batteryLvl%" : "غير متوفر"}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (batteryLvl != null && batteryLvl <= 20)
                      ? Icons.battery_alert_rounded
                      : Icons.battery_charging_full_rounded,
                  size: 13,
                  color: _getBatteryColor(batteryLvl),
                ),
                const SizedBox(width: 3),
                Text(
                  batteryLvl != null ? '$batteryLvl%' : '—',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _getBatteryColor(batteryLvl),
                  ),
                ),
              ],
            ),
          ),
          // Speed
          Tooltip(
            message: 'سرعة التحرك الحالية',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_rounded, size: 13, color: colorScheme.primary),
                const SizedBox(width: 3),
                Text(
                  speed != null ? '${speed.toStringAsFixed(0)} كم' : '0',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // Motion
          Tooltip(
            message: isMoving ? 'حالة الحركة: متحرك' : 'حالة الحركة: متوقف',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMoving ? Icons.directions_run_rounded : Icons.pan_tool_rounded,
                  size: 13,
                  color: isMoving ? const Color(0xFFC65102) : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  isMoving ? 'متحرك' : 'متوقف',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isMoving ? const Color(0xFFC65102) : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Last update
          Tooltip(
            message: 'توقيت آخر إشارة: $timeStr',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time_rounded, size: 13, color: colorScheme.primary),
                const SizedBox(width: 3),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildTrackingSwitch({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final session = widget.session;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 6, end: 10, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: session.isTrackingEnabled
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: session.isTrackingEnabled
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            width: 36,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: session.isTrackingEnabled,
                activeThumbColor: colorScheme.primary,
                activeTrackColor: colorScheme.primaryContainer,
                inactiveThumbColor: colorScheme.outline,
                inactiveTrackColor: colorScheme.surfaceContainerHighest,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: widget.onToggleTracking,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            session.isTrackingEnabled ? 'تتبع نشط' : 'متوقف',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: session.isTrackingEnabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions({
    required BuildContext context,
    required ColorScheme colorScheme,
  }) {
    final session = widget.session;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
        if (session.delegatePhone.isNotEmpty) ...[
          IconButton.filledTonal(
            onPressed: () => _makeCall(context),
            icon: const Icon(Icons.call_rounded, size: 15),
            tooltip: 'اتصال هاتفي',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
              foregroundColor: colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            onPressed: () => _openWhatsApp(context),
            icon: const Icon(Icons.chat_rounded, size: 15),
            tooltip: 'واتساب',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
              foregroundColor: colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
            ),
          ),
          const SizedBox(width: 4),
        ],
        IconButton.filledTonal(
          onPressed: () {
            if (widget.onFocusOnMap != null) {
              widget.onFocusOnMap!();
            } else {
              _openMap(context);
            }
          },
          icon: Icon(
            widget.onFocusOnMap != null
                ? Icons.my_location_rounded
                : Icons.map_rounded,
            size: 15,
          ),
          tooltip: widget.onFocusOnMap != null
              ? 'توسيط المسار على الخريطة'
              : 'عرض على الخريطة',
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
            foregroundColor: colorScheme.primary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
          ),
        ),
        if (widget.onRefreshPing != null) ...[
          const SizedBox(width: 4),
          IconButton.filledTonal(
            onPressed: widget.onRefreshPing,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            tooltip: 'تحديث الإشارة',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
              foregroundColor: colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ],
        if (widget.onClose != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded, size: 16),
            tooltip: 'إغلاق',
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
            ),
          ),
        ],
      ],
    ),
  );
  }
}
