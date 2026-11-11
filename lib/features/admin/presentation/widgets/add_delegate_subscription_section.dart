import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Subscription cycle banner, payment cards, and submit CTA used by
/// [AddDelegateFormScreen]. Kept public so tests and screenshots pump the
/// same widget tree the form uses.
class AddDelegateCycleBanner extends StatelessWidget {
  const AddDelegateCycleBanner({
    super.key,
    required this.isFree,
    this.colorScheme,
  });

  final bool isFree;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final cycleTitle = SubscriptionCycleHelper.getCycleTitleArabic();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFree
            ? const Color(0xFFDCFCE7).withValues(alpha: 0.6)
            : cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFree
              ? const Color(0xFF86EFAC)
              : cs.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isFree ? const Color(0xFF16A34A) : cs.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFree ? Icons.local_offer_rounded : Symbols.date_range_rounded,
              color: isFree ? Colors.white : cs.onPrimary,
              size: 20,
              fill: 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFree
                      ? 'عرض ترويجي مجاني ممتد لنهاية العام'
                      : 'دورة الاشتراك النصف سنوية المطبقة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isFree ? const Color(0xFF14532D) : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isFree
                      ? 'الخدمة مجانية بالكامل لجميع السلاسل والمنظمات حتى 31 ديسمبر 2026'
                      : cycleTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isFree
                        ? const Color(0xFF15803D)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddDelegatePaymobCard extends StatelessWidget {
  const AddDelegatePaymobCard({
    super.key,
    this.companyUID,
    this.colorScheme,
  });

  final String? companyUID;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final months = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee(null, companyUID);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.credit_card_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الدفع إلكترونيًا عبر Paymob',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${SubscriptionCycleHelper.formatEgp(fee)} ج.م',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'اشتراك $months ${months == 1 ? 'شهر' : 'أشهر'} حتى نهاية ${SubscriptionCycleHelper.getCycleShortTitleArabic()}. '
              'الاشتراك الواحد يغطي كل السلاسل. يتم تفعيل المندوب بعد تأكيد الدفع واعتماد المستندات.',
              style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class AddDelegateSubmitButton extends StatelessWidget {
  const AddDelegateSubmitButton({
    super.key,
    required this.isFree,
    required this.isBusy,
    this.onSubmit,
  });

  final bool isFree;
  final bool isBusy;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          minimumSize: const Size(48, 56),
          shape: const StadiumBorder(),
          elevation: 1,
          iconAlignment: IconAlignment.start,
        ),
        onPressed: isBusy ? null : onSubmit,
        icon: isBusy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.onPrimary,
                ),
              )
            : const Icon(Symbols.send_rounded, size: 24, fill: 0),
        label: Text(
          isBusy
              ? 'جاري رفع البيانات وإرسال الطلب...'
              : (isFree ? 'إرسال طلب التسجيل (مجاناً)' : 'إرسال طلب التسجيل'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class AddDelegateSubscriptionSection extends StatelessWidget {
  const AddDelegateSubscriptionSection({
    super.key,
    required this.isFree,
    this.companyUID,
    this.isBusy = false,
    this.onSubmit,
    this.showSubmit = true,
  });

  final bool isFree;
  final String? companyUID;
  final bool isBusy;
  final VoidCallback? onSubmit;
  final bool showSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final months = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee(null, companyUID);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AddDelegateCycleBanner(isFree: isFree),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              isFree ? Icons.card_giftcard_rounded : Symbols.payments_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isFree
                    ? 'الاشتراك والربط (مجاناً حتى 31/12)'
                    : 'الاشتراك والدفع الإلكتروني ($months أشهر - ${SubscriptionCycleHelper.formatEgp(fee)} ج.م)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isFree)
          AddDelegateFreePromotionCard(colorScheme: colorScheme)
        else
          AddDelegatePaymobCard(companyUID: companyUID, colorScheme: colorScheme),
        if (showSubmit) ...[
          const SizedBox(height: 24),
          AddDelegateSubmitButton(isFree: isFree, isBusy: isBusy, onSubmit: onSubmit),
        ],
      ],
    );
  }
}

class AddDelegateFreePromotionCard extends StatelessWidget {
  const AddDelegateFreePromotionCard({super.key, this.colorScheme});

  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerLow
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? const Color(0xFF16A34A).withValues(alpha: 0.4)
              : const Color(0xFF86EFAC),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: isDark ? 0.05 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF166534).withValues(alpha: 0.4)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF16A34A) : const Color(0xFF86EFAC),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      size: 15,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'عرض خاص حتى 31 ديسمبر 2026',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'مجاناً 0 ج.م',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Main Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF166534).withValues(alpha: 0.4)
                      : const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'اشتراك ومتابعة مجاناً بالكامل حتى 31/12',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? cs.onSurface : const Color(0xFF14532D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Clarifying Announcement Message Box (User exact words)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainer
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? cs.outlineVariant
                    : const Color(0xFFBBF7D0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'يمكنك الآن إضافة المناديب للسلاسل والمنظمات الأخرى ومتابعة حضورهم وانصرافهم ورفع التصوير مجاناً بالكامل حتى 31/12 بدون أي رسوم اشتراك.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? cs.onSurface : const Color(0xFF1F2937),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Benefit Checkpoints
          _AddDelegatePromotionBenefitItem(
            cs,
            icon: Icons.storefront_rounded,
            title: 'إضافة غير محدودة لكافة السلاسل الشريكة',
            subtitle: 'سجل مناديبك في زهران ماركت، جملة ماركت، كارفور، وبيت الجملة.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _AddDelegatePromotionBenefitItem(
            cs,
            icon: Icons.access_time_filled_rounded,
            title: 'متابعة لحظية للحضور والانصراف',
            subtitle: 'تقارير ميدانية موحدة لضبط التواجد والالتزام بساعات العمل.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _AddDelegatePromotionBenefitItem(
            cs,
            icon: Icons.camera_alt_rounded,
            title: 'رفع تقارير وأذونات التصوير الميداني',
            subtitle: 'إدارة وتفعيل أذونات التصوير الشهرية ومراجعة معروضات المندوب.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _AddDelegatePromotionBenefitItem(
            cs,
            icon: Icons.money_off_rounded,
            title: 'بدون أي إجراء مالي أو إيصالات',
            subtitle: 'لا يلزم سداد أي مبالغ أو إرفاق إيصالات دفع خلال فترة العرض.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          // Reassurance Note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainerHigh
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم اعتماد وتفعيل حساب المندوب فور مراجعة المستندات من الدعم الفني.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddDelegatePromotionBenefitItem extends StatelessWidget {
  const _AddDelegatePromotionBenefitItem(
    this.colorScheme, {
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  final ColorScheme colorScheme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF166534).withValues(alpha: 0.3)
                : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF16A34A)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.onSurface : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
