import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/delegate_tracking_session.dart';

class DelegateTrackingCard extends StatelessWidget {
  final DelegateTrackingSession session;
  final ValueChanged<bool> onToggleTracking;
  final VoidCallback? onRefreshPing;

  const DelegateTrackingCard({
    super.key,
    required this.session,
    required this.onToggleTracking,
    this.onRefreshPing,
  });

  String _cleanPhoneNumber(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('01') && p.length == 11) {
      p = '+20${p.substring(1)}';
    }
    return p;
  }

  Future<void> _makeCall(BuildContext context) async {
    final clean = _cleanPhoneNumber(session.delegatePhone);
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
    var clean = _cleanPhoneNumber(session.delegatePhone).replaceAll('+', '');
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
    final lat = session.lastLatitude ?? session.branchLat;
    final lng = session.lastLongitude ?? session.branchLng;
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

    final isOutside = session.isOutside;
    final isOffline = session.isOffline;
    final isInGrace = session.isInGracePeriod;

    Color statusColor;
    Color statusContainerColor;
    String statusTitle;
    String statusSubtitle;
    IconData statusIcon;

    if (isOutside) {
      if (isInGrace) {
        statusColor = colorScheme.error;
        statusContainerColor = colorScheme.errorContainer.withValues(alpha: 0.25);
        statusTitle = 'مغادرة مؤقتة (فترة سماح قيد التأكيد)';
        final remaining = session.remainingGraceSeconds;
        statusSubtitle =
            'تجاوز النطاق - متبقي $remaining ثانية قبل إطلاق الإنذار النهائي';
        statusIcon = Icons.hourglass_top_rounded;
      } else {
        statusColor = colorScheme.error;
        statusContainerColor = colorScheme.errorContainer.withValues(alpha: 0.35);
        statusTitle = 'خارج النطاق المسموح (مزوّغ)';
        final excess =
            (session.currentDistanceMeters - session.geofenceRadius).toInt();
        final breachTimeStr = session.lastBreachAt != null
            ? DateFormat('hh:mm a', 'ar').format(session.lastBreachAt!)
            : '';
        statusSubtitle =
            'تجاوز نطاق الفرع بـ $excess متر ${breachTimeStr.isNotEmpty ? "($breachTimeStr)" : ""}';
        statusIcon = Icons.warning_amber_rounded;
      }
    } else if (isOffline) {
      statusColor = colorScheme.onSurfaceVariant;
      statusContainerColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      statusTitle = 'انقطاع شبكة / غير متصل';
      statusSubtitle = 'الهاتف خارج التغطية - آخر موقع مؤكد: داخل نطاق الفرع';
      statusIcon = Icons.cloud_off_rounded;
    } else {
      statusColor = colorScheme.tertiary;
      statusContainerColor = colorScheme.tertiaryContainer.withValues(alpha: 0.35);
      statusTitle = 'داخل نطاق الفرع المعتمد';
      statusSubtitle =
          'المسافة الحالية: ${session.currentDistanceMeters.toInt()}م من أصل ${session.geofenceRadius.toInt()}م';
      statusIcon = Icons.check_circle_rounded;
    }

    final checkInStr = session.checkInTime != null
        ? DateFormat('hh:mm a', 'ar').format(session.checkInTime!)
        : 'حاضر اليوم';

    return Card(
      elevation: 0,
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: session.isTrackingEnabled
              ? statusColor.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: session.isTrackingEnabled ? 1.5 : 1,
        ),
      ),
      color: session.isTrackingEnabled
          ? statusContainerColor.withValues(alpha: 0.15)
          : colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Delegate Avatar + Name + Check-in badge + Switch
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    session.delegateName.isNotEmpty
                        ? session.delegateName.characters.first
                        : 'م',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.delegateName,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              session.branchName,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              checkInStr,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Switch: تفعيل التتبع
                Column(
                  children: [
                    Switch.adaptive(
                      value: session.isTrackingEnabled,
                      activeThumbColor: colorScheme.primary,
                      onChanged: onToggleTracking,
                    ),
                    Text(
                      session.isTrackingEnabled ? 'تتبع نشط' : 'تتبع متوقف',
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: session.isTrackingEnabled
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (session.isMockLocationDetected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.gpp_bad_rounded, size: 18, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تحذير أمني: تم رصد استخدام موقع وهمي (Mock Location)!',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Row 2: Status Banner
            Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: statusContainerColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, size: 20, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusTitle,
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          statusSubtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: statusColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Row 3: Action Buttons (Call, WhatsApp, Map)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (session.delegatePhone.isNotEmpty) ...[
                  IconButton.filledTonal(
                    onPressed: () => _makeCall(context),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    tooltip: 'اتصال هاتفي',
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    tooltip: 'واتساب',
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton.filledTonal(
                  onPressed: () => _openMap(context),
                  icon: const Icon(Icons.map_rounded, size: 18),
                  tooltip: 'عرض على الخريطة',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const Spacer(),
                if (onRefreshPing != null)
                  TextButton.icon(
                    onPressed: onRefreshPing,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text(
                      'تحديث الإشارة',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
