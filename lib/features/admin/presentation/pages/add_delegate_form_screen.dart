import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/injection_container.dart';

class AddDelegateFormScreen extends StatefulWidget {
  final Delegate supervisor;

  const AddDelegateFormScreen({super.key, required this.supervisor});

  @override
  State<AddDelegateFormScreen> createState() => _AddDelegateFormScreenState();
}

class _AddDelegateFormScreenState extends State<AddDelegateFormScreen> {
  static const String _instaPayLink = 'https://ipn.eg/S/fathall/instapay/1VphF7';

  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _firstNameController = TextEditingController();
  final _secondNameController = TextEditingController();
  final _thirdNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _receiptCodeController = TextEditingController();

  // Organizations
  List<Map<String, dynamic>> _organizations = [];
  String? _selectedOrgUID;
  String? _selectedOrgName;
  bool _isLoadingOrgs = true;

  // Uploaded Files
  File? _profileImage;
  File? _nationalIdFront;
  File? _nationalIdBack;
  File? _receiptImage;

  // Payment Selection
  SubscriptionPaymentMethod _paymentMethod = SubscriptionPaymentMethod.companyDeduction;

  // Receipt code validation state
  bool _isCheckingReceiptCode = false;
  bool? _isReceiptCodeValid;
  String? _receiptCodeStatusText;

  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (SubscriptionCycleHelper.isFreePromotionActive()) {
      _paymentMethod = SubscriptionPaymentMethod.freePromotion;
    }
    _fetchOrganizations();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _secondNameController.dispose();
    _thirdNameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _receiptCodeController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganizations() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('organizations').get();
      final orgs = snap.docs
          .map((doc) {
            final data = doc.data();
            return {
              'uid': doc.id,
              'name': data['name'] ?? data['title'] ?? doc.id,
            };
          })
          .where((org) {
            final name = (org['name'] ?? '').toString().toLowerCase();
            final uid = (org['uid'] ?? '').toString().toLowerCase();
            // استبعاد أسواق فتح الله لأن لها آلية تسجيل خاصة عبر الموقع الإلكتروني
            final isFathalla = name.contains('fathalla') ||
                name.contains('فتح الله') ||
                name.contains('فتح_الله') ||
                uid.contains('fathalla') ||
                uid.contains('فتح_الله');
            return !isFathalla;
          })
          .toList();

      if (mounted) {
        setState(() {
          _organizations = orgs;
          if (_organizations.isNotEmpty) {
            _selectedOrgUID = _organizations.first['uid'];
            _selectedOrgName = _organizations.first['name'];
          }
          _isLoadingOrgs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingOrgs = false);
    }
  }

