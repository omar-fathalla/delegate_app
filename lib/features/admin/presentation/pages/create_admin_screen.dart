import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../bloc/create_admin_bloc.dart';

class CreateAdminScreen extends StatelessWidget {
  final String organizationUID;

  const CreateAdminScreen({super.key, required this.organizationUID});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<CreateAdminBloc>()..add(LoadOrganizationsRequested()),
      child: _CreateAdminView(organizationUID: organizationUID),
    );
  }
}

class _CreateAdminView extends StatefulWidget {
  final String organizationUID;

  const _CreateAdminView({required this.organizationUID});

  @override
  State<_CreateAdminView> createState() => _CreateAdminViewState();
}

class _CreateAdminViewState extends State<_CreateAdminView> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'company-admin';
  String? _selectedOrgUID;
  List<Map<String, dynamic>> _organizations = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار المنظمة')));
      return;
    }

    context.read<CreateAdminBloc>().add(
      CreateAdminSubmitted(
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        displayName: _nameController.text.trim(),
        role: _selectedRole,
        organizationUID: _selectedOrgUID!,
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
            if (widget.organizationUID.isNotEmpty) {
              _selectedOrgUID = widget.organizationUID;
            }
          });
        }
        if (state is CreateAdminSuccess) {
          _phoneController.clear();
          _emailController.clear();
          _nameController.clear();
          setState(() {
            _selectedOrgUID = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.adminCreatedSuccessfully),
              backgroundColor: Colors.green,
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

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
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
                    // Header icon
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 40,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
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
                    const SizedBox(height: 32),

                    // Display Name
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.adminName,
                        prefixIcon: Icon(
                          Icons.person_outline,
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
                          Icons.phone_outlined,
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
                          Icons.email_outlined,
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
                                });
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
                            title: 'موظف تسويق',
                            subtitle: 'Marketing',
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
                            title: 'مدير قطاع',
                            subtitle: 'Company Admin',
                            icon: Icons.business_rounded,
                            value: 'company-admin',
                            isSelected: _selectedRole == 'company-admin',
                            onTap: () {
                              setState(() => _selectedRole = 'company-admin');
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: isLoading ? null : _submitForm,
                        icon: const Icon(Icons.person_add_outlined),
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
