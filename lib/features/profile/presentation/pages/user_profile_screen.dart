import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

import '../../../../l10n/app_localizations.dart';

/// صفحة الملف الشخصي للمستخدم
/// User Profile Screen with ability to change password
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _auth = FirebaseAuth.instance;
  User? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _currentUser = _auth.currentUser;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.profile),
          backgroundColor: colorScheme.surface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.profile),
          backgroundColor: colorScheme.surface,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على المستخدم',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.profile),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          Delegate? delegate;
          if (state is AuthAuthenticated) {
            delegate = state.delegate;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Header
                _buildProfileHeader(colorScheme, theme, delegate),

                const SizedBox(height: 24),

                // Personal Information Card
                _buildPersonalInfoCard(colorScheme, theme, l10n, delegate),

                const SizedBox(height: 16),

                // Security Card
                _buildSecurityCard(colorScheme, theme, l10n, delegate),

                const SizedBox(height: 24),

                // Logout Button
                _buildLogoutButton(colorScheme, theme, l10n),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Profile Header ─────────────────────────────────────────────
  Widget _buildProfileHeader(
    ColorScheme colorScheme,
    ThemeData theme,
    Delegate? delegate,
  ) {
    final displayName = delegate?.fullName ?? _currentUser?.displayName ?? 'مستخدم';
    final email = delegate?.email ?? _currentUser?.email ?? '';

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.primary, width: 3),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Display Name
            Text(
              displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            // Email
            if (email.isNotEmpty)
              Text(
                email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  // ─── Personal Information Card ──────────────────────────────────
  Widget _buildPersonalInfoCard(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'المعلومات الشخصية',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Display Name
            _buildInfoRow(
              icon: Icons.badge_outlined,
              label: 'الاسم',
              value: delegate?.fullName ?? _currentUser?.displayName ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
            ),

            // Email
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'البريد الإلكتروني',
              value: delegate?.email ?? _currentUser?.email ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
            ),

            // Phone Number
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: 'رقم الموبايل',
              value: delegate?.phoneNumber ?? _currentUser?.phoneNumber ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Security Card ──────────────────────────────────────────────
  Widget _buildSecurityCard(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    color: colorScheme.secondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'الأمان',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Change Password Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showChangePasswordSheet(context, delegate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text(
                  'تغيير كلمة المرور',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Logout Button ──────────────────────────────────────────────
  Widget _buildLogoutButton(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showLogoutDialog(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: Text(
          l10n.logout,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ─── Info Row Widget ────────────────────────────────────────────
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required ThemeData theme,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  // ─── Change Password Sheet ──────────────────────────────────────
  void _showChangePasswordSheet(BuildContext context, Delegate? delegate) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChangePasswordBottomSheet(delegate: delegate, l10n: l10n),
    );
  }

  // ─── Logout Dialog ──────────────────────────────────────────────
  void _showLogoutDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logout),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _auth.signOut();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Change Password Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _ChangePasswordBottomSheet extends StatefulWidget {
  final Delegate? delegate;
  final AppLocalizations l10n;
  const _ChangePasswordBottomSheet({this.delegate, required this.l10n});

  @override
  State<_ChangePasswordBottomSheet> createState() => _ChangePasswordBottomSheetState();
}

class _ChangePasswordBottomSheetState extends State<_ChangePasswordBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final String currentPass = _currentPasswordController.text.trim();
      final String newPass = _newPasswordController.text.trim();

      bool passwordUpdated = false;

      // 1. Try Firebase Auth (if user exists and has email)
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null && fbUser.email != null) {
        try {
          final credential = EmailAuthProvider.credential(
            email: fbUser.email!,
            password: currentPass,
          );
          await fbUser.reauthenticateWithCredential(credential);
          await fbUser.updatePassword(newPass);
          passwordUpdated = true;
        } catch (e) {
          // Might fail if they log in via anonymous/phone, proceed to Firestore as fallback.
        }
      }

      // 2. Try Firestore 'users' collection (for Admin / Marketing phone users)
      if (widget.delegate != null) {
        final delegate = widget.delegate!;
        final db = FirebaseFirestore.instance;
        
        // Find user by email or phone number
        Query query = db.collection('users');
        if (delegate.email != null && delegate.email!.isNotEmpty) {
           query = query.where('email', isEqualTo: delegate.email);
        } else if (delegate.phoneNumber.isNotEmpty) {
           query = query.where('phoneNumber', isEqualTo: delegate.phoneNumber);
        }

        final snapshot = await query.limit(1).get();
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final storedPass = data['password'] ?? data['temporaryPassword'] ?? data['tempPassword'];

          if (storedPass == currentPass) {
             // Correct current password, update it
             await doc.reference.update({
               'password': newPass,
               'temporaryPassword': FieldValue.delete(),
               'tempPassword': FieldValue.delete(),
             });
             passwordUpdated = true;
          } else if (!passwordUpdated) {
             throw Exception('كلمة المرور الحالية غير صحيحة');
          }
        }
      }

      if (!passwordUpdated) {
        throw Exception('البيانات غير صحيحة أو لا يوجد حساب مرتبط بكلمة المرور هذه.');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تغيير كلمة المرور بنجاح'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    required ColorScheme colorScheme,
    required AppLocalizations l10n,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        prefixIcon: Icon(Icons.lock_outline, color: colorScheme.onSurfaceVariant),
        suffixIcon: IconButton(
          tooltip: obscureText ? l10n.showPassword : l10n.hidePassword,
          icon: Icon(
            obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: onToggleVisibility,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset_rounded, size: 28, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'تغيير كلمة المرور',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Current Password
              _buildTextField(
                controller: _currentPasswordController,
                label: 'كلمة المرور الحالية',
                obscureText: _obscureCurrentPassword,
                colorScheme: colorScheme,
                l10n: widget.l10n,
                onToggleVisibility: () {
                  setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال كلمة المرور الحالية';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // New Password
              _buildTextField(
                controller: _newPasswordController,
                label: 'كلمة المرور الجديدة',
                obscureText: _obscureNewPassword,
                colorScheme: colorScheme,
                l10n: widget.l10n,
                onToggleVisibility: () {
                  setState(() => _obscureNewPassword = !_obscureNewPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال كلمة المرور الجديدة';
                  }
                  if (value.length < 6) {
                    return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Confirm Password
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'تأكيد كلمة المرور',
                obscureText: _obscureConfirmPassword,
                colorScheme: colorScheme,
                l10n: widget.l10n,
                onToggleVisibility: () {
                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى تأكيد كلمة المرور';
                  }
                  if (value != _newPasswordController.text) {
                    return 'كلمة المرور غير متطابقة';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _changePassword,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('تغيير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

