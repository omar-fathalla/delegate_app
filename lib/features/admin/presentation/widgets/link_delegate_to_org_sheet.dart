import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/presentation/widgets/chain_multi_select.dart';
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
      builder: (_) =>
          LinkDelegateToOrgSheet(delegate: delegate, supervisor: supervisor),
    );
  }

  @override
  State<LinkDelegateToOrgSheet> createState() => _LinkDelegateToOrgSheetState();
}

class _LinkDelegateToOrgSheetState extends State<LinkDelegateToOrgSheet> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _organizations = [];
  final Set<String> _selectedOrgUIDs = {};
  bool _isLoadingOrgs = true;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchAvailableOrganizations();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchAvailableOrganizations() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('organizations')
          .get();

      final currentOrgUID = widget.delegate.organizationUID
          .trim()
          .toLowerCase();
      final currentOrgName = widget.delegate.organizationName
          .trim()
          .toLowerCase();
      final allKnownOrgNames = widget.delegate.allOrganizationNames
          .map((n) => n.trim().toLowerCase())
          .toSet();
      final alreadyUids = {currentOrgUID}..removeWhere((id) => id.isEmpty);

      final companyUID =
          (widget.supervisor.companyUID.isNotEmpty
                  ? widget.supervisor.companyUID
                  : widget.delegate.companyUID)
              .trim();
      final role = widget.supervisor.role;
      final isGlobal = role == UserRole.superAdmin;
      if (companyUID.isEmpty && !isGlobal) {
        if (mounted) {
          setState(() {
            _organizations = [];
            _selectedOrgUIDs.clear();
            _isLoadingOrgs = false;
          });
        }
        return;
      }

      final List<Map<String, dynamic>> orgs = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final name = (data['name'] ?? data['title'] ?? doc.id).toString();
        final uidKey = uid.trim().toLowerCase();
        final nameKey = name.trim().toLowerCase();
        final isFathalla = nameKey.contains('fathalla') ||
            nameKey.contains('فتح الله') ||
            nameKey.contains('فتح_الله') ||
            uidKey.contains('fathalla') ||
            uidKey.contains('فتح_الله');
        if (isFathalla) continue;
        if (alreadyUids.contains(uidKey)) continue;
        if (nameKey == currentOrgName) continue;
        if (allKnownOrgNames.contains(nameKey)) continue;
        if (companyUID.isNotEmpty) {
          try {
            final cDoc = await FirebaseFirestore.instance
                .collection('organizations')
                .doc(uid)
                .collection('companies')
                .doc(companyUID)
                .get();
            if (!cDoc.exists) continue;
          } catch (_) {
            continue;
          }
        }
        orgs.add({'uid': uid, 'name': name});
      }
      if (role == UserRole.organizationAdmin) {
        final ownOrg = widget.supervisor.organizationUID.trim();
        orgs.removeWhere((o) => (o['uid'] as String).trim() != ownOrg);
      }

      if (mounted) {
        setState(() {
          _organizations = orgs;
          _selectedOrgUIDs.clear();
          _isLoadingOrgs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingOrgs = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedOrgUIDs.isEmpty) {
      AppSnackBar.showError(context, 'يرجى اختيار سلسلة واحدة على الأقل.');
      return;
    }

    final selected = [
      for (final org in _organizations)
        if (_selectedOrgUIDs.contains(org['uid'])) org,
    ];
    if (selected.isEmpty) {
      AppSnackBar.showError(context, 'يرجى اختيار سلسلة واحدة على الأقل.');
      return;
    }
    final primary = selected.first;
    final extraUids = [
      for (final org in selected.skip(1)) org['uid'] as String,
    ];
    final extraNames = [
      for (final org in selected.skip(1)) org['name'] as String,
    ];
    final selectedNames = [for (final org in selected) org['name'] as String];

    setState(() => _isSubmitting = true);

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
      targetOrganizationUID: primary['uid'] as String,
      targetOrganizationName: primary['name'] as String,
      organizationUIDs: extraUids,
      organizationNames: extraNames,
      existingDelegate: widget.delegate,
      // One subscription per delegate covers all chains: no fee here.
      paymentMethod: SubscriptionPaymentMethod.notRequired,
      fee: 0,
      remainingMonths: 0,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold((failure) => AppSnackBar.showError(context, failure.message), (
      _,
    ) {
      AppSnackBar.showSuccess(
        context,
        'تم إرسال طلب ربط المندوب بـ ${selectedNames.length} سلسلة (${selectedNames.join('، ')}) بنجاح (بدون رسوم إضافية)! بانتظار الاعتماد.',
      );
      Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                            'يمكن اختيار أكثر من سلسلة داخل نفس الشركة، بدون رسوم إضافية.',
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
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
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
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
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
                              color: colorScheme.errorContainer.withValues(
                                alpha: 0.3,
                              ),
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
                          ChainMultiSelect(
                            chains: [
                              for (final org in _organizations)
                                ChainOption(
                                  uid: org['uid'] as String,
                                  name: org['name'] as String,
                                ),
                            ],
                            selectedUids: _selectedOrgUIDs,
                            onChanged: (next) => setState(() {
                              _selectedOrgUIDs
                                ..clear()
                                ..addAll(next);
                            }),
                          ),
                        const SizedBox(height: 16),

                        _buildNoExtraFeeCard(colorScheme),

                        const SizedBox(height: 24),

                        // Submit Button
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed:
                              (_isSubmitting ||
                                  _organizations.isEmpty ||
                                  _selectedOrgUIDs.isEmpty)
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
                                : 'تأكيد ربط المندوب بالسلاسل (بدون رسوم)',
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

  Widget _buildNoExtraFeeCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_rounded, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'بدون رسوم إضافية: اشتراك المندوب الواحد يغطي كل السلاسل. '
              'يتجدد الاشتراك مرة واحدة كل دورة (يناير–يونيو / يوليو–ديسمبر) من صفحة «تجديد المناديب».',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
