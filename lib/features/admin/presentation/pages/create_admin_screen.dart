import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../bloc/create_admin_bloc.dart';

class CreateAdminScreen extends StatelessWidget {
  const CreateAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<CreateAdminBloc>()..add(LoadOrganizations()),
      child: const _CreateAdminView(),
    );
  }
}

class _CreateAdminView extends StatefulWidget {
  const _CreateAdminView();

  @override
  State<_CreateAdminView> createState() => _CreateAdminViewState();
}

class _CreateAdminViewState extends State<_CreateAdminView> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  
  String _selectedRole = 'company-admin';
  String? _selectedOrganizationUID;
  List<Map<String, dynamic>> _organizations = [];

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'marketing' && _selectedOrganizationUID == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.organizationRequired),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    context.read<CreateAdminBloc>().add(
      CreateAdminSubmitted(
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        displayName: _nameController.text.trim(),
        role: _selectedRole,
        organizationUID: _selectedRole == 'marketing' ? _selectedOrganizationUID : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<CreateAdminBloc, CreateAdminState>(
      listener: (context, state) {
        if (state is OrganizationsLoaded) {
           setState(() {
             _organizations = state.organizations;
           });
        } else if (state is CreateAdminSuccess) {
          _phoneController.clear();
          _emailController.clear();
          _nameController.clear();
          setState(() {
            _selectedOrganizationUID = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_selectedRole == 'marketing' ? l10n.marketingUserCreated : l10n.adminCreatedSuccessfully),
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
        final isOrgsLoading = state is OrganizationsLoading;

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
                          _selectedRole == 'marketing' ? Icons.analytics_rounded : Icons.admin_panel_settings_rounded,
                          size: 40,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        l10n.createUser,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // User Type Segmented Button
                    Center(
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment<String>(
                            value: 'company-admin',
                            label: Text(l10n.adminRole),
                            icon: const Icon(Icons.shield_outlined),
                          ),
                          ButtonSegment<String>(
                            value: 'marketing',
                            label: Text(l10n.marketingRole),
                            icon: const Icon(Icons.analytics_outlined),
                          ),
                        ],
                        selected: {_selectedRole},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _selectedRole = newSelection.first;
                          });
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 32),

                    // Organization Dropdown (Only for Marketing)
                    if (_selectedRole == 'marketing') ...[
                      if (isOrgsLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _selectedOrganizationUID,
                          decoration: InputDecoration(
                            labelText: l10n.selectOrganization,
                            prefixIcon: const Icon(Icons.business),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: colorScheme.outline),
                            ),
                          ),
                          items: _organizations.map((org) {
                            return DropdownMenuItem<String>(
                              value: org['uid'] as String,
                              child: Text(org['name'] ?? 'Unnamed Organization'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedOrganizationUID = value;
                            });
                          },
                          validator: (value) {
                            if (_selectedRole == 'marketing' && (value == null || value.isEmpty)) {
                              return l10n.organizationRequired;
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 20),
                    ],

                    // Display Name
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.adminName,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterAdminName;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Phone Number
                    TextFormField(
                      controller: _phoneController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.adminPhone,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterAdminPhone;
                        }
                        if (value.trim().length < 10) {
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
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.adminEmail,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterAdminEmail;
                        }
                        if (!RegExp(
                          r'^[^@]+@[^@]+\.[^@]+$',
                        ).hasMatch(value.trim())) {
                          return l10n.invalidEmail;
                        }
                        return null;
                      },
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
                                l10n.createUser,
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
