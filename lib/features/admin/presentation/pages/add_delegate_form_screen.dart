import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
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

    if (_paymentMethod == SubscriptionPaymentMethod.receipt) {
      final code = _receiptCodeController.text.trim();
      if (code.length != 5) {
        AppSnackBar.showError(context, 'كود الإيصال يجب أن يتكون من 5 أرقام بالضبط.');
        return;
      }
      if (_receiptImage == null) {
        AppSnackBar.showError(context, 'يرجى إرفاق صورة إيصال الدفع / التحويل.');
        return;
      }
    }

    setState(() => _isSubmitting = true);

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
      receiptCode: _paymentMethod == SubscriptionPaymentMethod.receipt
          ? _receiptCodeController.text.trim()
          : null,
      receiptImage: _paymentMethod == SubscriptionPaymentMethod.receipt
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
        AppSnackBar.showSuccess(
          context,
          'تم إرسال طلب تسجيل واشتراك المندوب بنجاح! بانتظار اعتماد الدعم الفني.',
        );

        final goToApprovals = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 26),
                SizedBox(width: 10),
                Text('تم إرسال الطلب بنجاح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB8860B),
                  foregroundColor: Colors.white,
                ),
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
        title: const Text(
          'إضافة مندوب لمنظمة جديدة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
                      _buildSectionHeader('البيانات الشخصية للمندوب', Icons.badge_outlined),
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
                        'طريقة دفع الاشتراك (${SubscriptionCycleHelper.getRemainingMonthsInCycle()} أشهر - ${SubscriptionCycleHelper.getProratedSubscriptionFee().toInt()} ج.م)',
                        Icons.payments_outlined,
                      ),
                      const SizedBox(height: 8),
                      _buildPaymentCard(colorScheme),
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
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 22),
                          label: Text(
                            _isSubmitting
                                ? 'جاري رفع البيانات وإرسال الطلب...'
                                : 'إرسال طلب التسجيل',
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
    final cycleTitle = SubscriptionCycleHelper.getCycleTitleArabic();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.date_range_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'دورة الاشتراك النصف سنوية المطبقة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  cycleTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
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
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: colorScheme.surface,
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
                    decoration: const InputDecoration(
                      labelText: 'الاسم الأول *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _secondNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الأب *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _thirdNameController,
                    decoration: const InputDecoration(
                      labelText: 'اللقب / العائلة *',
                      border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (لتسجيل الدخول) *',
                hintText: '01xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_android_rounded),
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'الرقم القومي (14 رقم) *',
                prefixIcon: Icon(Icons.credit_card_rounded),
                border: OutlineInputBorder(),
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
            icon: const Icon(Icons.close_rounded, color: Colors.red, size: 20),
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
                    child: const Icon(
                      Icons.price_check_rounded,
                      color: Colors.white,
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
                                style: const TextStyle(
                                  color: Colors.white,
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

            RadioGroup<SubscriptionPaymentMethod>(
              groupValue: _paymentMethod,
              onChanged: (val) {
                if (val != null) setState(() => _paymentMethod = val);
              },
              child: Column(
                children: [
                  // Radio 1: Company Deduction
                  RadioListTile<SubscriptionPaymentMethod>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'خصم من حساب الشركة (${fee.toInt()} ج.م)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'يتم قيد قيمة الاشتراك المستحقة (${fee.toInt()} ج.م) على الفاتورة الدورية لشركتكم مباشرة.',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    value: SubscriptionPaymentMethod.companyDeduction,
                  ),
                  const Divider(),

                  // Radio 2: Bank Receipt / Transfer
                  RadioListTile<SubscriptionPaymentMethod>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'إيصال دفع / تحويل بنكي (${fee.toInt()} ج.م)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'تحويل مبلغ ${fee.toInt()} ج.م ورفع صورة إيصال الدفع وإدخال كود الإيصال الخماسي (5 أرقام).',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    value: SubscriptionPaymentMethod.receipt,
                  ),
                ],
              ),
            ),

            if (_paymentMethod == SubscriptionPaymentMethod.receipt) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _receiptCodeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'كود الإيصال / العملية (5 أرقام) *',
                        hintText: 'مثال: 54821',
                        prefixIcon: Icon(Icons.tag_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_paymentMethod == SubscriptionPaymentMethod.receipt) {
                          if (v == null || v.trim().isEmpty) return 'يرجى إدخال كود الإيصال';
                          if (v.trim().length != 5) return 'كود الإيصال يتكون من 5 أرقام';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildImagePickerTile(
                      title: 'صورة إيصال الدفع *',
                      subtitle: 'صورة واضحة لإيصال التحويل البنكي أو فوري',
                      icon: Icons.receipt_long_rounded,
                      file: _receiptImage,
                      onPick: () => _pickImage((f) => _receiptImage = f),
                      onRemove: () => setState(() => _receiptImage = null),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
