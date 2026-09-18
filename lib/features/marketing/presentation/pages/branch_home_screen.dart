import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// الشاشة الرئيسية للفروع - تعرض جميع الفروع المفضلة في نفس الصفحة
class BranchHomeScreen extends StatelessWidget {
  final Delegate marketingUser;
  final bool showAppBar;

  const BranchHomeScreen({
    super.key,
    required this.marketingUser,
    this.showAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = di.sl<MarketingBloc>();
        final prefService = di.sl<BranchPreferenceService>();
        final favorites = prefService.getFavoriteBranches(marketingUser.uid);
        if (favorites.isNotEmpty) {
          bloc.add(
            LoadAllFavoriteBranchesAttendance(
              favoriteBranches: favorites,
              organizationId: marketingUser.organizationUID.isNotEmpty
                  ? marketingUser.organizationUID
                  : 'PiioBFgxaHAeuRdjlDgj',
              date: DateTime.now(),
            ),
          );
        }
        bloc.add(LoadBranchPreferences(userId: marketingUser.uid));
        return bloc;
      },
      child: _BranchHomeView(
        marketingUser: marketingUser,
        showAppBar: showAppBar,
      ),
    );
  }
}

class _BranchHomeView extends StatefulWidget {
  final Delegate marketingUser;
  final bool showAppBar;

  const _BranchHomeView({
    required this.marketingUser,
    this.showAppBar = false,
  });

  @override
  State<_BranchHomeView> createState() => _BranchHomeViewState();
}