  Future<void> _pickImage(void Function(File file) onSelected) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        onSelected(File(picked.path));
      });
    }
  }

  Future<void> _openInstaPayUrl() async {
    final uri = Uri.parse(_instaPayLink);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'تعذر فتح رابط انستاباي تلقائياً.');
      }
    }
  }

  Future<void> _copyInstaPayLink() async {
    await Clipboard.setData(const ClipboardData(text: _instaPayLink));
    if (mounted) {
      AppSnackBar.showSuccess(context, 'تم نسخ رابط حساب انستاباي بنجاح');
    }
  }

  Future<void> _checkReceiptCode(String code) async {
    final clean = code.trim();
    if (clean.length != 5) {
      setState(() {
        _isCheckingReceiptCode = false;
        _isReceiptCodeValid = null;
        _receiptCodeStatusText = null;
      });
      return;
    }

    setState(() {
      _isCheckingReceiptCode = true;
      _receiptCodeStatusText = 'جاري التحقق من توفر كود الإيصال...';
    });

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.isReceiptCodeUsed(clean);

    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() {
          _isCheckingReceiptCode = false;
          _isReceiptCodeValid = null;
          _receiptCodeStatusText = 'تعذر التحقق: ${failure.message}';
        });
      },
      (isUsed) {
        setState(() {
          _isCheckingReceiptCode = false;
          _isReceiptCodeValid = !isUsed;
          _receiptCodeStatusText = isUsed
              ? 'عذراً، كود الإيصال ($clean) مستخدم مسبقاً وغير صالح للاستخدام.'
              : 'كود الإيصال متاح وصالح للاستخدام ✓';
        });
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      AppSnackBar.showError(context, 'يرجى استكمال البيانات المطلوبة وتصحيح الأخطاء.');
      return;
    }

    if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
      AppSnackBar.showError(context, 'يرجى اختيار المنظمة / السلسلة التجارية المستهدفة.');
      return;
    }

    if (_profileImage == null) {
      AppSnackBar.showError(context, 'يرجى رفع الصورة الشخصية للمندوب.');
      return;
    }

    if (_nationalIdFront == null || _nationalIdBack == null) {
      AppSnackBar.showError(context, 'يرجى رفع صورة بطاقة الرقم القومي (الوجه والظهر).');
      return;
    }

    if (_paymentMethod == SubscriptionPaymentMethod.branchReceipt) {
      final code = _receiptCodeController.text.trim();
      if (code.length != 5) {
        AppSnackBar.showError(context, 'كود الإيصال الإلكتروني يجب أن يتكون من 5 أرقام بالضبط.');
        return;
      }
      if (_isReceiptCodeValid == false) {
        AppSnackBar.showError(
          context,
          'كود الإيصال الخماسي ($code) مستخدم مسبقاً في النظام، يرجى إدخال كود صالح.',
        );
        return;
      }
      if (_receiptImage == null) {
        AppSnackBar.showError(context, 'يرجى إرفاق صورة الإيصال الإلكتروني من تسويق الفرع.');
        return;
      }
    } else if (_paymentMethod == SubscriptionPaymentMethod.instaPay) {
      if (_receiptImage == null) {
        AppSnackBar.showError(context, 'يرجى إرفاق صورة إيصال التحويل أو إشعار الدفع من تطبيق انستاباي.');
        return;
      }
    }

    setState(() => _isSubmitting = true);

    // Hard pre-validation check against duplicate receipt code before uploading files
    if (_paymentMethod == SubscriptionPaymentMethod.branchReceipt) {
      final code = _receiptCodeController.text.trim();
      final repo = sl<DelegateSubscriptionRepository>();
      final checkResult = await repo.isReceiptCodeUsed(code);
      final isUsed = checkResult.fold((_) => false, (used) => used);
      if (isUsed) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _isReceiptCodeValid = false;
          _receiptCodeStatusText = 'عذراً، كود الإيصال ($code) مستخدم مسبقاً وغير صالح للاستخدام.';
        });
        AppSnackBar.showError(
          context,
          'كود الإيصال الخماسي ($code) مستخدم مسبقاً في النظام ولا يمكن تكراره.',
        );
        return;
      }
    }

    final remainingMonths = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee();

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.submitSubscriptionRequest(
      supervisorUid: widget.supervisor.uid,
      supervisorName: widget.supervisor.fullName,
      supervisorPhone: widget.supervisor.phoneNumber,
      companyUID: widget.supervisor.companyUID,
      companyName: widget.supervisor.companyName,
      organizationUID: _selectedOrgUID!,
      organizationName: _selectedOrgName ?? _selectedOrgUID!,
      firstName: _firstNameController.text.trim(),
      secondName: _secondNameController.text.trim(),
      thirdName: _thirdNameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      nationalId: _nationalIdController.text.trim(),
      profileImage: _profileImage!,
      nationalIdFront: _nationalIdFront!,
      nationalIdBack: _nationalIdBack!,
      paymentMethod: _paymentMethod,
      fee: fee,
      remainingMonths: remainingMonths,
      receiptCode: _paymentMethod == SubscriptionPaymentMethod.branchReceipt
          ? _receiptCodeController.text.trim()
          : null,
      receiptImage: (_paymentMethod == SubscriptionPaymentMethod.branchReceipt ||
              _paymentMethod == SubscriptionPaymentMethod.instaPay)
          ? _receiptImage
          : null,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    await result.fold(
      (failure) async {
        AppSnackBar.showError(context, failure.message);
      },
      (requestId) async {
        final isFree = _paymentMethod == SubscriptionPaymentMethod.freePromotion;
        AppSnackBar.showSuccess(
          context,
          isFree
              ? 'تم إرسال طلب تسجيل المندوب بنجاح (مجاناً ضمن العرض الترويجي)! بانتظار اعتماد الإدارة.'
              : 'تم إرسال طلب تسجيل واشتراك المندوب بنجاح! بانتظار اعتماد الدعم الفني.',
        );

        final goToApprovals = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Theme.of(ctx).colorScheme.primary, size: 26),
                const SizedBox(width: 10),
                const Text('تم إرسال الطلب بنجاح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: const Text(
              'تم إرسال طلب تسجيل المندوب بنجاح! يمكنك الآن متابعة حالة اعتماد المندوب (قيد الانتظار / تم الاعتماد / مرفوض) من شاشة الاعتمادات.',
              style: TextStyle(fontSize: 13.5, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('العودة للمناديب'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                label: const Text('عرض شاشة الاعتمادات'),
              ),
            ],
          ),
        );

        if (!mounted) return;
        if (goToApprovals == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DelegateSubscriptionRequestsPage(
                currentAdmin: widget.supervisor,
              ),
            ),
          );
        } else {
          Navigator.pop(context, true);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'إضافة مندوب لمنظمة جديدة',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoadingOrgs
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Subscription Cycle Info Card
                      _buildCycleBanner(colorScheme),
                      const SizedBox(height: 16),

                      // 2. Select Organization Section
                      _buildOrganizationSelector(colorScheme),
                      const SizedBox(height: 16),

                      // 3. Personal Information
                      _buildSectionHeader('البيانات الشخصية للمندوب', Icons.badge_rounded),
                      const SizedBox(height: 8),
                      _buildPersonalInfoCard(colorScheme),
                      const SizedBox(height: 16),

                      // 4. Documents & Photos Upload
                      _buildSectionHeader('المستندات والصور المرفقة', Icons.upload_file_rounded),
                      const SizedBox(height: 8),
                      _buildDocumentsCard(colorScheme),
                      const SizedBox(height: 16),

                      // 5. Payment Method & Subscription
                      _buildSectionHeader(
                        SubscriptionCycleHelper.isFreePromotionActive()
                            ? 'الاشتراك والربط (مجاناً حتى 31/12)'
                            : 'طريقة دفع الاشتراك (${SubscriptionCycleHelper.getRemainingMonthsInCycle()} أشهر - ${SubscriptionCycleHelper.getProratedSubscriptionFee().toInt()} ج.م)',
                        SubscriptionCycleHelper.isFreePromotionActive()
                            ? Icons.card_giftcard_rounded
                            : Icons.payments_rounded,
                      ),
                      const SizedBox(height: 8),
                      SubscriptionCycleHelper.isFreePromotionActive()
                          ? _buildFreePromotionCard(colorScheme)
                          : _buildPaymentCard(colorScheme),
                      const SizedBox(height: 24),

                      // 6. Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 1,
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          icon: _isSubmitting
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 22),
                          label: Text(
                            _isSubmitting
                                ? 'جاري رفع البيانات وإرسال الطلب...'
                                : (SubscriptionCycleHelper.isFreePromotionActive()
                                    ? 'إرسال طلب التسجيل (مجاناً)'
                                    : 'إرسال طلب التسجيل'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCycleBanner(ColorScheme colorScheme) {
    final isFree = SubscriptionCycleHelper.isFreePromotionActive();
    final cycleTitle = SubscriptionCycleHelper.getCycleTitleArabic();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFree
            ? const Color(0xFFDCFCE7).withValues(alpha: 0.6)
            : colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFree
              ? const Color(0xFF86EFAC)
              : colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isFree ? const Color(0xFF16A34A) : colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFree ? Icons.local_offer_rounded : Icons.date_range_rounded,
              color: Colors.white,
              size: 20,
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
                    color: isFree ? const Color(0xFF14532D) : colorScheme.onSurface,
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
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationSelector(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.corporate_fare_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'المنظمة / السلسلة التجارية المستهدفة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedOrgUID,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              items: _organizations.map((org) {
                return DropdownMenuItem<String>(
                  value: org['uid'] as String,
                  child: Text(org['name'] as String),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedOrgUID = val;
                    final found = _organizations.firstWhere(
                      (o) => o['uid'] == val,
                      orElse: () => {'name': val},
                    );
                    _selectedOrgName = found['name'];
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  InputDecoration _buildM3InputDecoration({
    required BuildContext context,
    required String labelText,
    String? hintText,
    String? helperText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.normal,
        color: colorScheme.onSurfaceVariant,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colorScheme.primary,
      ),
      hintStyle: TextStyle(
        fontSize: 11.5,
        color: colorScheme.outline.withValues(alpha: 0.6),
      ),
      helperStyle: TextStyle(
        fontSize: 10.5,
        color: colorScheme.outline,
      ),
      errorStyle: const TextStyle(
        fontSize: 10,
        height: 1.1,
      ),
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.error,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: _buildM3InputDecoration(
                      context: context,
                      labelText: 'الاسم الأول *',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _secondNameController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: _buildM3InputDecoration(
                      context: context,
                      labelText: 'اسم الأب *',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _thirdNameController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: _buildM3InputDecoration(
                      context: context,
                      labelText: 'اللقب *',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13),
              decoration: _buildM3InputDecoration(
                context: context,
                labelText: 'رقم الهاتف (لتسجيل الدخول) *',
                hintText: '01xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_android_rounded, size: 20, color: colorScheme.primary),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'يرجى إدخال رقم الهاتف';
                if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(v.trim())) {
                  return 'يرجى إدخال رقم هاتف مصري صحيح (11 رقم يبدأ بـ 01)';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nationalIdController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(14),
              ],
              style: const TextStyle(fontSize: 13),
              decoration: _buildM3InputDecoration(
                context: context,
                labelText: 'الرقم القومي (14 رقم) للباسورد *',
                helperText: 'يُعتمد الرقم القومي ككلمة مرور افتراضية لتسجيل دخول المندوب',
                prefixIcon: Icon(Icons.credit_card_rounded, size: 20, color: colorScheme.primary),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'يرجى إدخال الرقم القومي';
                if (v.trim().length != 14) return 'الرقم القومي يجب أن يتكون من 14 رقماً';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _buildImagePickerTile(
              title: 'الصورة الشخصية للمندوب *',
              subtitle: 'صورة واضحة للوجه بخلفية مضيئة',
              icon: Icons.account_circle_rounded,
              file: _profileImage,
              onPick: () => _pickImage((f) => _profileImage = f),
              onRemove: () => setState(() => _profileImage = null),
            ),
            const Divider(height: 20),
            _buildImagePickerTile(
              title: 'بطاقة الرقم القومي (الوجه) *',
              subtitle: 'صورة واضحة لوجه البطاقة القومية',
              icon: Icons.featured_play_list_rounded,
              file: _nationalIdFront,
              onPick: () => _pickImage((f) => _nationalIdFront = f),
              onRemove: () => setState(() => _nationalIdFront = null),
            ),
            const Divider(height: 20),
            _buildImagePickerTile(
              title: 'بطاقة الرقم القومي (الظهر) *',
              subtitle: 'صورة واضحة لظهر البطاقة القومية',
              icon: Icons.flip_rounded,
              file: _nationalIdBack,
              onPick: () => _pickImage((f) => _nationalIdBack = f),
              onRemove: () => setState(() => _nationalIdBack = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required File? file,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 28, color: colorScheme.outline),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        if (file != null)
          IconButton(
            icon: Icon(Icons.close_rounded, color: colorScheme.error, size: 20),
            onPressed: onRemove,
            tooltip: 'حذف',
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
            label: const Text('اختيار', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  /// كارت العرض الترويجي المجاني (حتى 31/12) بمواصفات Material Design 3
  Widget _buildFreePromotionCard(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerLow
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
                    color: isDark ? colorScheme.onSurface : const Color(0xFF14532D),
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
                  ? colorScheme.surfaceContainer
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? colorScheme.outlineVariant
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
                      color: isDark ? colorScheme.onSurface : const Color(0xFF1F2937),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Benefit Checkpoints
          _buildPromotionBenefitItem(
            colorScheme,
            icon: Icons.storefront_rounded,
            title: 'إضافة غير محدودة لكافة السلاسل الشريكة',
            subtitle: 'سجل مناديبك في زهران ماركت، جملة ماركت، كارفور، وبيت الجملة.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildPromotionBenefitItem(
            colorScheme,
            icon: Icons.access_time_filled_rounded,
            title: 'متابعة لحظية للحضور والانصراف',
            subtitle: 'تقارير ميدانية موحدة لضبط التواجد والالتزام بساعات العمل.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildPromotionBenefitItem(
            colorScheme,
            icon: Icons.camera_alt_rounded,
            title: 'رفع تقارير وأذونات التصوير الميداني',
            subtitle: 'إدارة وتفعيل أذونات التصوير الشهرية ومراجعة معروضات المندوب.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildPromotionBenefitItem(
            colorScheme,
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
                  ? colorScheme.surfaceContainerHigh
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم اعتماد وتفعيل حساب المندوب فور مراجعة المستندات من الدعم الفني.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
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

  Widget _buildPromotionBenefitItem(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
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

  Widget _buildPaymentCard(ColorScheme colorScheme) {
    final remainingMonths = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee();
    final isFullCycle = remainingMonths == 6;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Prorated Subscription Fee Notice Banner ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.price_check_rounded,
                      color: colorScheme.onPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isFullCycle
                                  ? 'الاشتراك (6 أشهر)'
                                  : 'الاشتراك ($remainingMonths أشهر متبقية)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${fee.toInt()} ج.م',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isFullCycle
                              ? 'قيمة الاشتراك كاملة للدورة النصف سنوية هي 500 ج.م.'
                              : 'متبقي $remainingMonths أشهر حتى نهاية دورة الاشتراك الحالية. تم تقليل قيمة الشهور المنقضية لتصبح التكلفة المطلوبة ${fee.toInt()} ج.م بدلاً من 500 ج.م.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Payment Option Cards with Nested Expandable Details
            RadioGroup<SubscriptionPaymentMethod>(
              groupValue: _paymentMethod,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _paymentMethod = val;
                    if (val == SubscriptionPaymentMethod.companyDeduction) {
                      _receiptImage = null;
                      _receiptCodeController.clear();
                      _isReceiptCodeValid = null;
                      _receiptCodeStatusText = null;
                    }
                  });
                }
              },
              child: Column(
                children: [
                  // Option 1: Company Deduction Card
                  InkWell(
                    onTap: () {
                      setState(() {
                        _paymentMethod = SubscriptionPaymentMethod.companyDeduction;
                        _receiptImage = null;
                        _receiptCodeController.clear();
                        _isReceiptCodeValid = null;
                        _receiptCodeStatusText = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: AppMotionDurations.short4,
                      curve: AppMotionCurves.standard,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == SubscriptionPaymentMethod.companyDeduction
                            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _paymentMethod == SubscriptionPaymentMethod.companyDeduction
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          width: _paymentMethod == SubscriptionPaymentMethod.companyDeduction ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Radio<SubscriptionPaymentMethod>(
                            value: SubscriptionPaymentMethod.companyDeduction,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'خصم من حساب الشركة (${fee.toInt()} ج.م)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'يتم قيد قيمة الاشتراك المستحقة (${fee.toInt()} ج.م) على الفاتورة الدورية لشركتكم مباشرة.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 2: InstaPay Card (with Nested Details)
                InkWell(
                  onTap: () {
                    setState(() {
                      _paymentMethod = SubscriptionPaymentMethod.instaPay;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: AppMotionDurations.short4,
                    curve: AppMotionCurves.standard,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _paymentMethod == SubscriptionPaymentMethod.instaPay
                          ? const Color(0xFF6B21A8).withValues(alpha: 0.08)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _paymentMethod == SubscriptionPaymentMethod.instaPay
                            ? const Color(0xFF9333EA)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: _paymentMethod == SubscriptionPaymentMethod.instaPay ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Radio<SubscriptionPaymentMethod>(
                              value: SubscriptionPaymentMethod.instaPay,
                              activeColor: const Color(0xFF9333EA),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'تحويل عبر انستاباي - InstaPay (${fee.toInt()} ج.م)',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                      ),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.purple.shade200),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.asset(
                                            'assets/images/instapay_logo.png',
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'الدفع المباشر عبر حساب انستاباي ورفع صورة إيصال التحويل أو إشعار الدفع.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Animated Expansion directly inside the InstaPay Card!
                        AnimatedSize(
                          duration: AppMotionDurations.medium3,
                          curve: AppMotionCurves.emphasized,
                          alignment: Alignment.topCenter,
                          child: _paymentMethod == SubscriptionPaymentMethod.instaPay
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF9333EA).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.purple.shade200),
                                              ),
                                              child: ClipOval(
                                                child: Image.asset(
                                                  'assets/images/instapay_logo.png',
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'الدفع عبر تطبيق انستاباي (InstaPay)',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: colorScheme.onSurface,
                                                    ),
                                                  ),
                                                  Text(
                                                    'المبلغ المطلوب: ${fee.toInt()} ج.م',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF9333EA),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        // Link Box with Copy Button
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.link_rounded, size: 18, color: Color(0xFF9333EA)),
                                              const SizedBox(width: 8),
                                              const Expanded(
                                                child: SelectableText(
                                                  _instaPayLink,
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'نسخ الرابط',
                                                icon: const Icon(Icons.copy_rounded, size: 16),
                                                visualDensity: VisualDensity.compact,
                                                onPressed: _copyInstaPayLink,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        // Action Button to Launch Link
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFF6B21A8),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            icon: Container(
                                              width: 22,
                                              height: 22,
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(3),
                                                child: Image.asset(
                                                  'assets/images/instapay_logo.png',
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            label: const Text(
                                              'اضغط للدفع عبر انستاباي',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            onPressed: _openInstaPayUrl,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Screenshot picker
                                        _buildImagePickerTile(
                                          title: 'صورة إيصال التحويل من انستاباي *',
                                          subtitle: 'صورة واضحة أو لقطة شاشة لإشعار نجاح التحويل',
                                          icon: Icons.receipt_long_rounded,
                                          file: _receiptImage,
                                          onPick: () => _pickImage((f) => _receiptImage = f),
                                          onRemove: () => setState(() => _receiptImage = null),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 3: Branch Electronic Receipt Card (with Nested Details)
                InkWell(
                  onTap: () {
                    setState(() {
                      _paymentMethod = SubscriptionPaymentMethod.branchReceipt;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: AppMotionDurations.short4,
                    curve: AppMotionCurves.standard,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _paymentMethod == SubscriptionPaymentMethod.branchReceipt
                          ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _paymentMethod == SubscriptionPaymentMethod.branchReceipt
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: _paymentMethod == SubscriptionPaymentMethod.branchReceipt ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Radio<SubscriptionPaymentMethod>(
                              value: SubscriptionPaymentMethod.branchReceipt,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'إيصال إلكتروني من تسويق الفرع (${fee.toInt()} ج.م)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'إدخال كود الإيصال الخماسي (5 أرقام) ورفع صورة الإيصال الصادر من تسويق الفرع.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Animated Expansion directly inside Branch Receipt Card!
                        AnimatedSize(
                          duration: AppMotionDurations.medium3,
                          curve: AppMotionCurves.emphasized,
                          alignment: Alignment.topCenter,
                          child: _paymentMethod == SubscriptionPaymentMethod.branchReceipt
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colorScheme.primary.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: colorScheme.primaryContainer,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.receipt_long_rounded,
                                                size: 18,
                                                color: colorScheme.onPrimaryContainer,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'بيانات الإيصال الإلكتروني من تسويق الفرع',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: colorScheme.onSurface,
                                                    ),
                                                  ),
                                                  Text(
                                                    'المبلغ المطلوب: ${fee.toInt()} ج.م',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: colorScheme.primary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _receiptCodeController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                            LengthLimitingTextInputFormatter(5),
                                          ],
                                          onChanged: (val) {
                                            _checkReceiptCode(val);
                                          },
                                          decoration: _buildM3InputDecoration(
                                            context: context,
                                            labelText: 'كود الإيصال / العملية (5 أرقام) *',
                                            hintText: 'مثال: 54821',
                                            prefixIcon: const Icon(Icons.tag_rounded),
                                            suffixIcon: _isCheckingReceiptCode
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: Padding(
                                                      padding: EdgeInsets.all(12),
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                  )
                                                : _isReceiptCodeValid == true
                                                    ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                                                    : _isReceiptCodeValid == false
                                                        ? const Icon(Icons.error_rounded, color: Colors.red)
                                                        : null,
                                            helperText: _receiptCodeStatusText,
                                          ).copyWith(
                                            helperStyle: TextStyle(
                                              color: _isReceiptCodeValid == true
                                                  ? Colors.green
                                                  : _isReceiptCodeValid == false
                                                      ? Colors.red
                                                      : colorScheme.onSurfaceVariant,
                                              fontWeight: _isReceiptCodeValid != null ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                          validator: (v) {
                                            if (_paymentMethod == SubscriptionPaymentMethod.branchReceipt) {
                                              if (v == null || v.trim().isEmpty) return 'يرجى إدخال كود الإيصال';
                                              if (v.trim().length != 5) return 'كود الإيصال يتكون من 5 أرقام بالضبط';
                                              if (_isReceiptCodeValid == false) return 'كود الإيصال مستخدم مسبقاً';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _buildImagePickerTile(
                                          title: 'صورة الإيصال الإلكتروني *',
                                          subtitle: 'صورة واضحة للإيصال الصادر من تسويق الفرع',
                                          icon: Icons.receipt_long_rounded,
                                          file: _receiptImage,
                                          onPick: () => _pickImage((f) => _receiptImage = f),
                                          onRemove: () => setState(() => _receiptImage = null),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
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
}
