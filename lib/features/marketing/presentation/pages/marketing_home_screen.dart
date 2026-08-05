import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingHomeScreen extends StatelessWidget {
  final Delegate marketingUser;

  const MarketingHomeScreen({super.key, required this.marketingUser});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => di.sl<MarketingBloc>()
            ..add(LoadBranchPreferences(userId: marketingUser.uid)),
        ),
        BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>()
            ..add(const LoadPermissionsRequested(
              organizationUID: '', // All permissions globally for marketing
              companyUID: '',
            )),
        ),
      ],
      child: _MarketingHomeView(marketingUser: marketingUser),
    );
  }
}

class _MarketingHomeView extends StatefulWidget {
  final Delegate marketingUser;
  const _MarketingHomeView({required this.marketingUser});

  @override
  State<_MarketingHomeView> createState() => _MarketingHomeViewState();
}

class _MarketingHomeViewState extends State<_MarketingHomeView> {
  List<String> _favoriteBranches = [];
  bool _prefsLoaded = false;

  void _loadAttendance(BuildContext context, List<String> favorites) {
    if (favorites.isEmpty) return;
    context.read<MarketingBloc>().add(
      LoadAllFavoriteBranchesAttendance(
        favoriteBranches: favorites,
        organizationId: widget.marketingUser.organizationUID,
        date: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return BlocListener<MarketingBloc, MarketingState>(
      listenWhen: (prev, curr) => curr is BranchPreferencesLoaded,
      listener: (context, state) {
        if (state is BranchPreferencesLoaded) {
          setState(() {
            _favoriteBranches = state.favoriteBranches;
            _prefsLoaded = true;
          });
          _loadAttendance(context, state.favoriteBranches);
        }
      },
      child: RefreshIndicator(
        onRefresh: () async {
          context.read<MarketingBloc>().add(
            LoadBranchPreferences(userId: widget.marketingUser.uid),
          );
          context.read<PhotoPermissionBloc>().add(
            const LoadPermissionsRequested(
              organizationUID: '',
              companyUID: '',
            ),
          );
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Welcome & App Info Card ──
              _buildWelcomeCard(colorScheme, isArabic),
              const SizedBox(height: 20),

              // ── 2. Photo Permissions Stats Section ──
              Text(
                isArabic ? 'إحصائيات أذونات التصوير' : 'Photo Permissions Stats',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              _buildStatsGrid(colorScheme, isArabic),
              const SizedBox(height: 24),

              // ── 3. Role-specific Section ──
              if (widget.marketingUser.role != UserRole.marketingPromotion) ...[
                Text(
                  isArabic ? 'صلاحيات تسويق الفروع المضافة' : 'Favorite Branches Marketing Validity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _buildBranchesList(colorScheme, isArabic),
              ] else ...[
                _buildPhotoReportsCard(context, colorScheme, isArabic),
              ],
              const SizedBox(height: 100), // Spacing for BottomNavigationBar
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoReportsCard(BuildContext context, ColorScheme colorScheme, bool isArabic) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider(
                create: (context) => di.sl<PhotoPermissionBloc>(),
                child: MonthlyPhotoReportScreen(
                  delegate: widget.marketingUser,
                  showAppBar: true,
                ),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'تقارير الصور' : 'Photo Reports',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isArabic 
                          ? 'عرض تقارير الصور للشركات' 
                          : 'View company photo reports',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Welcome & App/Market Info Card ──
  Widget _buildWelcomeCard(ColorScheme colorScheme, bool isArabic) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.business_center_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'مرحباً بك في نظام التسويق' : 'Welcome to Market System',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic ? 'تطبيق تسهيل المندوب' : 'Tasheel Delegate App',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Colors.white24),
          ),
          Text(
            isArabic
                ? 'يوفر نظام التسويق (Market System) لمسؤولي ومروجي التسويق القدرة على متابعة الفروع وإصدار وتفعيل أذونات تصوير المنتجات للشركات، بالإضافة للتحقق من الحضور اليومي للمناديب لضمان سير العمل الميداني بكفاءة.'
                : 'The Market System provides marketing administrators and promoters with the ability to monitor branches, issue and activate photo permissions for companies, and track delegates\' daily attendance.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  // ── Photo Permissions Stats Row/Grid ──
  Widget _buildStatsGrid(ColorScheme colorScheme, bool isArabic) {
    return BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
      builder: (context, state) {
        int activeCount = 0;
        int pendingCount = 0;
        bool isLoading = state is PhotoPermissionLoading;

        if (state is PhotoPermissionsLoaded || state is OngoingPermissionsLoaded) {
          final permissions = state is PhotoPermissionsLoaded
              ? state.permissions
              : (state as OngoingPermissionsLoaded).permissions;

          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

          activeCount = permissions.where((p) =>
              p.status.toLowerCase() == 'approved' &&
              p.isSupervisorEnabled != false &&
              !p.startDate.isAfter(todayEnd) &&
              !p.endDate.isBefore(todayStart)).length;

          pendingCount = permissions.where((p) =>
              p.status.toLowerCase() == 'pending').length;
        }

        return Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: isArabic ? 'أذونات نشطة' : 'Active Permits',
                value: isLoading ? '...' : '$activeCount',
                icon: Icons.check_circle_rounded,
                color: Colors.green,
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: isArabic ? 'قيد الاعتماد' : 'Pending Review',
                value: isLoading ? '...' : '$pendingCount',
                icon: Icons.pending_rounded,
                color: Colors.orange,
                colorScheme: colorScheme,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Favorite Branches List with validity & delegate count ──
  Widget _buildBranchesList(ColorScheme colorScheme, bool isArabic) {
    if (!_prefsLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_favoriteBranches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(Icons.store_mall_directory_rounded, size: 48, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'لم تقم بإضافة أي فرع مفضل بعد.'
                  : 'No favorite branches added yet.',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'يرجى الانتقال لتبويب الفروع لإضافة الفروع ومتابعتها.'
                  : 'Please go to the Branches tab to add and monitor branches.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return BlocBuilder<MarketingBloc, MarketingState>(
      buildWhen: (prev, curr) =>
          curr is AllBranchesAttendanceLoading ||
          curr is AllBranchesAttendanceLoaded ||
          curr is AllBranchesAttendanceError,
      builder: (context, marketingState) {
        return BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
          builder: (context, permissionState) {
            final permissions = permissionState is PhotoPermissionsLoaded
                ? permissionState.permissions
                : (permissionState is OngoingPermissionsLoaded
                    ? permissionState.permissions
                    : <PhotoPermission>[]);

            final Map<String, List<Map<String, dynamic>>> attendanceData =
                marketingState is AllBranchesAttendanceLoaded
                    ? marketingState.data
                    : {};

            final isAttendanceLoading = marketingState is AllBranchesAttendanceLoading;

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _favoriteBranches.length,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final branchName = _favoriteBranches[index];
                final branchAttendance = attendanceData[branchName] ?? [];
                
                // Find validity of marketing permission for this branch
                final permissionStatus = _getBranchPermissionStatus(branchName, permissions);

                return _buildBranchValidityCard(
                  branchName: branchName,
                  delegateCount: branchAttendance.length,
                  permissionStatus: permissionStatus,
                  isAttendanceLoading: isAttendanceLoading,
                  colorScheme: colorScheme,
                  isArabic: isArabic,
                );
              },
            );
          },
        );
      },
    );
  }

  // Find the permission status and details for a branch
  _BranchPermissionInfo _getBranchPermissionStatus(String branchName, List<PhotoPermission> permissions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    PhotoPermission? activePermission;
    PhotoPermission? pendingPermission;

    for (final p in permissions) {
      if (p.branchNames.contains(branchName)) {
        final status = p.status.toLowerCase();
        if (status == 'approved' &&
            p.isSupervisorEnabled != false &&
            !p.startDate.isAfter(todayEnd) &&
            !p.endDate.isBefore(todayStart)) {
          if (activePermission == null || p.endDate.isAfter(activePermission.endDate)) {
            activePermission = p;
          }
        } else if (status == 'pending') {
          pendingPermission = p;
        }
      }
    }

    if (activePermission != null) {
      return _BranchPermissionInfo(
        status: _PermissionStatusType.active,
        details: 'من: ${DateFormat('yyyy-MM-dd').format(activePermission.startDate)} إلى: ${DateFormat('yyyy-MM-dd').format(activePermission.endDate)}',
        companyName: activePermission.companyName,
      );
    } else if (pendingPermission != null) {
      return _BranchPermissionInfo(
        status: _PermissionStatusType.pending,
        details: 'طلب إذن تصوير قيد الاعتماد',
        companyName: pendingPermission.companyName,
      );
    } else {
      return _BranchPermissionInfo(
        status: _PermissionStatusType.none,
        details: 'لا توجد صلاحية تسويق نشطة',
      );
    }
  }

  Widget _buildBranchValidityCard({
    required String branchName,
    required int delegateCount,
    required _BranchPermissionInfo permissionStatus,
    required bool isAttendanceLoading,
    required ColorScheme colorScheme,
    required bool isArabic,
  }) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (permissionStatus.status) {
      case _PermissionStatusType.active:
        statusColor = Colors.green;
        statusLabel = isArabic ? 'صلاحية تسويق نشطة' : 'Active Marketing';
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case _PermissionStatusType.pending:
        statusColor = Colors.orange;
        statusLabel = isArabic ? 'قيد الاعتماد' : 'Awaiting Approval';
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case _PermissionStatusType.none:
        statusColor = Colors.red.shade400;
        statusLabel = isArabic ? 'غير مصرح بالتصوير' : 'No Photography Permit';
        statusIcon = Icons.cancel_outlined;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch Header & Attendance count badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    branchName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isAttendanceLoading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : Text(
                        isArabic ? '$delegateCount مناديب اليوم' : '$delegateCount delegates today',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Marketing Validity details
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      permissionStatus.details,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (permissionStatus.companyName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        isArabic
                            ? 'الشركة: ${permissionStatus.companyName}'
                            : 'Company: ${permissionStatus.companyName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PermissionStatusType { active, pending, none }

class _BranchPermissionInfo {
  final _PermissionStatusType status;
  final String details;
  final String? companyName;

  _BranchPermissionInfo({
    required this.status,
    required this.details,
    this.companyName,
  });
}
