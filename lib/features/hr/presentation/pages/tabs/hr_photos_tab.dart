import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/captured_photos_view_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

class HRPhotosTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRPhotosTab({super.key, required this.hrDelegate});

  @override
  State<HRPhotosTab> createState() => _HRPhotosTabState();
}

class _HRPhotosTabState extends State<HRPhotosTab> {
  int _selectedView = 0; // 0 = صور المعاينة الميدانية, 1 = أذونات التصوير
  final TextEditingController _searchController = TextEditingController();
  String _selectedBranch = 'all';

  late PhotoPermissionBloc _photoBloc;

  @override
  void initState() {
    super.initState();
    _photoBloc = di.sl<PhotoPermissionBloc>();
    _refreshData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _photoBloc.close();
    super.dispose();
  }

  void _refreshData() {
    if (_selectedView == 0) {
      _photoBloc.add(
        LoadCompanyCapturedPhotosRequested(
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
    } else {
      _photoBloc.add(
        LoadPermissionsRequested(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
    }
  }

  void _openPhotoDetail(CapturedPhoto photo) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    photo.delegateName.isNotEmpty
                        ? photo.delegateName
                        : 'معاينة الصورة',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Interactive Image Viewer
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: AppPhotoImage(
                      photoUrl: photo.photoUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Metadata Info Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 16, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          photo.branchName.isNotEmpty
                              ? photo.branchName
                              : 'الفرع غير محدد',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.schedule_rounded,
                            size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('yyyy/MM/dd - hh:mm a', 'ar')
                              .format(photo.capturedAt),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (photo.comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'ملاحظات: ${photo.comment}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider.value(
      value: _photoBloc,
      child: Column(
        children: [
          // ── Top Monthly Report Quick Link ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('الصور الميدانية'),
                        icon: Icon(Icons.photo_library_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('أذونات التصوير'),
                        icon: Icon(Icons.verified_rounded, size: 18),
                      ),
                    ],
                    selected: {_selectedView},
                    onSelectionChanged: (set) {
                      setState(() {
                        _selectedView = set.first;
                        _selectedBranch = 'all';
                      });
                      _refreshData();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider(
                          create: (_) => di.sl<PhotoPermissionBloc>(),
                          child: MonthlyPhotoReportScreen(
                            delegate: widget.hrDelegate,
                            showAppBar: true,
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('التقرير الشهري'),
                ),
              ],
            ),
          ),

          // ── Search & Filter Controls ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SearchBar(
              controller: _searchController,
              hintText: _selectedView == 0
                  ? 'بحث باسم المندوب أو الفرع...'
                  : 'بحث باسم الفرع أو كود الإذن...',
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              leading: const Icon(Icons.search_rounded, size: 20),
              trailing: _searchController.text.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    ]
                  : null,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // ── Content View ──
          Expanded(
            child: BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
              builder: (context, state) {
                if (state is PhotoPermissionLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is PhotoPermissionError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 48, color: colorScheme.error),
                        const SizedBox(height: 12),
                        Text(state.message,
                            style: TextStyle(color: colorScheme.error)),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _refreshData,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                } else if (_selectedView == 0 && state is CapturedPhotosLoaded) {
                  return _buildCapturedPhotosGrid(state.photos, theme, colorScheme);
                } else if (_selectedView == 1 &&
                    state is PhotoPermissionsLoaded) {
                  return _buildPermissionsList(
                      state.permissions, theme, colorScheme);
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedPhotosGrid(
    List<CapturedPhoto> photos,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = photos.where((p) {
      if (query.isNotEmpty) {
        final matchesName = p.delegateName.toLowerCase().contains(query);
        final matchesBranch = p.branchName.toLowerCase().contains(query);
        final matchesComment = p.comment.toLowerCase().contains(query);
        if (!matchesName && !matchesBranch && !matchesComment) return false;
      }
      if (_selectedBranch != 'all' && p.branchName != _selectedBranch) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'لا توجد صور معاينة ميدانية مطابقة',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refreshData(),
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 250,
          childAspectRatio: 0.78,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final photo = filtered[index];
          return InkWell(
            onTap: () => _openPhotoDetail(photo),
            borderRadius: BorderRadius.circular(16),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppPhotoImage(
                    photoUrl: photo.photoUrl,
                    fit: BoxFit.cover,
                  ),
                  // Gradient Overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Bottom Info
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photo.delegateName.isNotEmpty
                              ? photo.delegateName
                              : 'مندوب',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.storefront_rounded,
                                size: 12, color: Colors.amber),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                photo.branchName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MM/dd - hh:mm a', 'ar')
                              .format(photo.capturedAt),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionsList(
    List<PhotoPermission> permissions,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = permissions.where((p) {
      if (query.isNotEmpty) {
        final matchesBranch =
            p.branchNames.any((b) => b.toLowerCase().contains(query));
        final matchesCode =
            (p.companyCode?.toString() ?? '').toLowerCase().contains(query);
        if (!matchesBranch && !matchesCode) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'لا توجد أذونات تصوير مسجلة للشركة حالياً',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refreshData(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 750) {
            return GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 550,
                childAspectRatio: 2.2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildPermissionCard(
                filtered[index],
                theme,
                colorScheme,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildPermissionCard(
              filtered[index],
              theme,
              colorScheme,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionCard(
    PhotoPermission perm,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isActive = perm.status.toLowerCase() == 'approved' &&
        DateTime.now().isBefore(perm.endDate);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CapturedPhotosViewScreen(photoPermission: perm),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.assignment_turned_in_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          perm.branchNames.isNotEmpty
                              ? perm.branchNames.join('، ')
                              : 'إذن عام لجميع الفروع',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'من ${DateFormat('yyyy/MM/dd').format(perm.startDate)} إلى ${DateFormat('yyyy/MM/dd').format(perm.endDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (isActive
                              ? const Color(0xFF2E7D32)
                              : colorScheme.outline)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isActive ? 'نشط ومصرح' : 'منتهي أو قيد المراجعة',
                      style: TextStyle(
                        color: isActive
                            ? const Color(0xFF2E7D32)
                            : colorScheme.outline,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // Permitted departments
              if (perm.department != null &&
                  perm.department!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(perm.department!,
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'اضغط لعرض صور هذا الإذن',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
