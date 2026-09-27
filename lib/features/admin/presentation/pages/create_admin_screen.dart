import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/create_admin_bloc.dart';

class CreateAdminScreen extends StatelessWidget {
  final String organizationUID;
  final Delegate? currentDelegate;
  final UserRole? currentUserRole;
  final bool showAppBar;
  final VoidCallback? onBack;

  const CreateAdminScreen({
    super.key,
    required this.organizationUID,
    this.currentDelegate,
    this.currentUserRole,
    this.showAppBar = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<CreateAdminBloc>()..add(LoadOrganizationsRequested()),
      child: _CreateAdminView(
        organizationUID: organizationUID,
        currentDelegate: currentDelegate,
        currentUserRole: currentUserRole,
        showAppBar: showAppBar,
        onBack: onBack,
      ),
    );
  }
}

class _CreateAdminView extends StatefulWidget {
  final String organizationUID;
  final Delegate? currentDelegate;
  final UserRole? currentUserRole;
  final bool showAppBar;
  final VoidCallback? onBack;

  const _CreateAdminView({
    required this.organizationUID,
    this.currentDelegate,
    this.currentUserRole,
    this.showAppBar = true,
    this.onBack,
  });

  @override
  State<_CreateAdminView> createState() => _CreateAdminViewState();
}

