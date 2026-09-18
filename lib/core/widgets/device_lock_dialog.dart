import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';

/// نافذة أمان مخصصة عند محاولة الدخول من جهاز غير مطابق لجهاز المندوب المعتمد
class DeviceLockDialog extends StatelessWidget {
  final String? boundDeviceModel;
  final String? currentDeviceModel;
  final String? delegateName;

  const DeviceLockDialog({
    super.key,
    this.boundDeviceModel,
    this.currentDeviceModel,
    this.delegateName,
  });

  static Future<void> show(
    BuildContext context, {
    String? boundDeviceModel,
    String? currentDeviceModel,
    String? delegateName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeviceLockDialog(
        boundDeviceModel: boundDeviceModel,
        currentDeviceModel: currentDeviceModel,
        delegateName: delegateName,
      ),
    );
  }

  Future<void> _makeCall(BuildContext context) async {
    const phone = DeviceBindingService.technicalSupportPhone;
    final uri = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    const phone = DeviceBindingService.technicalSupportPhone;
    final cleanPhone = '2$phone';
    final message = Uri.encodeComponent(
      'السلام عليكم، أرجو فك ربط جهازي بحساب المندوب ${delegateName != null ? "($delegateName)" : ""}. قمت بتغيير الهاتف.',
    );
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$message');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final boundModel = (boundDeviceModel != null && boundDeviceModel!.trim().isNotEmpty)
        ? boundDeviceModel!
        : 'جهاز معتمد سابق';

    return PopScope(
      canPop: true,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerHigh,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header Shield / Lock Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Icon(
                  Icons.phonelink_lock_rounded,
                  color: colorScheme.error,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),

              // 2. Title
              Text(
                'تنبيه أمان: الحساب مقترن بجهاز آخر',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),

              // 3. Explanation
              Text(
                'عزيزي المندوب، هذا الحساب مصرح له بالعمل فقط من خلال جهازك المعتمد المسجل مسبقاً لدى النظام.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // 4. Device Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'الجهاز المعتمد للحساب:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 26),
                        child: Text(
                          boundModel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    if (currentDeviceModel != null && currentDeviceModel!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.cancel_rounded, color: colorScheme.error, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'الجهاز الحالي المستخدم:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 26),
                          child: Text(
                            currentDeviceModel!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Text(
                'إذا قمت بتغيير هاتفك أو استبداله، يرجى التواصل مع الدعم الفني لفك ربط الجهاز القديم وتفعيل هاتفك الجديد.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 18),

              // 5. Direct Action Call Support Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _makeCall(context),
                  icon: const Icon(Icons.phone_forwarded_rounded, size: 20),
                  label: const Text(
                    'اتصال بالدعم الفني (${DeviceBindingService.technicalSupportPhone})',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 6. WhatsApp Support Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openWhatsApp(context),
                  icon: Icon(Icons.chat_rounded, size: 18, color: colorScheme.secondary),
                  label: Text(
                    'مراسلة الدعم الفني عبر واتساب',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.secondary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.secondary.withValues(alpha: 0.5), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 7. Cancel / Close
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إغلاق',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
