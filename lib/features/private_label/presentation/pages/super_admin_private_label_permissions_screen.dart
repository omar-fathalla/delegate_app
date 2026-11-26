import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';

class SuperAdminPrivateLabelPermissionsScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const SuperAdminPrivateLabelPermissionsScreen({
    super.key,
    required this.adminDelegate,
  });

  @override
  State<SuperAdminPrivateLabelPermissionsScreen> createState() =>
      _SuperAdminPrivateLabelPermissionsScreenState();
}

class _SuperAdminPrivateLabelPermissionsScreenState
    extends State<SuperAdminPrivateLabelPermissionsScreen> {
  late final PrivateLabelPermissionsRemoteDataSource _permissionsDataSource;

  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<List<PrivateLabelPermissions>>? _permissionsSubscription;

  // State
  Map<String, PrivateLabelPermissions> _permissionsMap = {};
  List<Map<String, dynamic>> _loadedUsers = [];
  bool _isLoadingUsers = true;
  bool _isBulkProcessing = false;
  String _selectedRoleFilter = 'marketing_promotion'; // 'marketing_promotion', 'marketing', 'admin', 'all'
  String _selectedStatusFilter = 'all'; // 'all', 'permitted', 'unpermitted'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _permissionsDataSource = sl<PrivateLabelPermissionsRemoteDataSource>();
    _listenToPermissions();
    _fetchUsers();
  }

  @override
  void dispose() {
    _permissionsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToPermissions() {
    _permissionsSubscription =
        _permissionsDataSource.streamAllPermissions().listen((list) {
      if (!mounted) return;
      final map = <String, PrivateLabelPermissions>{};
      for (final p in list) {
        map[p.userId] = p;
      }
      setState(() {
        _permissionsMap = map;
      });
    });
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final users = await _permissionsDataSource.searchUsers(
        query: _searchQuery,
        roleFilter: _selectedRoleFilter,
      );
      if (mounted) {
        setState(() {
          _loadedUsers = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
        AppSnackBar.showError(context, 'فشل في تحميل المستخدمين: $e');
      }
    }
  }

  PrivateLabelPermissions _getPermissionForUser(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    if (_permissionsMap.containsKey(uid)) {
      return _permissionsMap[uid]!;
    }
    return PrivateLabelPermissions(
      userId: uid,
      userName: user['displayName'] ?? '',
      phoneNumber: user['phoneNumber'] ?? '',
      userRole: user['role'] ?? '',
      organizationUID: user['organizationUID'] ?? '',
      organizationName: user['organizationName'] ?? '',
      companyUID: user['companyUID'] ?? '',
      companyName: user['companyName'] ?? '',
      canCapture: false,
      canViewReports: false,
      canReviewAudit: false,
    );
  }

  Future<void> _toggleSinglePermission({
    required Map<String, dynamic> user,
    required String permissionKey, // 'capture', 'reports', 'audit'
    required bool newValue,
  }) async {
    HapticFeedback.selectionClick();
    final current = _getPermissionForUser(user);

    PrivateLabelPermissions updated;
    if (permissionKey == 'capture') {
      updated = current.copyWith(canCapture: newValue);
    } else if (permissionKey == 'reports') {
      updated = current.copyWith(canViewReports: newValue);
    } else {
      updated = current.copyWith(canReviewAudit: newValue);
    }

    // Optimistic local update
    setState(() {
      _permissionsMap[current.userId] = updated;
    });

    try {
      await _permissionsDataSource.updatePermissions(
        permissions: updated.copyWith(
          userName: user['displayName'] ?? current.userName,
          phoneNumber: user['phoneNumber'] ?? current.phoneNumber,
          userRole: user['role'] ?? current.userRole,
          organizationUID: user['organizationUID'] ?? current.organizationUID,
          organizationName: user['organizationName'] ?? current.organizationName,
          companyUID: user['companyUID'] ?? current.companyUID,
          companyName: user['companyName'] ?? current.companyName,
        ),
        adminUid: widget.adminDelegate.uid,
        adminName: widget.adminDelegate.fullName,
        adminRole: widget.adminDelegate.role.name,
      );

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'تم تحديث صلاحية (${_getPermissionArabicName(permissionKey)}) للمستخدم ${user['displayName']}',
        );
      }
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _permissionsMap[current.userId] = current;
        });
        AppSnackBar.showError(context, 'فشل في حفظ الصلاحية: $e');
      }
    }
  }

  Future<void> _setAllPermissionsForUser(
    Map<String, dynamic> user,
    bool enableAll,
  ) async {
    HapticFeedback.mediumImpact();
    final current = _getPermissionForUser(user);
    final updated = current.copyWith(
      canCapture: enableAll,
      canViewReports: enableAll,
      canReviewAudit: enableAll,
      userName: user['displayName'] ?? current.userName,
      phoneNumber: user['phoneNumber'] ?? current.phoneNumber,
      userRole: user['role'] ?? current.userRole,
      organizationUID: user['organizationUID'] ?? current.organizationUID,
      organizationName: user['organizationName'] ?? current.organizationName,
      companyUID: user['companyUID'] ?? current.companyUID,
      companyName: user['companyName'] ?? current.companyName,
    );

    setState(() {
      _permissionsMap[current.userId] = updated;
    });

    try {
      await _permissionsDataSource.updatePermissions(
        permissions: updated,
        adminUid: widget.adminDelegate.uid,
        adminName: widget.adminDelegate.fullName,
        adminRole: widget.adminDelegate.role.name,
      );

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          enableAll
              ? 'تم تفعيل جميع صلاحيات Private Label لـ ${user['displayName']}'
              : 'تم تعطيل جميع صلاحيات Private Label لـ ${user['displayName']}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _permissionsMap[current.userId] = current;
        });
        AppSnackBar.showError(context, 'فشل في تحديث الصلاحيات: $e');
      }
    }
  }

  String _getPermissionArabicName(String key) {
    switch (key) {
      case 'capture':
        return 'التوثيق الميداني';
      case 'reports':
        return 'التقارير';
      case 'audit':
        return 'الاعتمادات';
      default:
        return 'الصلاحية';
    }
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    return _loadedUsers.where((user) {
      final perm = _getPermissionForUser(user);

      if (_selectedStatusFilter == 'permitted' && !perm.hasAnyPermission) {
        return false;
      }
      if (_selectedStatusFilter == 'unpermitted' && perm.hasAnyPermission) {
        return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (user['displayName'] ?? '').toString().toLowerCase();
        final phone = (user['phoneNumber'] ?? '').toString().toLowerCase();
        final company = (user['companyName'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !phone.contains(q) && !company.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    final filteredUsers = _getFilteredUsers();

    // Calculate metrics
    final totalPermitted = _permissionsMap.values.where((p) => p.hasAnyPermission).length;
    final totalCapture = _permissionsMap.values.where((p) => p.canCapture).length;
    final totalReports = _permissionsMap.values.where((p) => p.canViewReports).length;
    final totalAudit = _permissionsMap.values.where((p) => p.canReviewAudit).length;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            isArabic ? 'صلاحيات Private Label' : 'Private Label Permissions',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: isArabic ? 'تحديث البيانات' : 'Refresh',
              onPressed: _fetchUsers,
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Metrics Pulse Summary Bar ──
            _buildMetricsBar(
              colorScheme: colorScheme,
              theme: theme,
              totalPermitted: totalPermitted,
              totalCapture: totalCapture,
              totalReports: totalReports,
              totalAudit: totalAudit,
            ),

            // ── Enterprise Filter Toolbar ──
            _buildFilterToolbar(
              context: context,
              colorScheme: colorScheme,
              theme: theme,
              isDesktop: isDesktop,
              isArabic: isArabic,
            ),

            // ── Results Counter & Bulk Actions Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_rounded,
                          size: 15,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${filteredUsers.length} مستخدم',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_isLoadingUsers || _isBulkProcessing)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: (filteredUsers.isEmpty || _isBulkProcessing || _isLoadingUsers)
                        ? null
                        : () => _openBulkActionsModal(context, filteredUsers, isArabic),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      isArabic ? 'إجراءات جماعية' : 'Bulk Actions',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bulk Processing Status Banner ──
            if (_isBulkProcessing)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isArabic
                            ? 'جاري تطبيق التعديلات الجماعية وتحديث الصلاحيات...'
                            : 'Applying bulk permission updates in background...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Users List ──
            Expanded(
              child: _isLoadingUsers && _loadedUsers.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(color: colorScheme.primary),
                    )
                  : filteredUsers.isEmpty
                      ? _buildEmptyState(colorScheme, theme, isArabic)
                      : RefreshIndicator(
                          onRefresh: _fetchUsers,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: filteredUsers.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final perm = _getPermissionForUser(user);
                              return _buildUserPermissionCard(
                                context: context,
                                colorScheme: colorScheme,
                                theme: theme,
                                user: user,
                                perm: perm,
                                isArabic: isArabic,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────── Widgets ──────────────────────────

  Widget _buildMetricsBar({
    required ColorScheme colorScheme,
    required ThemeData theme,
    required int totalPermitted,
    required int totalCapture,
    required int totalReports,
    required int totalAudit,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _buildMetricChip(
            icon: Icons.verified_user_rounded,
            label: 'المصرح لهم',
            count: totalPermitted,
            color: colorScheme.primary,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          _buildMetricChip(
            icon: Icons.camera_alt_rounded,
            label: 'التوثيق',
            count: totalCapture,
            color: colorScheme.tertiary,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          _buildMetricChip(
            icon: Icons.analytics_rounded,
            label: 'التقارير',
            count: totalReports,
            color: colorScheme.secondary,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          _buildMetricChip(
            icon: Icons.fact_check_rounded,
            label: 'الاعتمادات',
            count: totalAudit,
            color: colorScheme.primary,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToolbar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isDesktop,
    required bool isArabic,
  }) {
    final searchField = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
        decoration: InputDecoration(
          hintText: isArabic ? 'بحث بالاسم، الهاتف أو الشركة...' : 'Search by name, phone...',
          hintStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.onSurfaceVariant),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val.trim());
        },
      ),
    );

    final roleDropdown = _buildRoleDropdown(colorScheme, isArabic);
    final statusDropdown = _buildStatusDropdown(colorScheme, isArabic);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: isDesktop
          ? Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: roleDropdown),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: statusDropdown),
              ],
            )
          : Column(
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: roleDropdown),
                    const SizedBox(width: 8),
                    Expanded(child: statusDropdown),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildRoleDropdown(ColorScheme colorScheme, bool isArabic) {
    final Map<String, String> roles = {
      'marketing_promotion': isArabic ? 'تسويق العروض' : 'Promotion',
      'marketing': isArabic ? 'مسؤولي التسويق' : 'Marketing',
      'admin': isArabic ? 'مدراء القطاعات' : 'Admins',
      'all': isArabic ? 'جميع الأدوار' : 'All Roles',
    };

    return SizedBox(
      height: 44,
      child: PopupMenuButton<String>(
        initialValue: _selectedRoleFilter,
        color: colorScheme.surfaceContainerHigh,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        onSelected: (val) {
          setState(() => _selectedRoleFilter = val);
          _fetchUsers();
        },
        itemBuilder: (context) => roles.entries.map((e) {
          final isSelected = e.key == _selectedRoleFilter;
          return PopupMenuItem<String>(
            value: e.key,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.badge_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  roles[_selectedRoleFilter] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown(ColorScheme colorScheme, bool isArabic) {
    final Map<String, String> statuses = {
      'all': isArabic ? 'الكل' : 'All Status',
      'permitted': isArabic ? 'المصرح لهم فقط' : 'Permitted Only',
      'unpermitted': isArabic ? 'بدون صلاحيات' : 'No Permissions',
    };

    return SizedBox(
      height: 44,
      child: PopupMenuButton<String>(
        initialValue: _selectedStatusFilter,
        color: colorScheme.surfaceContainerHigh,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        onSelected: (val) {
          setState(() => _selectedStatusFilter = val);
        },
        itemBuilder: (context) => statuses.entries.map((e) {
          final isSelected = e.key == _selectedStatusFilter;
          return PopupMenuItem<String>(
            value: e.key,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.filter_alt_rounded, size: 18, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statuses[_selectedStatusFilter] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserPermissionCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required Map<String, dynamic> user,
    required PrivateLabelPermissions perm,
    required bool isArabic,
  }) {
    final hasPerm = perm.hasAnyPermission;
    final statusColor = hasPerm ? colorScheme.primary : colorScheme.outlineVariant;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.04),
        onTap: () => _openUserDetailModal(context, user, perm, isArabic),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: isArabic
                  ? BorderSide(color: statusColor, width: 3.5)
                  : BorderSide.none,
              left: !isArabic
                  ? BorderSide(color: statusColor, width: 3.5)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      (user['displayName'] as String).isNotEmpty
                          ? (user['displayName'] as String).substring(0, 1).toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user['displayName'] ?? '',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hasPerm
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                hasPerm ? 'مصرّح' : 'مغلق',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: hasPerm
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              icon: Icon(Icons.more_vert_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                              tooltip: 'خيارات سريعة',
                              onSelected: (action) {
                                if (action == 'grant_all') _setAllPermissionsForUser(user, true);
                                if (action == 'revoke_all') _setAllPermissionsForUser(user, false);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'grant_all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.select_all_rounded, size: 16),
                                      SizedBox(width: 8),
                                      Text('تفعيل الكل', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'revoke_all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.deselect_rounded, size: 16),
                                      SizedBox(width: 8),
                                      Text('تعطيل الكل', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if ((user['phoneNumber'] as String).isNotEmpty) ...[
                              Icon(Icons.phone_iphone_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                user['phoneNumber'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            if ((user['companyName'] as String).isNotEmpty) ...[
                              Icon(Icons.business_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  user['companyName'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // 3 Granular Permission Toggles
              Row(
                children: [
                  _buildTogglePill(
                    icon: Icons.camera_alt_rounded,
                    label: 'التوثيق',
                    isActive: perm.canCapture,
                    activeColor: colorScheme.tertiary,
                    colorScheme: colorScheme,
                    onToggle: (val) => _toggleSinglePermission(
                      user: user,
                      permissionKey: 'capture',
                      newValue: val,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTogglePill(
                    icon: Icons.analytics_rounded,
                    label: 'التقارير',
                    isActive: perm.canViewReports,
                    activeColor: colorScheme.secondary,
                    colorScheme: colorScheme,
                    onToggle: (val) => _toggleSinglePermission(
                      user: user,
                      permissionKey: 'reports',
                      newValue: val,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTogglePill(
                    icon: Icons.fact_check_rounded,
                    label: 'الاعتمادات',
                    isActive: perm.canReviewAudit,
                    activeColor: colorScheme.primary,
                    colorScheme: colorScheme,
                    onToggle: (val) => _toggleSinglePermission(
                      user: user,
                      permissionKey: 'audit',
                      newValue: val,
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

  Widget _buildTogglePill({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required ColorScheme colorScheme,
    required ValueChanged<bool> onToggle,
  }) {
    return Expanded(
      child: Material(
        color: isActive
            ? activeColor.withValues(alpha: 0.12)
            : colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isActive
                ? activeColor.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isActive ? 1.2 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onToggle(!isActive),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isActive ? activeColor : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? activeColor : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.cancel_outlined,
                  size: 13,
                  color: isActive ? activeColor : colorScheme.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, ThemeData theme, bool isArabic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.people_outline_rounded, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              isArabic ? 'لا توجد نتائج مطابقة' : 'No matching users found',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'جرب تغيير معايير البحث أو تصنيف الأدوار أعلاه'
                  : 'Try changing search terms or role filters above',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────── Responsive M3 Bottom Sheet / Dialog ────────────────

  void _openUserDetailModal(
    BuildContext context,
    Map<String, dynamic> user,
    PrivateLabelPermissions perm,
    bool isArabic,
  ) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: _UserPermissionsDetailContent(
              adminDelegate: widget.adminDelegate,
              user: user,
              initialPerm: perm,
              permissionsDataSource: _permissionsDataSource,
              onPermissionsUpdated: (updated) {
                setState(() => _permissionsMap[updated.userId] = updated);
              },
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Top drag handle pill
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _UserPermissionsDetailContent(
                adminDelegate: widget.adminDelegate,
                user: user,
                initialPerm: perm,
                permissionsDataSource: _permissionsDataSource,
                onPermissionsUpdated: (updated) {
                  setState(() => _permissionsMap[updated.userId] = updated);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  void _openBulkActionsModal(
    BuildContext context,
    List<Map<String, dynamic>> users,
    bool isArabic,
  ) {
    if (users.isEmpty) return;

    final isDesktop = MediaQuery.of(context).size.width >= 768;

    // Calculate current stats on these filtered users
    final activeCapture =
        users.where((u) => _getPermissionForUser(u).canCapture).length;
    final activeReports =
        users.where((u) => _getPermissionForUser(u).canViewReports).length;
    final activeAudit =
        users.where((u) => _getPermissionForUser(u).canReviewAudit).length;

    Widget contentBuilder(BuildContext ctx) {
      return _BulkActionsSheetContent(
        users: users,
        activeCapture: activeCapture,
        activeReports: activeReports,
        activeAudit: activeAudit,
        isArabic: isArabic,
        onToggleCapture: (enable) {
          Navigator.of(ctx).pop();
          _bulkToggleCapture(users, enable, isArabic);
        },
        onToggleReports: (enable) {
          Navigator.of(ctx).pop();
          _bulkToggleReports(users, enable, isArabic);
        },
        onToggleAudit: (enable) {
          Navigator.of(ctx).pop();
          _bulkToggleAudit(users, enable, isArabic);
        },
        onSetAll: (enableAll) {
          Navigator.of(ctx).pop();
          _bulkSetAll(users, enableAll, isArabic);
        },
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            child: contentBuilder(ctx),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Top drag handle pill
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              contentBuilder(ctx),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _executeBulkPermissionUpdate({
    required List<Map<String, dynamic>> targetUsers,
    required String actionTitle,
    required String confirmationMessage,
    required bool isDestructive,
    required String successMessage,
    required List<PrivateLabelPermissions> Function() buildUpdatedList,
    required bool isArabic,
  }) async {
    final confirmed = await _showBulkConfirmationDialog(
      context: context,
      title: actionTitle,
      message: confirmationMessage,
      confirmLabel: isDestructive
          ? (isArabic ? 'تأكيد الإيقاف' : 'Confirm Disable')
          : (isArabic ? 'تأكيد التفعيل' : 'Confirm Enable'),
      isDestructive: isDestructive,
      isArabic: isArabic,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBulkProcessing = true);
    final previousPermissions = Map<String, PrivateLabelPermissions>.from(_permissionsMap);

    // Build updated permissions list
    final updatedList = buildUpdatedList();

    // Optimistic local update
    setState(() {
      for (final p in updatedList) {
        _permissionsMap[p.userId] = p;
      }
    });

    try {
      await _permissionsDataSource.bulkUpdatePermissions(
        permissionsList: updatedList,
        adminUid: widget.adminDelegate.uid,
        adminName: widget.adminDelegate.fullName,
        adminRole: widget.adminDelegate.role.name,
        notificationActionLabel: actionTitle,
      );

      if (mounted) {
        setState(() => _isBulkProcessing = false);
        HapticFeedback.mediumImpact();
        AppSnackBar.showSuccess(context, successMessage);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _permissionsMap = previousPermissions;
          _isBulkProcessing = false;
        });
        AppSnackBar.showError(
          context,
          isArabic
              ? 'فشل في تطبيق التعديل الجماعي: $e'
              : 'Failed to apply bulk update: $e',
        );
      }
    }
  }

  void _bulkToggleCapture(
      List<Map<String, dynamic>> users, bool enable, bool isArabic) {
    final now = DateTime.now();
    final count = users.length;
    final action = enable
        ? (isArabic ? 'تفعيل التوثيق الميداني للجميع' : 'Enable Capture for All')
        : (isArabic ? 'إيقاف التوثيق الميداني للجميع' : 'Disable Capture for All');

    _executeBulkPermissionUpdate(
      targetUsers: users,
      actionTitle: action,
      confirmationMessage: isArabic
          ? 'هل أنت متأكد من ${enable ? "تفعيل" : "إيقاف"} صلاحية التوثيق الميداني لجميع الـ ($count) مستخدم المعروضين؟'
          : 'Are you sure you want to ${enable ? "enable" : "disable"} capture permissions for all ($count) users?',
      isDestructive: !enable,
      isArabic: isArabic,
      successMessage: isArabic
          ? 'تم ${enable ? "تفعيل" : "إيقاف"} التوثيق الميداني لـ $count مستخدم بنجاح'
          : 'Field capture ${enable ? "enabled" : "disabled"} for $count users successfully',
      buildUpdatedList: () {
        return users.map((u) {
          final current = _getPermissionForUser(u);
          return current.copyWith(
            canCapture: enable,
            userName: u['displayName'] ?? current.userName,
            phoneNumber: u['phoneNumber'] ?? current.phoneNumber,
            userRole: u['role'] ?? current.userRole,
            organizationUID: u['organizationUID'] ?? current.organizationUID,
            organizationName: u['organizationName'] ?? current.organizationName,
            companyUID: u['companyUID'] ?? current.companyUID,
            companyName: u['companyName'] ?? current.companyName,
            updatedAt: now,
            updatedBy: widget.adminDelegate.uid,
            updatedByName: widget.adminDelegate.fullName,
          );
        }).toList();
      },
    );
  }

  void _bulkToggleReports(
      List<Map<String, dynamic>> users, bool enable, bool isArabic) {
    final now = DateTime.now();
    final count = users.length;
    final action = enable
        ? (isArabic ? 'تفعيل التقارير للجميع' : 'Enable Reports for All')
        : (isArabic ? 'إيقاف التقارير للجميع' : 'Disable Reports for All');

    _executeBulkPermissionUpdate(
      targetUsers: users,
      actionTitle: action,
      confirmationMessage: isArabic
          ? 'هل أنت متأكد من ${enable ? "تفعيل" : "إيقاف"} صلاحية التقارير لجميع الـ ($count) مستخدم المعروضين؟'
          : 'Are you sure you want to ${enable ? "enable" : "disable"} reports permissions for all ($count) users?',
      isDestructive: !enable,
      isArabic: isArabic,
      successMessage: isArabic
          ? 'تم ${enable ? "تفعيل" : "إيقاف"} التقارير لـ $count مستخدم بنجاح'
          : 'Reports ${enable ? "enabled" : "disabled"} for $count users successfully',
      buildUpdatedList: () {
        return users.map((u) {
          final current = _getPermissionForUser(u);
          return current.copyWith(
            canViewReports: enable,
            userName: u['displayName'] ?? current.userName,
            phoneNumber: u['phoneNumber'] ?? current.phoneNumber,
            userRole: u['role'] ?? current.userRole,
            organizationUID: u['organizationUID'] ?? current.organizationUID,
            organizationName: u['organizationName'] ?? current.organizationName,
            companyUID: u['companyUID'] ?? current.companyUID,
            companyName: u['companyName'] ?? current.companyName,
            updatedAt: now,
            updatedBy: widget.adminDelegate.uid,
            updatedByName: widget.adminDelegate.fullName,
          );
        }).toList();
      },
    );
  }

  void _bulkToggleAudit(
      List<Map<String, dynamic>> users, bool enable, bool isArabic) {
    final now = DateTime.now();
    final count = users.length;
    final action = enable
        ? (isArabic ? 'تفعيل الاعتمادات للجميع' : 'Enable Audit Review for All')
        : (isArabic ? 'إيقاف الاعتمادات للجميع' : 'Disable Audit Review for All');

    _executeBulkPermissionUpdate(
      targetUsers: users,
      actionTitle: action,
      confirmationMessage: isArabic
          ? 'هل أنت متأكد من ${enable ? "تفعيل" : "إيقاف"} صلاحية الاعتمادات لجميع الـ ($count) مستخدم المعروضين؟'
          : 'Are you sure you want to ${enable ? "enable" : "disable"} audit review permissions for all ($count) users?',
      isDestructive: !enable,
      isArabic: isArabic,
      successMessage: isArabic
          ? 'تم ${enable ? "تفعيل" : "إيقاف"} الاعتمادات لـ $count مستخدم بنجاح'
          : 'Audit review ${enable ? "enabled" : "disabled"} for $count users successfully',
      buildUpdatedList: () {
        return users.map((u) {
          final current = _getPermissionForUser(u);
          return current.copyWith(
            canReviewAudit: enable,
            userName: u['displayName'] ?? current.userName,
            phoneNumber: u['phoneNumber'] ?? current.phoneNumber,
            userRole: u['role'] ?? current.userRole,
            organizationUID: u['organizationUID'] ?? current.organizationUID,
            organizationName: u['organizationName'] ?? current.organizationName,
            companyUID: u['companyUID'] ?? current.companyUID,
            companyName: u['companyName'] ?? current.companyName,
            updatedAt: now,
            updatedBy: widget.adminDelegate.uid,
            updatedByName: widget.adminDelegate.fullName,
          );
        }).toList();
      },
    );
  }

  void _bulkSetAll(
      List<Map<String, dynamic>> users, bool enableAll, bool isArabic) {
    final now = DateTime.now();
    final count = users.length;
    final action = enableAll
        ? (isArabic ? 'منح كافة الصلاحيات للكل' : 'Grant All Permissions to All')
        : (isArabic ? 'تعطيل كافة الصلاحيات للكل' : 'Revoke All Permissions from All');

    _executeBulkPermissionUpdate(
      targetUsers: users,
      actionTitle: action,
      confirmationMessage: isArabic
          ? 'هل أنت متأكد من ${enableAll ? "منح كافة صلاحيات Private Label" : "إيقاف كافة صلاحيات Private Label"} لجميع الـ ($count) مستخدم المعروضين؟'
          : 'Are you sure you want to ${enableAll ? "grant all" : "revoke all"} Private Label permissions for all ($count) users?',
      isDestructive: !enableAll,
      isArabic: isArabic,
      successMessage: isArabic
          ? 'تم ${enableAll ? "منح كافة الصلاحيات" : "إيقاف كافة الصلاحيات"} لـ $count مستخدم بنجاح'
          : 'All permissions ${enableAll ? "granted" : "revoked"} for $count users successfully',
      buildUpdatedList: () {
        return users.map((u) {
          final current = _getPermissionForUser(u);
          return current.copyWith(
            canCapture: enableAll,
            canViewReports: enableAll,
            canReviewAudit: enableAll,
            userName: u['displayName'] ?? current.userName,
            phoneNumber: u['phoneNumber'] ?? current.phoneNumber,
            userRole: u['role'] ?? current.userRole,
            organizationUID: u['organizationUID'] ?? current.organizationUID,
            organizationName: u['organizationName'] ?? current.organizationName,
            companyUID: u['companyUID'] ?? current.companyUID,
            companyName: u['companyName'] ?? current.companyName,
            updatedAt: now,
            updatedBy: widget.adminDelegate.uid,
            updatedByName: widget.adminDelegate.fullName,
          );
        }).toList();
      },
    );
  }

  Future<bool?> _showBulkConfirmationDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required bool isDestructive,
    required bool isArabic,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: Icon(
            isDestructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
            size: 36,
            color: isDestructive ? cs.error : cs.primary,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          content: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDestructive ? cs.error : cs.primary,
                      foregroundColor: isDestructive ? cs.onError : cs.onPrimary,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserPermissionsDetailContent extends StatefulWidget {
  final Delegate adminDelegate;
  final Map<String, dynamic> user;
  final PrivateLabelPermissions initialPerm;
  final PrivateLabelPermissionsRemoteDataSource permissionsDataSource;
  final ValueChanged<PrivateLabelPermissions> onPermissionsUpdated;

  const _UserPermissionsDetailContent({
    required this.adminDelegate,
    required this.user,
    required this.initialPerm,
    required this.permissionsDataSource,
    required this.onPermissionsUpdated,
  });

  @override
  State<_UserPermissionsDetailContent> createState() =>
      _UserPermissionsDetailContentState();
}

class _UserPermissionsDetailContentState
    extends State<_UserPermissionsDetailContent> {
  late bool _canCapture;
  late bool _canViewReports;
  late bool _canReviewAudit;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _canCapture = widget.initialPerm.canCapture;
    _canViewReports = widget.initialPerm.canViewReports;
    _canReviewAudit = widget.initialPerm.canReviewAudit;
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final updated = widget.initialPerm.copyWith(
      userName: widget.user['displayName'] ?? widget.initialPerm.userName,
      phoneNumber: widget.user['phoneNumber'] ?? widget.initialPerm.phoneNumber,
      userRole: widget.user['role'] ?? widget.initialPerm.userRole,
      organizationUID: widget.user['organizationUID'] ?? widget.initialPerm.organizationUID,
      organizationName: widget.user['organizationName'] ?? widget.initialPerm.organizationName,
      companyUID: widget.user['companyUID'] ?? widget.initialPerm.companyUID,
      companyName: widget.user['companyName'] ?? widget.initialPerm.companyName,
      canCapture: _canCapture,
      canViewReports: _canViewReports,
      canReviewAudit: _canReviewAudit,
    );

    try {
      await widget.permissionsDataSource.updatePermissions(
        permissions: updated,
        adminUid: widget.adminDelegate.uid,
        adminName: widget.adminDelegate.fullName,
        adminRole: widget.adminDelegate.role.name,
      );

      widget.onPermissionsUpdated(updated);
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackBar.showSuccess(
          context,
          'تم حفظ صلاحيات Private Label بنجاح وإرسال إشعار للمستخدم',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, 'فشل في الحفظ: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = widget.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  (user['displayName'] as String).isNotEmpty
                      ? (user['displayName'] as String).substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['displayName'] ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${user['role'] ?? 'تسويق'} • ${user['companyName'] ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),

          Text(
            'الصلاحيات المتاحة للنظام:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          // 1. Capture switch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.camera_alt_rounded, color: colorScheme.onTertiaryContainer, size: 20),
            ),
            title: const Text('التوثيق الميداني وتصوير المنتجات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text('تصوير المنتجات على الرف وبطاقات الأسعار وتسجيل أيام الراحة', style: TextStyle(fontSize: 11)),
            value: _canCapture,
            onChanged: (val) => setState(() => _canCapture = val),
          ),

          // 2. Reports switch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.analytics_rounded, color: colorScheme.onSecondaryContainer, size: 20),
            ),
            title: const Text('شاشة تقارير Private Label', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text('متابعة نسب الإنجاز الشهرية، ترتيب الفروع ومعدلات التغطية', style: TextStyle(fontSize: 11)),
            value: _canViewReports,
            onChanged: (val) => setState(() => _canViewReports = val),
          ),

          // 3. Audit switch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.fact_check_rounded, color: colorScheme.onPrimaryContainer, size: 20),
            ),
            title: const Text('شاشة تدقيق واعتماد التوثيقات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text('مراجعة توثيقات المسوقين، اعتمادها، وتعديل بطاقات الأسعار', style: TextStyle(fontSize: 11)),
            value: _canReviewAudit,
            onChanged: (val) => setState(() => _canReviewAudit = val),
          ),

          const SizedBox(height: 16),

          // Fast toggle buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.select_all_rounded, size: 16),
                label: const Text('منح الكل', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() {
                    _canCapture = true;
                    _canViewReports = true;
                    _canReviewAudit = true;
                  });
                },
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.deselect_rounded, size: 16),
                label: const Text('تعطيل الكل', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                onPressed: () {
                  setState(() {
                    _canCapture = false;
                    _canViewReports = false;
                    _canReviewAudit = false;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Connected Action Button Group (standard)
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: Center(
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant,
                ),
                Expanded(
                  child: Material(
                    color: colorScheme.primary,
                    child: InkWell(
                      onTap: _isSaving ? null : _saveChanges,
                      child: Center(
                        child: _isSaving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.save_rounded, size: 18, color: colorScheme.onPrimary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'حفظ الصلاحيات',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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
}

class _BulkActionsSheetContent extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final int activeCapture;
  final int activeReports;
  final int activeAudit;
  final bool isArabic;
  final ValueChanged<bool> onToggleCapture;
  final ValueChanged<bool> onToggleReports;
  final ValueChanged<bool> onToggleAudit;
  final ValueChanged<bool> onSetAll;

  const _BulkActionsSheetContent({
    required this.users,
    required this.activeCapture,
    required this.activeReports,
    required this.activeAudit,
    required this.isArabic,
    required this.onToggleCapture,
    required this.onToggleReports,
    required this.onToggleAudit,
    required this.onSetAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = users.length;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 22,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic ? 'إجراءات جماعية للصلاحيات' : 'Bulk Permissions Actions',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isArabic
                            ? 'تطبيق فوري على جميع الـ ($total) مستخدم المعروضين'
                            : 'Apply instantly to all ($total) displayed users',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: isArabic ? 'إغلاق' : 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Summary Active Metrics Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildQuickPill(
                    icon: Icons.camera_alt_rounded,
                    label: isArabic ? 'التوثيق' : 'Capture',
                    countText: '$activeCapture / $total',
                    color: colorScheme.tertiary,
                    colorScheme: colorScheme,
                  ),
                  Container(width: 1, height: 20, color: colorScheme.outlineVariant),
                  _buildQuickPill(
                    icon: Icons.analytics_rounded,
                    label: isArabic ? 'التقارير' : 'Reports',
                    countText: '$activeReports / $total',
                    color: colorScheme.secondary,
                    colorScheme: colorScheme,
                  ),
                  Container(width: 1, height: 20, color: colorScheme.outlineVariant),
                  _buildQuickPill(
                    icon: Icons.fact_check_rounded,
                    label: isArabic ? 'الاعتمادات' : 'Audit',
                    countText: '$activeAudit / $total',
                    color: colorScheme.primary,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 1. Capture Bulk Card
            _buildPermissionActionCard(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.camera_alt_rounded,
              iconColor: colorScheme.tertiary,
              title: isArabic ? 'صلاحية التوثيق الميداني' : 'Field Capture Permission',
              subtitle: isArabic
                  ? 'التقاط وتسجيل صور عروض ومواد Private Label'
                  : 'Capture and upload field display photos',
              activeCount: activeCapture,
              totalCount: total,
              onEnable: () => onToggleCapture(true),
              onDisable: () => onToggleCapture(false),
            ),
            const SizedBox(height: 10),

            // 2. Reports Bulk Card
            _buildPermissionActionCard(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.analytics_rounded,
              iconColor: colorScheme.secondary,
              title: isArabic ? 'صلاحية شاشة التقارير' : 'Reports Screen Permission',
              subtitle: isArabic
                  ? 'استعراض الإحصائيات الشهرية ونسب إنجاز التوثيق'
                  : 'View monthly completion statistics and reports',
              activeCount: activeReports,
              totalCount: total,
              onEnable: () => onToggleReports(true),
              onDisable: () => onToggleReports(false),
            ),
            const SizedBox(height: 10),

            // 3. Audit Bulk Card
            _buildPermissionActionCard(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.fact_check_rounded,
              iconColor: colorScheme.primary,
              title: isArabic ? 'صلاحية شاشة الاعتمادات' : 'Audit Review Permission',
              subtitle: isArabic
                  ? 'مراجعة وتدقيق الصور وقبول أو رفض التوثيق'
                  : 'Review display photos and accept/reject audits',
              activeCount: activeAudit,
              totalCount: total,
              onEnable: () => onToggleAudit(true),
              onDisable: () => onToggleAudit(false),
            ),
            const SizedBox(height: 12),

            // 4. Master Actions (All Permissions)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.stars_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        isArabic ? 'إجراءات شاملة (كافة الصلاحيات)' : 'Master Actions (All Permissions)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Connected Dual Action Button
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: colorScheme.primaryContainer,
                            child: InkWell(
                              onTap: () => onSetAll(true),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.done_all_rounded,
                                      size: 18,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isArabic ? 'تفعيل الكل للجميع' : 'Grant All to All',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: colorScheme.outlineVariant,
                        ),
                        Expanded(
                          child: Material(
                            color: colorScheme.surfaceContainerHigh,
                            child: InkWell(
                              onTap: () => onSetAll(false),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.block_rounded,
                                      size: 16,
                                      color: colorScheme.error,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isArabic ? 'إيقاف الكل للجميع' : 'Revoke All from All',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildQuickPill({
    required IconData icon,
    required String label,
    required String countText,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        Text(
          countText,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionActionCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int activeCount,
    required int totalCount,
    required VoidCallback onEnable,
    required VoidCallback onDisable,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (activeCount > 0 ? iconColor : colorScheme.outlineVariant)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activeCount / $totalCount مفعل',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: activeCount > 0 ? iconColor : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Connected dual button for this permission
          Container(
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: colorScheme.surface,
                    child: InkWell(
                      onTap: onEnable,
                      hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              isArabic ? 'تفعيل للجميع' : 'Enable for All',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant,
                ),
                Expanded(
                  child: Material(
                    color: colorScheme.surface,
                    child: InkWell(
                      onTap: onDisable,
                      hoverColor: colorScheme.error.withValues(alpha: 0.08),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cancel_outlined,
                                size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              isArabic ? 'إيقاف للجميع' : 'Disable for All',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
