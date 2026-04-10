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
      create: (_) => di.sl<CreateAdminBloc>(),
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

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;

    context.read<CreateAdminBloc>().add(
      CreateAdminSubmitted(
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        displayName: _nameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<CreateAdminBloc, CreateAdminState>(
      listener: (context, state) {
        if (state is CreateAdminSuccess) {
          _phoneController.clear();
          _emailController.clear();
          _nameController.clear();
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
