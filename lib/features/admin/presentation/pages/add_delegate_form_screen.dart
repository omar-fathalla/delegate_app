import 'dart:io';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/features/admin/data/chain_duplicate_lookup.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/presentation/widgets/chain_multi_select.dart';
import 'package:delegate_app/features/admin/presentation/widgets/add_delegate_subscription_section.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/utils/promo_clock_binding.dart';
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

class _AddDelegateFormScreenState extends State<AddDelegateFormScreen> with WidgetsBindingObserver, PromoClockBinding {

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
  final Set<String> _selectedOrgUIDs = {};
  Set<String> _duplicateOrgUIDs = {};
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
  bool _submitSucceeded = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _syncPaymentMethod();
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
      final role = widget.supervisor.role;
      final isGlobal = role == UserRole.superAdmin;
      if (companyUID.isEmpty && !isGlobal) {
        // Company staff and org-admin fail closed without a companyUID.
      } else if (companyUID.isEmpty && isGlobal) {
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
      if (role == UserRole.organizationAdmin) {
        final ownOrg = widget.supervisor.organizationUID.trim();
        orgs.removeWhere((o) => (o['uid'] as String).trim() != ownOrg);
      }

      if (mounted) {
        setState(() {
          _organizations = orgs;
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


  void _resetFormAfterSuccessfulSubmit() {
    _formKey.currentState?.reset();
    _firstNameController.clear();
    _secondNameController.clear();
    _thirdNameController.clear();
    _phoneController.clear();
    _nationalIdController.clear();
    _receiptCodeController.clear();
    _selectedOrgUIDs.clear();
    _duplicateOrgUIDs = {};
    _profileImage = null;
    _nationalIdFront = null;
    _nationalIdBack = null;
    _receiptImage = null;
    _isReceiptCodeValid = null;
    _syncPaymentMethod();
  }


  String? get _companyUID => widget.supervisor.companyUID;

  bool get _isFreePromotion =>
      SubscriptionCycleHelper.isFreePromotionActive(null, _companyUID);

  void _syncPaymentMethod() {
    _paymentMethod = _isFreePromotion
        ? SubscriptionPaymentMethod.freePromotion
        : SubscriptionPaymentMethod.paymob;
  }

  @override
  void onPromoClockTick() {
    if (!mounted) return;
    setState(_syncPaymentMethod);
  }

  Future<void> _submit() async {
    if (_isSubmitting || _submitSucceeded) return;
    if (!_formKey.currentState!.validate()) {
      AppSnackBar.showError(context, 'يرجى استكمال البيانات المطلوبة وتصحيح الأخطاء.');
      return;
    }

    final l10n = AppLocalizations.of(context);
    final chainOptions = _organizations
        .map((o) => ChainOption(uid: o['uid'] as String, name: o['name'] as String))
        .toList();
    if (_selectedOrgUIDs.isEmpty) {
      AppSnackBar.showError(context, l10n?.chainPickerRequired ?? 'يرجى اختيار سلسلة واحدة على الأقل.');
      return;
    }

    late final DuplicateChainLookup lookup;
    try {
      lookup = await lookupDuplicateChains(
        firestore: FirebaseFirestore.instance,
        companyUID: widget.supervisor.companyUID,
        nationalId: _nationalIdController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        organizationUIDs: _selectedOrgUIDs,
      );
    } on DuplicateChainLookupException catch (e) {
      AppSnackBar.showError(context, e.message);
      return;
    }
    if (!mounted) return;
    final duplicates = lookup.duplicateOrgUids;
    final selection = partitionSelectedChains(
      all: chainOptions,
      selectedUids: _selectedOrgUIDs,
      duplicateUids: duplicates,
    );
    if (mounted) {
      setState(() => _duplicateOrgUIDs = duplicates);
    }
    if (selection.warningAr != null && mounted) {
      if (!selection.canSubmit) {
        AppSnackBar.showError(context, selection.warningAr!);
        return;
      }
      AppSnackBar.showInfo(context, selection.warningAr!);
    }
    if (!selection.canSubmit) {
      AppSnackBar.showError(context, l10n?.chainPickerRequired ?? 'يرجى اختيار سلسلة واحدة على الأقل.');
      return;
    }
    final selectedOrgUID = selection.primaryUid!;
    final selectedOrgName = selection.primaryName!;

    // Partial duplicate: attach remaining chains to the existing uid, no new fee.
    if (selection.skippedUids.isNotEmpty &&
        lookup.existingDelegateUid != null &&
        lookup.existingDelegateUid!.trim().isNotEmpty &&
        selection.keptUids.isNotEmpty) {
      setState(() => _isSubmitting = true);
      final repo = sl<DelegateSubscriptionRepository>();
      final existing = await repo.loadCompanyDelegate(
        companyUID: widget.supervisor.companyUID,
        organizationUID: lookup.existingDelegateOrganizationUID ?? selection.skippedUids.first,
        uid: lookup.existingDelegateUid!,
      );
      if (!mounted) return;
      final loaded = existing.fold<Delegate?>(
        (f) {
          setState(() => _isSubmitting = false);
          AppSnackBar.showError(context, f.message);
          return null;
        },
        (d) => d,
      );
      if (loaded == null) return;
      final result = await repo.submitAddOrganizationRequest(
        supervisorUid: widget.supervisor.uid,
        supervisorName: widget.supervisor.fullName,
        supervisorPhone: widget.supervisor.phoneNumber,
        companyUID: widget.supervisor.companyUID,
        companyName: widget.supervisor.companyName,
        targetOrganizationUID: selectedOrgUID,
        targetOrganizationName: selectedOrgName,
        organizationUIDs: selection.keptUids,
        organizationNames: selection.keptNames,
        existingDelegate: loaded,
        paymentMethod: SubscriptionPaymentMethod.notRequired,
      );
      if (!mounted) return;
      await result.fold(
        (failure) async {
          setState(() => _isSubmitting = false);
          AppSnackBar.showError(context, failure.message);
        },
        (requestId) async {
          setState(() {
            _submitSucceeded = true;
            _resetFormAfterSuccessfulSubmit();
          });
          AppSnackBar.showSuccess(
            context,
            'تم إرسال طلب ربط المندوب الحالي بالسلاسل المتبقية بدون رسوم إضافية. بانتظار اعتماد الإدارة.',
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
              content: const Text('سيتم ربط المندوب الحالي بالسلاسل المتبقية بدون إنشاء هوية أو رسم جديد.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (goToApprovals == true) {
            // left for consistency with the new-delegate path; default is just close.
          }
          if (mounted) Navigator.of(context).pop();
        },
      );
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

    _syncPaymentMethod();
    final remainingMonths = SubscriptionCycleHelper.getRemainingMonthsInCycle();
    final fee = SubscriptionCycleHelper.getProratedSubscriptionFee(null, _companyUID);

    final repo = sl<DelegateSubscriptionRepository>();
    final result = await repo.submitSubscriptionRequest(
      supervisorUid: widget.supervisor.uid,
      supervisorName: widget.supervisor.fullName,
      supervisorPhone: widget.supervisor.phoneNumber,
      companyUID: widget.supervisor.companyUID,
      companyName: widget.supervisor.companyName,
      organizationUID: selectedOrgUID,
      organizationName: selectedOrgName,
      organizationUIDs: selection.keptUids,
      organizationNames: selection.keptNames,
      skippedDuplicateOrgUIDs: selection.skippedUids,
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

    await result.fold(
      (failure) async {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(context, failure.message);
      },
      (requestId) async {
        final isFree = _paymentMethod == SubscriptionPaymentMethod.freePromotion;
        setState(() {
          _submitSucceeded = true;
          _resetFormAfterSuccessfulSubmit();
        });
        String? checkoutError;
        if (!isFree) {
          // Paymob checkout: the server creates the order and computes the amount.
          final checkout = await sl<SubscriptionPaymentGateway>().startCheckout(requestId: requestId);
          if (!mounted) return;
          checkout.fold(
            (f) => checkoutError = f.message,
            (c) { launchUrl(c.checkoutUrl, mode: LaunchMode.externalApplication); },
          );
          if (!mounted) return;
        }

        if (checkoutError != null) {
          AppSnackBar.showError(context, checkoutError!);
          final goToApprovals = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Icon(Icons.error_rounded, color: Theme.of(ctx).colorScheme.error, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'تعذر بدء الدفع الإلكتروني',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: Text(
                '$checkoutError\n\nتم حفظ طلب التسجيل، لكن لم يبدأ الدفع. يمكنك إعادة المحاولة من شاشة الاعتمادات.',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
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
          return;
        }

        AppSnackBar.showSuccess(
          context,
          isFree
              ? 'تم إرسال طلب تسجيل المندوب بنجاح (مجاناً ضمن العرض الترويجي)! بانتظار اعتماد الإدارة.'
              : 'تم إرسال طلب التسجيل بانتظار الدفع الإلكتروني، ثم اعتماد الدعم الفني.',
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildFormScaffold(theme, colorScheme),
    );
  }

  Widget _buildFormScaffold(ThemeData theme, ColorScheme colorScheme) {
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
                        _isFreePromotion
                            ? 'الاشتراك والربط (مجاناً حتى 31/12)'
                            : 'الاشتراك والدفع الإلكتروني (${SubscriptionCycleHelper.getRemainingMonthsInCycle()} أشهر - ${SubscriptionCycleHelper.formatEgp(SubscriptionCycleHelper.getProratedSubscriptionFee(null, _companyUID))} ج.م)',
                        _isFreePromotion
                            ? Icons.card_giftcard_rounded
                            : Symbols.payments_rounded,
                      ),
                      const SizedBox(height: 8),
                      _isFreePromotion
                          ? _buildFreePromotionCard(colorScheme)
                          : _buildPaymobCard(colorScheme),
                      const SizedBox(height: 24),

                      // 6. Submit Button
                      AddDelegateSubmitButton(
                        isFree: _isFreePromotion,
                        isBusy: _isSubmitting || _submitSucceeded,
                        onSubmit: _submit,
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
    return AddDelegateCycleBanner(isFree: _isFreePromotion, colorScheme: colorScheme);
  }


  Widget _buildOrganizationSelector(ColorScheme colorScheme) {
    final chains = _organizations
        .map((o) => ChainOption(uid: o['uid'] as String, name: o['name'] as String))
        .toList();
    return ChainMultiSelect(
      chains: chains,
      selectedUids: _selectedOrgUIDs,
      duplicateUids: _duplicateOrgUIDs,
      onChanged: (next) => setState(() {
        _selectedOrgUIDs
          ..clear()
          ..addAll(next);
        _duplicateOrgUIDs = {};
      }),
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
                prefixIcon: Icon(Symbols.credit_card_rounded, size: 20, color: colorScheme.primary),
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

  /// كارت الدفع الإلكتروني عبر Paymob بعد انتهاء العرض الترويجي.
  Widget _buildPaymobCard(ColorScheme colorScheme) {
    return AddDelegatePaymobCard(companyUID: _companyUID, colorScheme: colorScheme);
  }


  Widget _buildFreePromotionCard(ColorScheme colorScheme) {
    return AddDelegateFreePromotionCard(colorScheme: colorScheme);
  }



}
