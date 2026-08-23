import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/captured_photo.dart';

enum GroupMode {
  byDate,
  byBranch,
}

class MonthlyPhotoReportScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const MonthlyPhotoReportScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  State<MonthlyPhotoReportScreen> createState() => _MonthlyPhotoReportScreenState();
}

class _MonthlyPhotoReportScreenState extends State<MonthlyPhotoReportScreen> {
  late DateTime _selectedMonth;
  GroupMode _currentGroupMode = GroupMode.byDate;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime.now();

    final isGeneralManagerOrAdmin =
        widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.admin ||
        widget.delegate.role == UserRole.branchesMarketingManager;

    if (isGeneralManagerOrAdmin) {
      _currentGroupMode = GroupMode.byBranch;
    }

    _loadPhotos();
  }

  void _loadPhotos() {
    final isGeneralManagerOrAdmin =
        widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.admin ||
        widget.delegate.role == UserRole.branchesMarketingManager;

    if (isGeneralManagerOrAdmin) {
      context.read<PhotoPermissionBloc>().add(
            LoadCompanyCapturedPhotosRequested(companyUID: widget.delegate.companyUID),
          );
    } else {
      context.read<PhotoPermissionBloc>().add(
            LoadDelegateCapturedPhotosRequested(delegateUID: widget.delegate.uid),
          );
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    // عدم السماح بتخطي الشهر الحالي
    final now = DateTime.now();
    if (_selectedMonth.year >= now.year && _selectedMonth.month >= now.month) {
      return;
    }
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(
        title: const Text('تقارير الصور الشهرية'),
      ) : null,
      backgroundColor: colorScheme.surfaceContainerLow,
      body: BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'جاري تحميل تقارير الصور...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          if (state is CapturedPhotosLoaded) {
            // تصفية الصور حسب الشهر المحدد محلياً
            final filteredPhotos = state.photos.where((photo) {
              return photo.capturedAt.year == _selectedMonth.year &&
                  photo.capturedAt.month == _selectedMonth.month;
            }).toList();

            // حساب الإحصائيات
            final totalPhotos = filteredPhotos.length;
            final uniqueBranches = filteredPhotos.map((p) => p.branchId).toSet().length;
            
            final today = DateTime.now();
            final photosToday = filteredPhotos.where((p) =>
                p.capturedAt.year == today.year &&
                p.capturedAt.month == today.month &&
                p.capturedAt.day == today.day).length;

            return RefreshIndicator(
              onRefresh: () async {
                _loadPhotos();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // شريط التنقل بين الأشهر
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded),
                                onPressed: _previousMonth,
                                tooltip: 'الشهر السابق',
                              ),
                              Text(
                                _getMonthNameArabic(_selectedMonth),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios_rounded),
                                onPressed: isCurrentMonth ? null : _nextMonth,
                                tooltip: 'الشهر التالي',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // كروت الإحصائيات
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              title: 'إجمالي الصور',
                              value: '$totalPhotos',
                              icon: Icons.photo_library_rounded,
                              color: Colors.blue,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              title: 'الفروع المزارة',
                              value: '$uniqueBranches',
                              icon: Icons.store_rounded,
                              color: Colors.green,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              title: 'التقاطات اليوم',
                              value: '$photosToday',
                              icon: Icons.today_rounded,
                              color: Colors.orange,
                              theme: theme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // شريط اختيار طريقة العرض
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SegmentedButton<GroupMode>(
                        segments: const [
                          ButtonSegment<GroupMode>(
                            value: GroupMode.byDate,
                            label: Text('حسب التاريخ'),
                            icon: Icon(Icons.calendar_month_rounded),
                          ),
                          ButtonSegment<GroupMode>(
                            value: GroupMode.byBranch,
                            label: Text('حسب الفرع'),
                            icon: Icon(Icons.store_rounded),
                          ),
                        ],
                        selected: <GroupMode>{_currentGroupMode},
                        onSelectionChanged: (Set<GroupMode> newSelection) {
                          setState(() {
                            _currentGroupMode = newSelection.first;
                          });
                        },
                      ),
                    ),
                  ),

                  // عرض الصور أو حالة خلو البيانات
                  if (filteredPhotos.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(theme, colorScheme),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      sliver: _buildGroupedPhotosList(filteredPhotos, theme),
                    ),
                ],
              ),
            );
          }

          if (state is PhotoPermissionError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'خطأ أثناء تحميل البيانات',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.message,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadPhotos,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          return const Center(child: Text('جاري تحميل التقرير...'));
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPhotoCard(BuildContext context, CapturedPhoto photo, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateStr = DateFormat('dd-MM-yyyy hh:mm a').format(photo.capturedAt);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        onTap: () => _showPhotoDetails(context, photo),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.image_outlined, color: colorScheme.onPrimaryContainer),
        ),
        title: Text(
          photo.branchName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          dateStr,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_left_rounded, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildGroupedPhotosList(List<CapturedPhoto> photos, ThemeData theme) {
    if (_currentGroupMode == GroupMode.byDate) {
      // Group by date (day)
      final Map<String, List<CapturedPhoto>> grouped = {};
      for (var photo in photos) {
        final dateKey = DateFormat('yyyy-MM-dd').format(photo.capturedAt);
        grouped.putIfAbsent(dateKey, () => []).add(photo);
      }
      
      // Sort keys descending
      final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final key = sortedKeys[index];
            final groupPhotos = grouped[key]!;
            final displayDate = DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.parse(key));
            
            return _buildGroupExpansionTile(
              title: displayDate,
              icon: Icons.calendar_today_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    } else {
      // Group by branch
      final Map<String, List<CapturedPhoto>> grouped = {};
      for (var photo in photos) {
        grouped.putIfAbsent(photo.branchName, () => []).add(photo);
      }
      
      final sortedKeys = grouped.keys.toList()..sort();

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final key = sortedKeys[index];
            final groupPhotos = grouped[key]!;
            
            return _buildGroupExpansionTile(
              title: key,
              icon: Icons.store_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    }
  }

  Widget _buildGroupExpansionTile({
    required String title,
    required IconData icon,
    required List<CapturedPhoto> photos,
    required ThemeData theme,
  }) {
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedBackgroundColor: colorScheme.surface,
          backgroundColor: colorScheme.surfaceContainerLowest,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: colorScheme.onPrimaryContainer),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${photos.length} صور',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: photos.map((photo) => _buildCompactPhotoCard(context, photo, theme)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.no_photography_rounded,
              size: 72,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد صور ملتقطة في هذا الشهر',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'صور العروض الميدانية التي تقوم بالتقاطها عن طريق الكاميرا خلال هذا الشهر ستظهر هنا كتقارير منظمة.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthNameArabic(DateTime date) {
    final formatter = DateFormat('MMMM yyyy', 'ar');
    return formatter.format(date);
  }

  void _showPhotoDetails(BuildContext context, CapturedPhoto photo) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formattedDate = DateFormat('EEEE، d MMMM yyyy - hh:mm a', 'ar').format(photo.capturedAt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // مقبض السحب
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // العنوان وزر الإغلاق
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'تفاصيل الصورة الميدانية',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),

                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // الصورة التفاعلية (مع قرص للتكبير)
                        Container(
                          height: 350,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: photo.photoUrl.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: photo.photoUrl,
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                    errorWidget: (context, url, error) => const Center(
                                      child: Icon(Icons.broken_image, size: 64),
                                    ),
                                  )
                                : Image.file(
                                    File(photo.photoUrl),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) => const Center(
                                      child: Icon(Icons.broken_image, size: 64),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            '💡 يمكنك قرص الصورة أو استخدام إصبعين لتكبير التفاصيل',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // تفاصيل التقرير
                        _buildDetailItem(
                          icon: Icons.store_rounded,
                          title: 'الفرع المعتمد:',
                          value: photo.branchName,
                          theme: theme,
                        ),
                        const SizedBox(height: 12),
                        _buildDetailItem(
                          icon: Icons.calendar_today_rounded,
                          title: 'وقت وتاريخ الالتقاط:',
                          value: formattedDate,
                          theme: theme,
                        ),
                        const SizedBox(height: 12),
                        _buildDetailItem(
                          icon: Icons.person_rounded,
                          title: 'بواسطة المندوب:',
                          value: photo.delegateName,
                          theme: theme,
                        ),
                        
                        if (photo.comment.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildDetailItem(
                            icon: Icons.comment_rounded,
                            title: 'تعليق المندوب:',
                            value: photo.comment,
                            theme: theme,
                            isComment: true,
                          ),
                        ],
                        
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 12),

                        // إحداثيات الموقع والملاحة
                        Text(
                          'الموقع الجغرافي للالتقاط:',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'خط العرض (Lat): ${photo.latitude.toStringAsFixed(6)}',
                                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'خط الطول (Lng): ${photo.longitude.toStringAsFixed(6)}',
                                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () => _openMap(photo.latitude, photo.longitude),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.map_rounded),
                              label: const Text('الخريطة'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
    required ThemeData theme,
    bool isComment = false,
  }) {
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: isComment ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, color: colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontStyle: isComment ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openMap(double latitude, double longitude) async {
    final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    }
  }
}