class _BranchHomeViewState extends State<_BranchHomeView> {
  List<String> _favoriteBranches = [];
  bool _prefsLoaded = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    try {
      final prefService = di.sl<BranchPreferenceService>();
      final favorites = prefService.getFavoriteBranches(widget.marketingUser.uid);
      _favoriteBranches = favorites;
      _prefsLoaded = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadAllBranches(BuildContext context, List<String> favorites) {
    if (favorites.isEmpty) return;
    context.read<MarketingBloc>().add(
      LoadAllFavoriteBranchesAttendance(
        favoriteBranches: favorites,
        organizationId: widget.marketingUser.organizationUID.isNotEmpty
            ? widget.marketingUser.organizationUID
            : 'PiioBFgxaHAeuRdjlDgj',
        date: _selectedDate,
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null && picked != _selectedDate) {
      if (!mounted) return;
      setState(() {
        _selectedDate = picked;
      });
      _loadAllBranches(context, _favoriteBranches);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<MarketingBloc, MarketingState>(
      listenWhen: (prev, curr) =>
          curr is BranchPreferencesLoaded ||
          curr is AllBranchesAttendanceLoaded ||
          curr is AllBranchesAttendanceError ||
          curr is AllBranchesAttendanceLoading,
      listener: (context, state) {
        if (state is BranchPreferencesLoaded) {
          final favorites = state.favoriteBranches;
          setState(() {
            _favoriteBranches = favorites;
            _prefsLoaded = true;
          });
          if (favorites.isEmpty) {
            // لا توجد فروع → افتح المنتقي
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showBranchPicker(context);
            });
          } else {
            // حمّل بيانات كل الفروع دفعة واحدة
            _loadAllBranches(context, favorites);
          }
        }
      },
      buildWhen: (prev, curr) =>
          curr is BranchPreferencesLoaded ||
          curr is AllBranchesAttendanceLoading ||
          curr is AllBranchesAttendanceLoaded ||
          curr is AllBranchesAttendanceError,
      builder: (context, state) {
        if (!_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        Widget body;

        if (_favoriteBranches.isEmpty) {
          body = _buildEmptyState(context, colorScheme);
        } else if (state is AllBranchesAttendanceLoading) {
          body = _buildLoadingSkeletons(colorScheme);
        } else if (state is AllBranchesAttendanceError) {
          body = _buildError(context, state.message, colorScheme);
        } else if (state is AllBranchesAttendanceLoaded) {
          body = _buildAllBranches(context, state, colorScheme);
        } else {
          body = const Center(child: CircularProgressIndicator());
        }

        final content = Stack(
          children: [
            body,
            // ─── FAB: إضافة فرع ───────────────────────────────────────────
            Positioned(
              bottom: 16,
              left: 16,
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: () => _showBranchPicker(context),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('إضافة فرع'),
                elevation: 3,
              ),
            ),
          ],
        );

        if (widget.showAppBar) {
          return Scaffold(
            backgroundColor: colorScheme.surfaceContainerLowest,
            appBar: AppBar(
              backgroundColor: colorScheme.surfaceContainer,
              elevation: 0,
              shape: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              title: Text(
                'متابعة حضور الفروع',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              centerTitle: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded),
                  tooltip: 'تغيير التاريخ',
                  onPressed: _selectDate,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'تحديث',
                  onPressed: () => _loadAllBranches(context, _favoriteBranches),
                ),
              ],
            ),
            body: content,
          );
        }

        return content;
      },
    );
  }

  // ─── Empty State ─────────────────────────────────────────────────────────
  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.store_mall_directory_rounded,
              size: 56,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'لم تضف أي فرع بعد',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أضف فروعك لمتابعة الحضور اليومي',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showBranchPicker(context),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('إضافة فرع'),
          ),
        ],
      ),
    );
  }

  // ─── Loading Skeletons ────────────────────────────────────────────────────
  Widget _buildLoadingSkeletons(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteBranches.length,
      itemBuilder: (_, index) => _BranchSectionSkeleton(
        branchName: _favoriteBranches[index],
        colorScheme: colorScheme,
      ),
    );
  }

  // ─── Error ──────────────────────────────────────────────────────────────
  Widget _buildError(
    BuildContext context,
    String message,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _loadAllBranches(context, _favoriteBranches),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  // ─── All Branches Sections ───────────────────────────────────────────────
  Widget _buildAllBranches(
    BuildContext context,
    AllBranchesAttendanceLoaded state,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: () async => _loadAllBranches(context, _favoriteBranches),
      child: CustomScrollView(
        slivers: [
          // ─── تاريخ اليوم ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                elevation: 0,
                color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  ),
                ),
                child: InkWell(
                  onTap: () => _selectDate(),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE، d MMMM yyyy', 'ar').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color: colorScheme.primary,
                        ),
                        const Spacer(),
                        if (!DateUtils.isSameDay(_selectedDate, DateTime.now()))
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedDate = DateTime.now();
                              });
                              _loadAllBranches(context, _favoriteBranches);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'اليوم',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ─── شريط البحث عن مندوب أو شركة ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المندوب أو اسم الشركة...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colorScheme.primary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),

          // ─── قسم لكل فرع ──────────────────────────────────────────────
          for (final branchName in state.favoriteBranches)
            _buildBranchSection(
              context,
              branchName,
              state.data[branchName] ?? [],
              colorScheme,
            ),

          // مسافة أسفل الصفحة
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─── Branch Section (Header + Delegate Cards) ─────────────────────────────
  Widget _buildBranchSection(
    BuildContext context,
    String branchName,
    List<Map<String, dynamic>> records,
    ColorScheme colorScheme,
  ) {
    final query = _searchQuery.toLowerCase();
    final filteredRecords = query.isEmpty
        ? records
        : records.where((r) {
            final name = (r['fullName'] as String? ?? '').toLowerCase();
            final company = (r['companyName'] as String? ?? '').toLowerCase();
            final phone = (r['phoneNumber'] as String? ?? '').toLowerCase();
            return name.contains(query) || company.contains(query) || phone.contains(query);
          }).toList();

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Branch Header ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.secondaryContainer,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
                bottom: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    branchName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                // Badge عدد المندوبين
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    query.isEmpty
                        ? '${records.length} مندوب'
                        : '${filteredRecords.length} من ${records.length}',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // زر حذف الفرع المباشر
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  tooltip: 'إزالة الفرع من القائمة',
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _confirmRemoveBranch(context, branchName),
                ),
              ],
            ),
          ),

          // ── Delegates List ──
          if (filteredRecords.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    query.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.people_outline_rounded,
                    color: colorScheme.outlineVariant,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    query.isNotEmpty
                        ? 'لا يوجد مندوب مطابق للبحث في هذا الفرع'
                        : 'لا يوجد حضور اليوم',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                  bottom: Radius.circular(16),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: filteredRecords.asMap().entries.map((entry) {
                  final isLast = entry.key == filteredRecords.length - 1;
                  return Column(
                    children: [
                      _buildDelegateRow(context, entry.value, colorScheme),
                      if (!isLast)
                        Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          indent: 68,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Delegate Row ─────────────────────────────────────────────────────────
  Widget _buildDelegateRow(
    BuildContext context,
    Map<String, dynamic> record,
    ColorScheme colorScheme,
  ) {
    final String fullName = record['fullName'] as String? ?? 'مندوب';
    final String companyName = record['companyName'] as String? ?? '';
    final String? imageUrl = record['personalPhotoURL'] as String? ??
        record['imageUrl'] as String?;
    final checkIn = record['checkInTime'] as Timestamp?;
    final checkOut = record['checkOutTime'] as Timestamp?;
    final bool hasCheckOut = checkOut != null;

    final checkInStr = checkIn != null
        ? DateFormat('hh:mm a', 'ar').format(checkIn.toDate())
        : '--:--';
    final checkOutStr = checkOut != null
        ? DateFormat('hh:mm a', 'ar').format(checkOut.toDate())
        : '--:--';

    final hasPhoto = imageUrl != null && imageUrl.isNotEmpty;

    return InkWell(
      onTap: () => _openAttendanceHistory(context, record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar (صورة المندوب أو الحرف الأول مع إمكانية التكبير عند الضغط)
            GestureDetector(
              onTap: hasPhoto
                  ? () => _showImagePreview(
                        context,
                        imageUrl,
                        fullName,
                        companyName,
                      )
                  : null,
              child: AppAvatar(
                imageUrl: hasPhoto ? imageUrl : null,
                fallbackText: fullName,
                radius: 22,
                backgroundColor: hasCheckOut
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.primaryContainer,
                foregroundColor: hasCheckOut
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onPrimaryContainer,
                badge: hasPhoto
                    ? Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.zoom_in_rounded,
                          size: 10,
                          color: colorScheme.primary,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      companyName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _miniChip(
                        Icons.login_rounded,
                        checkInStr,
                        colorScheme.tertiaryContainer,
                        colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 6),
                      _miniChip(
                        Icons.logout_rounded,
                        checkOutStr,
                        hasCheckOut
                            ? colorScheme.errorContainer.withValues(alpha: 0.6)
                            : colorScheme.surfaceContainerHighest,
                        hasCheckOut
                            ? colorScheme.onErrorContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Call Supervisor Button
            IconButton(
              icon: Icon(
                Icons.phone_in_talk_rounded,
                color: colorScheme.primary,
                size: 19,
              ),
              tooltip: 'اتصال بمشرف المندوب',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _contactSupervisor(context, record),
            ),
            const SizedBox(width: 8),
            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: hasCheckOut
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasCheckOut ? 'منصرف' : 'حاضر',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasCheckOut
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded, color: colorScheme.outline, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: fg, fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Contact Supervisor (اتصال بمشرف المندوب) ──────────────────────────
  Future<void> _contactSupervisor(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final String delegateName = record['fullName'] as String? ?? 'المندوب';
    final String companyName = record['companyName'] as String? ?? '';
    final String companyUID = record['companyUID'] as String? ?? '';
    final delegateData = record['delegateData'] as Map<String, dynamic>?;

    String? supName = record['supervisorName'] as String? ??
        delegateData?['supervisorName'] as String?;
    String? supPhone = record['supervisorPhone'] as String? ??
        delegateData?['supervisorPhone'] as String?;

    // If supervisor phone is not directly present, resolve it dynamically
    if (supPhone == null || supPhone.trim().isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final firestore = di.sl<FirebaseFirestore>();

        // 1. Check createdBy in users
        final createdBy = (record['createdBy'] ?? delegateData?['createdBy']) as String?;
        if (createdBy != null && createdBy.isNotEmpty) {
          final supDoc = await firestore.collection('users').doc(createdBy).get();
          if (supDoc.exists && supDoc.data() != null) {
            final data = supDoc.data()!;
            final phone = data['phoneNumber'] as String? ?? data['phone'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= data['displayName'] as String? ?? data['name'] as String?;
            }
          }
        }

        // 2. If still empty, search users for company-admin or supervisor of this company
        if ((supPhone == null || supPhone.isEmpty) && companyUID.isNotEmpty) {
          final querySnap = await firestore
              .collection('users')
              .where('companyUID', isEqualTo: companyUID)
              .where('role', whereIn: ['company-admin', 'supervisor'])
              .limit(1)
              .get();

          if (querySnap.docs.isNotEmpty) {
            final data = querySnap.docs.first.data();
            final phone = data['phoneNumber'] as String? ?? data['phone'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= data['displayName'] as String? ?? data['name'] as String?;
            }
          }
        }

        // 3. If still empty, check company document in organizations
        final effectiveOrg = widget.marketingUser.organizationUID.isNotEmpty
            ? widget.marketingUser.organizationUID
            : (record['organizationId'] as String? ??
                delegateData?['organizationUID'] as String? ??
                'PiioBFgxaHAeuRdjlDgj');

        if ((supPhone == null || supPhone.isEmpty) &&
            companyUID.isNotEmpty &&
            effectiveOrg.isNotEmpty) {
          final compDoc = await firestore
              .collection('organizations')
              .doc(effectiveOrg)
              .collection('companies')
              .doc(companyUID)
              .get();
          if (compDoc.exists && compDoc.data() != null) {
            final compData = compDoc.data()!;
            final phone = compData['supervisorPhone'] as String? ??
                compData['phone'] as String? ??
                compData['phoneNumber'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= compData['supervisorName'] as String? ??
                  (companyName.isNotEmpty ? 'مشرف $companyName' : null);
            }
          }
        }

        // Cache for subsequent taps
        if (supPhone != null && supPhone.isNotEmpty) {
          record['supervisorPhone'] = supPhone;
          if (supName != null) record['supervisorName'] = supName;
        }
      } catch (_) {
      } finally {
        if (context.mounted) Navigator.of(context).pop();
      }
    }

    if (!context.mounted) return;

    _showSupervisorModal(
      context: context,
      delegateName: delegateName,
      companyName: companyName,
      supervisorName: (supName != null && supName.isNotEmpty)
          ? supName
          : (companyName.isNotEmpty ? 'مشرف $companyName' : 'مشرف المندوب'),
      supervisorPhone: supPhone,
    );
  }

  void _showSupervisorModal({
    required BuildContext context,
    required String delegateName,
    required String companyName,
    required String supervisorName,
    required String? supervisorPhone,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPhone = supervisorPhone != null && supervisorPhone.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Avatar & Titles
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.supervisor_account_rounded,
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
                          'الاتصال بمشرف المندوب',
                          style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '$delegateName ${companyName.isNotEmpty ? '• $companyName' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (hasPhone) ...[
                // Supervisor Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              supervisorName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'مشرف الشركة',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_iphone_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              supervisorPhone,
                              style: GoogleFonts.cairo(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            tooltip: 'نسخ الرقم',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: supervisorPhone),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ رقم المشرف إلى الحافظة'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons (Call / WhatsApp)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _callPhone(supervisorPhone);
                        },
                        icon: const Icon(Icons.phone_in_talk_rounded),
                        label: Text(
                          'اتصال الآن',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          foregroundColor: Colors.green.shade800,
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _openWhatsApp(supervisorPhone, delegateName);
                        },
                        icon: const Icon(Icons.chat_rounded, color: Colors.green),
                        label: Text(
                          'واتساب',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Empty state for supervisor phone
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.phone_disabled_rounded,
                        size: 40,
                        color: colorScheme.error.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'لا يوجد رقم هاتف مسجل لمشرف هذا المندوب',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (companyName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'شركة: $companyName',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone, String delegateName) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final message = Uri.encodeComponent('مرحباً، بخصوص المندوب: $delegateName');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$message');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ─── Open Attendance History ───────────────────────────────────────────────
  void _openAttendanceHistory(BuildContext context, Map<String, dynamic> record) {
    final delegateData = record['delegateData'] as Map<String, dynamic>?;
    final delegateId = record['delegateId'] as String? ?? '';
    if (delegateId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات للمندوب')),
      );
      return;
    }
    try {
      final safeData = Map<String, dynamic>.from(delegateData ?? {});
      safeData.putIfAbsent('uid', () => delegateId);
      safeData.putIfAbsent('fullName', () => record['fullName'] ?? 'مندوب');
      safeData.putIfAbsent('phoneNumber', () => record['phoneNumber'] ?? '');
      safeData.putIfAbsent('companyName', () => record['companyName'] ?? '');
      safeData.putIfAbsent('companyUID', () => record['companyUID'] ?? '');
      final effectiveOrg = widget.marketingUser.organizationUID.isNotEmpty
          ? widget.marketingUser.organizationUID
          : (record['organizationId'] as String? ?? 'PiioBFgxaHAeuRdjlDgj');
      safeData['organizationUID'] = effectiveOrg;
      safeData.putIfAbsent('status', () => 'Active');
      safeData.putIfAbsent('role', () => 'delegate');

      final delegate = DelegateModel.fromJson(safeData, delegateId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceScreen(delegate: delegate, viewOnly: true),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح سجل الحضور')),
      );
    }
  }

  // ─── Image Preview (تكبير الصورة) ──────────────────────────────────────────
  void _showImagePreview(
    BuildContext context,
    String imageUrl,
    String name,
    String company,
  ) {
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
              // Header with name & close button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (company.isNotEmpty)
                            Text(
                              company,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Image Container with InteractiveViewer (pinch & zoom)
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.65,
                      maxWidth: double.infinity,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'تعذّر عرض الصورة',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Branch Picker ─────────────────────────────────────────────────────────
  void _showBranchPicker(BuildContext context) {
    final bloc = context.read<MarketingBloc>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BranchPickerBottomSheet(
        userId: widget.marketingUser.uid,
        organizationId: widget.marketingUser.organizationUID,
        currentFavorites: _favoriteBranches,
        onBranchSelected: (branchName) {
          bloc.add(AddFavoriteBranch(
            userId: widget.marketingUser.uid,
            branchName: branchName,
          ));
        },
      ),
    );
  }

  // ─── Remove Branch ─────────────────────────────────────────────────────────
  void _confirmRemoveBranch(BuildContext context, String branchName) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.delete_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              const Text('حذف الفرع'),
            ],
          ),
          content: Text('هل تريد إزالة "$branchName" من قائمة فروعك المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                final bloc = context.read<MarketingBloc>();
                bloc.add(RemoveFavoriteBranch(
                  userId: widget.marketingUser.uid,
                  branchName: branchName,
                ));
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton loading card
// ─────────────────────────────────────────────────────────────────────────────
class _BranchSectionSkeleton extends StatelessWidget {
  final String branchName;
  final ColorScheme colorScheme;
  const _BranchSectionSkeleton({
    required this.branchName,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header skeleton
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_rounded,
                  color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                branchName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        // Body skeleton
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          height: 80,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Branch Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class BranchPickerBottomSheet extends StatefulWidget {
  final String userId;
  final String organizationId;
  final List<String> currentFavorites;
  final void Function(String branchName) onBranchSelected;

  const BranchPickerBottomSheet({
    super.key,
    required this.userId,
    required this.organizationId,
    required this.currentFavorites,
    required this.onBranchSelected,
  });

  @override
  State<BranchPickerBottomSheet> createState() =>
      _BranchPickerBottomSheetState();
}

class _BranchPickerBottomSheetState extends State<BranchPickerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allBranches = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final snapshot = await di.sl<FirebaseFirestore>()
          .collection('branches')
          .get();
      if (mounted) {
        final docs = snapshot.docs.map((d) {
          final data = d.data();
          final name = (data['branchName'] as String?) ??
              (data['name'] as String?) ??
              (data['title'] as String?) ??
              '';
          return {
            'id': d.id,
            'branchName': name,
          };
        }).where((b) => (b['branchName'] as String).isNotEmpty).toList();
        docs.sort((a, b) =>
            (a['branchName'] ?? '').compareTo(b['branchName'] ?? ''));
        setState(() {
          _allBranches = docs;
          _filtered = _allBranches;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'فشل في جلب الفروع';
          _loading = false;
        });
      }
    }
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allBranches
          : _allBranches
              .where((b) =>
                  (b['branchName'] as String? ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.add_location_alt_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'إضافة فرع',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'ابحث عن فرع...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                            const SizedBox(height: 8),
                            Text(_error!),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _loadBranches();
                              },
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : _filtered.isEmpty
                        ? const Center(child: Text('لا توجد فروع مطابقة'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _filtered.length,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemBuilder: (context, index) {
                              final branch = _filtered[index];
                              final name =
                                  branch['branchName'] as String? ?? 'فرع';
                              final isAlreadyAdded =
                                  widget.currentFavorites.contains(name);

                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isAlreadyAdded
                                        ? colorScheme.primaryContainer
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.store_rounded,
                                    color: isAlreadyAdded
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isAlreadyAdded
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: isAlreadyAdded
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'مضاف',
                                            style: TextStyle(
                                              color: colorScheme.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onTap: isAlreadyAdded
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        widget.onBranchSelected(name);
                                      },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
