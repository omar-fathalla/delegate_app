import 'dart:io';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
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
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/injection_container.dart';

class AddDelegateFormScreen extends StatefulWidget {
  final Delegate supervisor;

  const AddDelegateFormScreen({super.key, required this.supervisor});

  @override
  State<AddDelegateFormScreen> createState() => _AddDelegateFormScreenState();
}

class _AddDelegateFormScreenState extends State<AddDelegateFormScreen> {

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
  bool? _isReceiptCodeValid;

  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 2026: free promotion. From 2027 the only method is online (Paymob).
    _paymentMethod = SubscriptionCycleHelper.isFreePromotionActive()
        ? SubscriptionPaymentMethod.freePromotion
        : SubscriptionPaymentMethod.paymob;
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
      final companyUID = widget.supervisor.companyUID;
      final candidates = snap.docs.where((doc) {
        final data = doc.data();
        final name = (data['name'] ?? data['title'] ?? doc.id).toString().toLowerCase();
        final uid = doc.id.toLowerCase();
        // استبعاد أسواق فتح الله لأن لها آلية تسجيل خاصة عبر الموقع الإلكتروني
        final isFathalla = name.contains('fathalla') ||
            name.contains('فتح الله') ||
            name.contains('فتح_الله') ||
            uid.contains('fathalla') ||
            uid.contains('فتح_الله');
        return !isFathalla;
      }).toList();

      final List<Map<String, dynamic>> orgs = [];
      if (companyUID.isEmpty) {
        orgs.addAll(candidates.map((doc) {
          final data = doc.data();
          return {
            'uid': doc.id,
            'name': data['name'] ?? data['title'] ?? doc.id,
          };
        }));
      } else {
        final checks = await Future.wait(candidates.map((doc) async {
          try {
            final cDoc = await FirebaseFirestore.instance
                .collection('organizations')
                .doc(doc.id)
                .collection('companies')
                .doc(companyUID)
                .get();
            if (!cDoc.exists) return null;
            final data = doc.data();
            return {
              'uid': doc.id,
              'name': data['name'] ?? data['title'] ?? doc.id,
            };
          } catch (_) {
            return null;
          }
        }));
        orgs.addAll(checks.whereType<Map<String, dynamic>>());
      }

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
      final checkResult = await repo.isReceiptCodeUsed(
        code,
        companyUID: widget.supervisor.companyUID,
      );
      final isUsed = checkResult.fold((_) => false, (used) => used);
      if (isUsed) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _isReceiptCodeValid = false;
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
              : 'تم إرسال طلب التسجيل بانتظار الدفع الإلكتروني، ثم اعتماد الدعم الفني.',
        );
        if (!isFree) {
          // Paymob checkout: the server creates the order and computes the amount.
          final checkout = await sl<SubscriptionPaymentGateway>().startCheckout(requestId: requestId);
          if (!mounted) return;
          await checkout.fold(
            (f) async => AppSnackBar.showError(context, f.message),
            (c) async => launchUrl(c.checkoutUrl, mode: LaunchMode.externalApplication),
          );
          if (!mounted) return;
        }

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
                            : 'الاشتراك والدفع الإلكتروني (${SubscriptionCycleHelper.getRemainingMonthsInCycle()} أشهر - ${SubscriptionCycleHelper.formatEgp(SubscriptionCycleHelper.getProratedSubscriptionFee())} ج.م)',
                        SubscriptionCycleHelper.isFreePromotionActive()
                            ? Icons.card_giftcard_rounded
                            : Icons.payments_rounded,
                      ),
                      const SizedBox(height: 8),
                      SubscriptionCycleHelper.isFreePromotionActive()
                          ? _buildFreePromotionCard(colorScheme)
                          : _buildPaymobCard(colorScheme),
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
  Widget _buildPaymobCard(ColorScheme colorScheme) {
    final months = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('الدفع إلكترونياً عبر Paymob', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(
                  '${SubscriptionCycleHelper.formatEgp(fee)} ج.م',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'اشتراك $months ${months == 1 ? 'شهر' : 'أشهر'} حتى نهاية ${SubscriptionCycleHelper.getCycleTitleArabic()}. '
              'الاشتراك الواحد يغطي كل السلاسل. يتم تفعيل المندوب بعد تأكيد الدفع واعتماد المستندات.',
              style: TextStyle(fontSize: 12, height: 1.5, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

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

}
