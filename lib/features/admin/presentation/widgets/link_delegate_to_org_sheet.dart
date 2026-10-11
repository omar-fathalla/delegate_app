import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';

class LinkDelegateToOrgSheet extends StatefulWidget {
  final Delegate delegate;
  final Delegate supervisor;

  const LinkDelegateToOrgSheet({
    super.key,
    required this.delegate,
    required this.supervisor,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Delegate delegate,
    required Delegate supervisor,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LinkDelegateToOrgSheet(
        delegate: delegate,
        supervisor: supervisor,
      ),
    );
  }

  @override
  State<LinkDelegateToOrgSheet> createState() => _LinkDelegateToOrgSheetState();
}

class _LinkDelegateToOrgSheetState extends State<LinkDelegateToOrgSheet> {
  static const String _instaPayLink = 'https://ipn.eg/S/fathall/instapay/1VphF7';

  final _formKey = GlobalKey<FormState>();
  final _receiptCodeController = TextEditingController();

  List<Map<String, dynamic>> _organizations = [];
  String? _selectedOrgUID;
  String? _selectedOrgName;
  bool _isLoadingOrgs = true;

  SubscriptionPaymentMethod _paymentMethod =
      SubscriptionPaymentMethod.companyDeduction;
  File? _receiptImage;
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
    _fetchAvailableOrganizations();
  }

  @override
  void dispose() {
    _receiptCodeController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableOrganizations() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('organizations').get();

      // Current delegate organizations to exclude
      final currentOrgUID = widget.delegate.organizationUID.trim().toLowerCase();
      final currentOrgName =
          widget.delegate.organizationName.trim().toLowerCase();
      final allKnownOrgNames = widget.delegate.allOrganizationNames
          .map((n) => n.trim().toLowerCase())
          .toSet();

      final orgs = snap.docs
          .map((doc) {
            final data = doc.data();
            return {
              'uid': doc.id,
              'name': (data['name'] ?? data['title'] ?? doc.id).toString(),
            };
          })
          .where((org) {
            final uid = (org['uid'] ?? '').toString().trim().toLowerCase();
            final name = (org['name'] ?? '').toString().trim().toLowerCase();

            // Exclude current organization or any organization the delegate already belongs to
            if (uid == currentOrgUID) return false;
            if (name == currentOrgName) return false;
            if (allKnownOrgNames.contains(name)) return false;

            return true;
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

  Future<void> _pickReceiptImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        _receiptImage = File(picked.path);
      });
    }
  }

  Future<void> _openInstaPayUrl() async {
    final uri = Uri.parse(_instaPayLink);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.showError(context, 'تعذر فتح تطبيق انستاباي تلقائياً.');
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
    if (!_formKey.currentState!.validate()) return;

    if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
      AppSnackBar.showError(
        context,
        'يرجى اختيار السلسلة / المنظمة المستهدفة.',
      );
      return;
    }

    if (_paymentMethod == SubscriptionPaymentMethod.branchReceipt) {
      final code = _receiptCodeController.text.trim();
      if (code.length != 5) {
        AppSnackBar.showError(
          context,
          'كود الإيصال الإلكتروني يجب أن يتكون من 5 أرقام بالضبط.',
        );
        return;
      }
      if (_isReceiptCodeValid == false) {
        AppSnackBar.showError(
          context,
          'كود الإيصال ($code) مستخدم مسبقاً، يرجى إدخال كود صالح.',
        );
        return;
      }
      if (_receiptImage == null) {
        AppSnackBar.showError(
          context,
          'يرجى إرفاق صورة الإيصال الإلكتروني من تسويق الفرع.',
        );
        return;
      }
    } else if (_paymentMethod == SubscriptionPaymentMethod.instaPay) {
      if (_receiptImage == null) {
        AppSnackBar.showError(
          context,
          'يرجى إرفاق صورة إشعار التحويل من تطبيق انستاباي.',
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    final remainingMonths = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee();

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.submitAddOrganizationRequest(
      supervisorUid: widget.supervisor.uid,
      supervisorName: widget.supervisor.fullName,
      supervisorPhone: widget.supervisor.phoneNumber,
      companyUID: widget.supervisor.companyUID.isNotEmpty
          ? widget.supervisor.companyUID
          : widget.delegate.companyUID,
      companyName: widget.supervisor.companyName.isNotEmpty
          ? widget.supervisor.companyName
          : widget.delegate.companyName,
      targetOrganizationUID: _selectedOrgUID!,
      targetOrganizationName: _selectedOrgName ?? _selectedOrgUID!,
      existingDelegate: widget.delegate,
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

    result.fold(
      (failure) => AppSnackBar.showError(context, failure.message),
      (_) {
        final isFree = _paymentMethod == SubscriptionPaymentMethod.freePromotion;
        AppSnackBar.showSuccess(
          context,
          isFree
              ? 'تم إرسال طلب ربط المندوب بسلسلة ($_selectedOrgName) بنجاح (مجاناً حتى 31/12)! بانتظار الاعتماد.'
              : 'تم إرسال طلب ربط المندوب بسلسلة ($_selectedOrgName) وسداد الاشتراك بنجاح! بانتظار الاعتماد.',
        );
        Navigator.pop(context, true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee();
    final remainingMonths = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final cycleCode = SubscriptionCycleHelper.getCycleCode();

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Title Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.add_business_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ربط المندوب بسلسلة إضافية',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'سداد الاشتراك والاعتماد للعمل في سلاسل تجارية متعددة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),

              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Delegate Info Summary Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              AppAvatar(
                                imageUrl: widget.delegate.personalPhotoUrl,
                                fallbackText: widget.delegate.fullName,
                                radius: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.delegate.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'الهاتف: ${widget.delegate.phoneNumber}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'السلسلة الحالية: ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            widget.delegate.organizationName,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 2. Select Target Organization
                        Text(
                          'السلسلة / المنظمة المستهدفة',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_isLoadingOrgs)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_organizations.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'لا توجد منظمات إضافية متاحة للربط حالياً (المندوب مشترك في جميع المنظمات المتاحة).',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _selectedOrgUID,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.storefront_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: _organizations.map((org) {
                              return DropdownMenuItem<String>(
                                value: org['uid'],
                                child: Text(
                                  org['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                final match = _organizations.firstWhere(
                                  (o) => o['uid'] == val,
                                );
                                setState(() {
                                  _selectedOrgUID = val;
                                  _selectedOrgName = match['name'];
                                });
                              }
                            },
                          ),
                        const SizedBox(height: 16),

                        if (SubscriptionCycleHelper.isFreePromotionActive()) ...[
                          _buildFreePromotionCard(colorScheme, theme.brightness == Brightness.dark),
                        ] else ...[
                          // 3. Subscription & Fee Banner
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFB8860B).withValues(alpha: 0.12),
                                  const Color(0xFFD4AF37).withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFB8860B)
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.workspace_premium_rounded,
                                      color: Color(0xFFB8860B),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'رسوم وفترة الاشتراك بالسلسلة الإضافية',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color:
                                            theme.brightness == Brightness.dark
                                                ? const Color(0xFFFFE082)
                                                : const Color(0xFF8D6200),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'دورة الاشتراك: $cycleCode ($remainingMonths أشهر)',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      '${fee.toInt()} ج.م',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFFB8860B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ينتهي الاشتراك بنهاية الدورة الحالية، ويتجدد دورياً لكل سلسلة مستقلة.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4. Payment Method Selection
                          Text(
                            'طريقة سداد الاشتراك',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          RadioGroup<SubscriptionPaymentMethod>(
                            groupValue: _paymentMethod,
                            onChanged: (val) {
                              if (val != null) setState(() => _paymentMethod = val);
                            },
                            child: Column(
                              children: [
                                RadioListTile<SubscriptionPaymentMethod>(
                                  value: SubscriptionPaymentMethod.companyDeduction,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    SubscriptionPaymentMethod
                                        .companyDeduction.displayName,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'خصم مباشر من رصيد الشركة المسجل في النظام',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                RadioListTile<SubscriptionPaymentMethod>(
                                  value: SubscriptionPaymentMethod.instaPay,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    SubscriptionPaymentMethod.instaPay.displayName,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'تحويل إلكتروني مباشر عبر تطبيق انستاباي',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                RadioListTile<SubscriptionPaymentMethod>(
                                  value: SubscriptionPaymentMethod.branchReceipt,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    SubscriptionPaymentMethod
                                        .branchReceipt.displayName,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'سداد نقدي بتسويق الفرع وإدخال كود الإيصال الخماسي',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Conditional: InstaPay details
                          if (_paymentMethod ==
                              SubscriptionPaymentMethod.instaPay) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.launch_rounded, size: 16),
                                    label: const Text('فتح انستاباي', style: TextStyle(fontSize: 12)),
                                    onPressed: _openInstaPayUrl,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.copy_rounded, size: 16),
                                    label: const Text('نسخ الحساب', style: TextStyle(fontSize: 12)),
                                    onPressed: _copyInstaPayLink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(42),
                              ),
                              icon: Icon(
                                _receiptImage != null
                                    ? Icons.check_circle_rounded
                                    : Icons.upload_file_rounded,
                                size: 18,
                                color: _receiptImage != null
                                    ? Colors.green
                                    : null,
                              ),
                              label: Text(
                                _receiptImage != null
                                    ? 'تم إرفاق إيصال التحويل ✓'
                                    : 'إرفاق إشعار تحويل انستاباي *',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              onPressed: _pickReceiptImage,
                            ),
                          ],

                          // Conditional: Branch receipt code
                          if (_paymentMethod ==
                              SubscriptionPaymentMethod.branchReceipt) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _receiptCodeController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              decoration: InputDecoration(
                                labelText: 'كود الإيصال الخماسي *',
                                hintText: '5 أرقام (مثال: 48921)',
                                prefixIcon: const Icon(Icons.pin_rounded, size: 20),
                                suffixIcon: _isCheckingReceiptCode
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : _isReceiptCodeValid == true
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            color: Colors.green,
                                          )
                                        : _isReceiptCodeValid == false
                                            ? const Icon(
                                                Icons.cancel_rounded,
                                                color: Colors.red,
                                              )
                                            : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: _checkReceiptCode,
                            ),
                            if (_receiptCodeStatusText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _receiptCodeStatusText!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isReceiptCodeValid == true
                                      ? Colors.green
                                      : _isReceiptCodeValid == false
                                          ? colorScheme.error
                                          : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(42),
                              ),
                              icon: Icon(
                                _receiptImage != null
                                    ? Icons.check_circle_rounded
                                    : Icons.receipt_long_rounded,
                                size: 18,
                                color: _receiptImage != null
                                    ? Colors.green
                                    : null,
                              ),
                              label: Text(
                                _receiptImage != null
                                    ? 'تم إرفاق صورة الإيصال ✓'
                                    : 'إرفاق صورة الإيصال الإلكتروني *',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              onPressed: _pickReceiptImage,
                            ),
                          ],
                        ],

                        const SizedBox(height: 24),

                        // Submit Button
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: (_isSubmitting || _organizations.isEmpty)
                              ? null
                              : _submit,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(
                            _isSubmitting
                                ? 'جاري إرسال الطلب...'
                                : (SubscriptionCycleHelper.isFreePromotionActive()
                                    ? 'تأكيد ربط المندوب بالسلسلة (مجاناً)'
                                    : 'إرسال طلب الربط وسداد الاشتراك'),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreePromotionCard(ColorScheme colorScheme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerLow
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFF16A34A).withValues(alpha: 0.4)
              : const Color(0xFF86EFAC),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF166534).withValues(alpha: 0.4)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF16A34A) : const Color(0xFF86EFAC),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      size: 14,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'عرض خاص حتى 31 ديسمبر 2026',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'مجاناً 0 ج.م',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF166534).withValues(alpha: 0.4)
                      : const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: Color(0xFF16A34A),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ربط المندوب بالسلسلة الإضافية مجاناً بالكامل',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? colorScheme.onSurface : const Color(0xFF14532D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainer
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? colorScheme.outlineVariant
                    : const Color(0xFFBBF7D0),
              ),
            ),
            child: Text(
              'يمكنك الآن ربط المندوب بالسلاسل والمنظمات الأخرى ومتابعة حضوره وانصرافه ورفع التصوير مجاناً بالكامل حتى 31/12 بدون أي رسوم اشتراك.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: isDark ? colorScheme.onSurface : const Color(0xFF1F2937),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildSheetBenefit(
            icon: Icons.check_circle_rounded,
            text: 'متابعة حضور وانصراف المندوب في فروع السلسلة الجديدة لحظياً.',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 6),
          _buildSheetBenefit(
            icon: Icons.check_circle_rounded,
            text: 'إدارة أذونات ورفع تقارير التصوير الميداني للفرع المستهدف.',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 6),
          _buildSheetBenefit(
            icon: Icons.check_circle_rounded,
            text: 'ربط فوري بدون أي رسوم مالية أو إيصالات دفع حتى نهاية 2026.',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildSheetBenefit({
    required IconData icon,
    required String text,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? colorScheme.onSurfaceVariant : const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}