class _CreateAdminViewState extends State<_CreateAdminView> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  String _selectedRole = 'organization-admin';
  String? _selectedOrgUID;
  String? _selectedCompanyUID;
  String? _selectedCompanyName;
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _companies = [];
  bool _isLoadingCompanies = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole != 'super-admin' &&
        (_selectedOrgUID == null || _selectedOrgUID!.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار المنظمة')));
      return;
    }

    if (_selectedRole == 'hr') {
      if (_selectedCompanyUID == null || _selectedCompanyUID!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار الشركة التابع لها مسؤول الموارد البشرية')),
        );
        return;
      }
    }

    context.read<CreateAdminBloc>().add(
      CreateAdminSubmitted(
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        displayName: _nameController.text.trim(),
        role: _selectedRole,
        organizationUID: _selectedOrgUID ?? '',
        companyUID: _selectedCompanyUID,
        companyName: _selectedCompanyName,
        jobTitle: _jobTitleController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<CreateAdminBloc, CreateAdminState>(
      listener: (context, state) {
        if (state is CreateAdminOrgsLoaded) {
          setState(() {
            _organizations = state.organizations;
            if (_organizations.isNotEmpty) {
              if (widget.organizationUID.isNotEmpty &&
                  _organizations.any((org) => org['uid'] == widget.organizationUID)) {
                _selectedOrgUID = widget.organizationUID;
              } else {
                final fathallaOrg = _organizations.firstWhere(
                  (org) {
                    final name = (org['name'] as String? ?? '').toLowerCase();
                    return name.contains('fathalla') || name.contains('فتح الله');
                  },
                  orElse: () => _organizations.first,
                );
                _selectedOrgUID = fathallaOrg['uid'] as String;
              }

              if (_selectedRole == 'hr' && _selectedOrgUID != null) {
                context.read<CreateAdminBloc>().add(
                  LoadCompaniesForOrgRequested(organizationUID: _selectedOrgUID!),
                );
              }
            }
          });
        }
        if (state is CreateAdminCompaniesLoading) {
          setState(() {
            _isLoadingCompanies = true;
          });
        }
        if (state is CreateAdminCompaniesLoaded) {
          setState(() {
            _isLoadingCompanies = false;
            _companies = state.companies;
          });
        }
        if (state is CreateAdminSuccess) {
          _phoneController.clear();
          _emailController.clear();
          _nameController.clear();
          _jobTitleController.clear();
          _selectedCompanyUID = null;
          _selectedCompanyName = null;
          setState(() {
            if (_organizations.isNotEmpty) {
              final fathallaOrg = _organizations.firstWhere(
                (org) {
                  final name = (org['name'] as String? ?? '').toLowerCase();
                  return name.contains('fathalla') || name.contains('فتح الله');
                },
                orElse: () => _organizations.first,
              );
              _selectedOrgUID = fathallaOrg['uid'] as String;
            } else {
              _selectedOrgUID = null;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.adminCreatedSuccessfully,
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
              backgroundColor: colorScheme.primaryContainer,
            ),
          );
        } else if (state is CreateAdminError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is CreateAdminLoading;

        void handleBack() {
          if (widget.onBack != null) {
            widget.onBack!();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else if (widget.currentDelegate != null) {
            context.go('/admin/home', extra: widget.currentDelegate);
          }
        }

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          appBar: widget.showAppBar
              ? AppBar(
                  backgroundColor: colorScheme.surfaceContainer,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 2.0,
                  shape: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  leading: BackButton(
                    onPressed: handleBack,
                  ),
                  title: Text(
                    l10n.createAdmin,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  centerTitle: true,
                )
              : null,
          body: SafeArea(
            top: !widget.showAppBar,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.showAppBar && widget.onBack != null) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IconButton.filledTonal(
                          icon: const BackButtonIcon(),
                          onPressed: widget.onBack,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Header icon
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 36,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (!widget.showAppBar) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          l10n.createAdmin,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Display Name
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.adminName,
                        prefixIcon: Icon(
                          Icons.person_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? l10n.pleaseEnterAdminName
                          : null,
                    ),
                    const SizedBox(height: 20),

                    // Phone Number
                    TextFormField(
                      controller: _phoneController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.adminPhone,
                        prefixIcon: Icon(
                          Icons.phone_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.pleaseEnterAdminPhone;
                        }
                        if (v.trim().length < 10) {
                          return l10n.invalidPhoneNumber;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: l10n.adminEmail,
                        prefixIcon: Icon(
                          Icons.email_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.pleaseEnterAdminEmail;
                        }
                        if (!RegExp(
                          r'^[^@]+@[^@]+\.[^@]+',
                        ).hasMatch(v.trim())) {
                          return l10n.invalidEmail;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Organization Dropdown
                    Text(
                      'المنظمة',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _organizations.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: _selectedOrgUID,
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.corporate_fare_rounded,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              hint: const Text('اختر المنظمة'),
                              items: _organizations.map((org) {
                                return DropdownMenuItem<String>(
                                  value: org['uid'] as String,
                                  child: Text(
                                    org['name'] as String? ??
                                        org['uid'] as String,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedOrgUID = val;
                                  _selectedCompanyUID = null;
                                  _selectedCompanyName = null;
                                  _companies = [];
                                });
                                if (val != null && _selectedRole == 'hr') {
                                  context.read<CreateAdminBloc>().add(
                                    LoadCompaniesForOrgRequested(organizationUID: val),
                                  );
                                }
                              },
                            ),
                    ),
                    const SizedBox(height: 20),

                    // Role Selector
                    Text(
                      'نوع المستخدم',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _RoleTile(
                            title: 'تسويق الفروع',
                            subtitle: 'Branch Marketing',
                            icon: Icons.campaign_rounded,
                            value: 'marketing',
                            isSelected: _selectedRole == 'marketing',
                            onTap: () {
                              setState(() => _selectedRole = 'marketing');
                            },
                          ),
                          Divider(
                            height: 1,
                            color: colorScheme.outline.withValues(alpha: 0.3),
                          ),
                          _RoleTile(
                            title: 'مدير تسويق الفروع',
                            subtitle: 'Branches Marketing Manager',
                            icon: Icons.storefront_rounded,
                            value: 'branches_marketing',
                            isSelected: _selectedRole == 'branches_marketing',
                            onTap: () {
                              setState(() => _selectedRole = 'branches_marketing');
                            },
                          ),
                          Divider(
                            height: 1,
                            color: colorScheme.outline.withValues(alpha: 0.3),
                          ),
                          _RoleTile(
                            title: 'تسويق العروض',
                            subtitle: 'Marketing Promotion',
                            icon: Icons.photo_library_rounded,
                            value: 'marketing_promotion',
                            isSelected: _selectedRole == 'marketing_promotion',
                            onTap: () {
                              setState(() => _selectedRole = 'marketing_promotion');
                            },
                          ),
                          Divider(
                            height: 1,
                            color: colorScheme.outline.withValues(alpha: 0.3),
                          ),

                          _RoleTile(
                            title: 'مدير عام',
                            subtitle: 'Organization Admin',
                            icon: Icons.corporate_fare_rounded,
                            value: 'organization-admin',
                            isSelected: _selectedRole == 'organization-admin',
                            onTap: () {
                              setState(
                                () => _selectedRole = 'organization-admin',
                              );
                            },
                          ),
                          if ((widget.currentDelegate?.role ?? widget.currentUserRole) != UserRole.technicalSupport) ...[
                            Divider(
                              height: 1,
                              color: colorScheme.outline.withValues(alpha: 0.3),
                            ),
                            _RoleTile(
                              title: 'مدير النظام الفائق',
                              subtitle: 'Super Admin - كامل الصلاحيات',
                              icon: Icons.verified_user_rounded,
                              value: 'super-admin',
                              isSelected: _selectedRole == 'super-admin',
                              onTap: () {
                                setState(() => _selectedRole = 'super-admin');
                              },
                            ),
                            Divider(
                              height: 1,
                              color: colorScheme.outline.withValues(alpha: 0.3),
                            ),
                            _RoleTile(
                              title: 'دعم فني',
                              subtitle: 'Technical Support',
                              icon: Icons.support_agent_rounded,
                              value: 'technical_support',
                              isSelected: _selectedRole == 'technical_support',
                              onTap: () {
                                setState(() => _selectedRole = 'technical_support');
                              },
                            ),
                            Divider(
                              height: 1,
                              color: colorScheme.outline.withValues(alpha: 0.3),
                            ),
                            _RoleTile(
                              title: 'محاسب / إدارة الحسابات',
                              subtitle: 'Accountant - الرقابة والتقارير المالية',
                              icon: Icons.account_balance_wallet_rounded,
                              value: 'accountant',
                              isSelected: _selectedRole == 'accountant',
                              onTap: () {
                                setState(() => _selectedRole = 'accountant');
                              },
                            ),
                            Divider(
                              height: 1,
                              color: colorScheme.outline.withValues(alpha: 0.3),
                            ),
                            _RoleTile(
                              title: 'مسؤول موارد بشرية (HR)',
                              subtitle: 'HR Admin - إدارة الحضور والصور ومناديب الشركة',
                              icon: Icons.badge_rounded,
                              value: 'hr',
                              isSelected: _selectedRole == 'hr',
                              onTap: () {
                                setState(() {
                                  _selectedRole = 'hr';
                                  if (_selectedOrgUID != null && _companies.isEmpty) {
                                    context.read<CreateAdminBloc>().add(
                                      LoadCompaniesForOrgRequested(organizationUID: _selectedOrgUID!),
                                    );
                                  }
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_selectedRole == 'hr') ...[
                      const SizedBox(height: 24),
                      _buildHRCompanySection(context, colorScheme),
                    ],
                    const SizedBox(height: 40),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: isLoading ? null : _submitForm,
                        icon: const Icon(Icons.person_add_rounded),
                        label: isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: colorScheme.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                l10n.createAdmin,
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
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
      },
    );
  }

  Widget _buildHRCompanySection(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.business_rounded,
                  size: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'بيانات شركة الـ HR التابع لها',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Company Selection Field
          Text(
            'الشركة *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingCompanies)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('جاري تحميل الشركات...'),
                ],
              ),
            )
          else
            InkWell(
              onTap: () {
                if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى اختيار المنظمة أولاً لعرض شركاتها')),
                  );
                  return;
                }
                if (_companies.isEmpty) {
                  context.read<CreateAdminBloc>().add(
                    LoadCompaniesForOrgRequested(organizationUID: _selectedOrgUID!),
                  );
                }
                _openCompanySearchModal(context, colorScheme);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedCompanyUID != null
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.35),
                    width: _selectedCompanyUID != null ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedCompanyUID != null
                          ? Icons.business_center_rounded
                          : Icons.search_rounded,
                      color: _selectedCompanyUID != null
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCompanyName ?? 'انقر للبحث واختيار الشركة...',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _selectedCompanyUID != null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _selectedCompanyUID != null
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_selectedCompanyUID != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'انقر لتغيير الشركة',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Job Title field
          TextFormField(
            controller: _jobTitleController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'المسمى الوظيفي (مثال: مدير الموارد البشرية / أخصائي HR)',
              prefixIcon: Icon(
                Icons.badge_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCompanySearchModal(BuildContext context, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = _companies.where((comp) {
              final name = (comp['name'] as String? ?? '').toLowerCase();
              final code = comp['code']?.toString().toLowerCase() ?? '';
              final codeOrg = comp['companyCodeInOrg']?.toString().toLowerCase() ?? '';
              final q = searchQuery.toLowerCase();
              return name.contains(q) || code.contains(q) || codeOrg.contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (scrollCtx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.business_rounded, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'اختر الشركة التابع لها الـ HR',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم الشركة أو الكود...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  searchQuery.isEmpty
                                      ? 'لا توجد شركات مسجلة في هذه المنظمة'
                                      : 'لم يتم العثور على شركات تطابق "$searchQuery"',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: filtered.length,
                                separatorBuilder: (_, index) => Divider(
                                  height: 1,
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                                ),
                                itemBuilder: (itemCtx, index) {
                                  final comp = filtered[index];
                                  final name = comp['name'] as String? ?? 'شركة بدون اسم';
                                  final code = comp['code'] ?? comp['companyCodeInOrg'] ?? '';
                                  final isSelected = comp['uid'] == _selectedCompanyUID;

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.business_center_rounded,
                                        color: isSelected
                                            ? colorScheme.onPrimary
                                            : colorScheme.onPrimaryContainer,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: code.toString().isNotEmpty
                                        ? Text('كود: $code')
                                        : null,
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_circle_rounded,
                                            color: colorScheme.primary,
                                          )
                                        : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedCompanyUID = comp['uid'] as String?;
                                        _selectedCompanyName = name;
                                      });
                                      Navigator.pop(modalCtx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                  width: isSelected ? 8 : 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
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
