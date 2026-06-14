import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// الشاشة الرئيسية للفروع - تعرض جميع الفروع المفضلة في نفس الصفحة
class BranchHomeScreen extends StatelessWidget {
  final Delegate marketingUser;

  const BranchHomeScreen({super.key, required this.marketingUser});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<MarketingBloc>()
            ..add(LoadBranchPreferences(userId: marketingUser.uid)),
      child: _BranchHomeView(marketingUser: marketingUser),
    );
  }
}

class _BranchHomeView extends StatefulWidget {
  final Delegate marketingUser;
  const _BranchHomeView({required this.marketingUser});

  @override
  State<_BranchHomeView> createState() => _BranchHomeViewState();
}

class _BranchHomeViewState extends State<_BranchHomeView> {
  List<String> _favoriteBranches = [];
  bool _prefsLoaded = false;

  void _loadAllBranches(BuildContext context, List<String> favorites) {
    if (favorites.isEmpty) return;
    context.read<MarketingBloc>().add(
      LoadAllFavoriteBranchesAttendance(
        favoriteBranches: favorites,
        organizationId: widget.marketingUser.organizationUID,
      ),
    );
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

        return Stack(
          children: [
            body,
            // ─── FAB: إضافة فرع ───────────────────────────────────────────
            Positioned(
              bottom: 16,
              left: 16,
              child: FloatingActionButton.extended(
                heroTag: 'add_branch_fab',
                onPressed: () => _showBranchPicker(context),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('إضافة فرع'),
                elevation: 3,
              ),
            ),
          ],
        );
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
              Icons.store_mall_directory_outlined,
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
            icon: const Icon(Icons.add_location_alt_outlined),
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
          Icon(Icons.error_outline, size: 56, color: colorScheme.error),
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
    final today = DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async => _loadAllBranches(context, _favoriteBranches),
      child: CustomScrollView(
        slivers: [
          // ─── تاريخ اليوم ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    today,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Branch Header ──
          GestureDetector(
            onLongPress: () => _confirmRemoveBranch(context, branchName),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      '${records.length} مندوب',
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Delegates List ──
          if (records.isEmpty)
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
                    Icons.people_outline_rounded,
                    color: colorScheme.outlineVariant,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لا يوجد حضور اليوم',
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
                children: records.asMap().entries.map((entry) {
                  final isLast = entry.key == records.length - 1;
                  return Column(
                    children: [
                      _buildDelegateRow(context, entry.value, colorScheme),
                      if (!isLast)
                        Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
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
    final checkIn = record['checkInTime'] as Timestamp?;
    final checkOut = record['checkOutTime'] as Timestamp?;
    final bool hasCheckOut = checkOut != null;

    final checkInStr = checkIn != null
        ? DateFormat('hh:mm a', 'ar').format(checkIn.toDate())
        : '--:--';
    final checkOutStr = checkOut != null
        ? DateFormat('hh:mm a', 'ar').format(checkOut.toDate())
        : '--:--';

    return InkWell(
      onTap: () => _openAttendanceHistory(context, record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: hasCheckOut
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.primaryContainer,
              child: Text(
                fullName.isNotEmpty ? fullName[0] : '؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: hasCheckOut
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onPrimaryContainer,
                ),
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
            Icon(
              Icons.chevron_left_rounded,
              color: colorScheme.outline,
              size: 18,
            ),
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

  // ─── Open Attendance History ───────────────────────────────────────────────
  void _openAttendanceHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final delegateData = record['delegateData'] as Map<String, dynamic>?;
    final delegateId = record['delegateId'] as String? ?? '';
    if (delegateData == null || delegateId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات كاملة للمندوب')),
      );
      return;
    }
    try {
      final delegate = DelegateModel.fromJson(delegateData, delegateId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceScreen(delegate: delegate, viewOnly: true),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّر فتح سجل الحضور')));
    }
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
          bloc.add(
            AddFavoriteBranch(
              userId: widget.marketingUser.uid,
              branchName: branchName,
            ),
          );
          // أعد تحميل كل الفروع بعد الإضافة
          final newFavorites = [..._favoriteBranches, branchName];
          bloc.add(
            LoadAllFavoriteBranchesAttendance(
              favoriteBranches: newFavorites,
              organizationId: widget.marketingUser.organizationUID,
            ),
          );
        },
      ),
    );
  }

  // ─── Remove Branch ─────────────────────────────────────────────────────────
  void _confirmRemoveBranch(BuildContext context, String branchName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الفرع'),
        content: Text('هل تريد حذف "$branchName" من قائمتك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final bloc = context.read<MarketingBloc>();
              bloc.add(
                RemoveFavoriteBranch(
                  userId: widget.marketingUser.uid,
                  branchName: branchName,
                ),
              );
              final newFavorites = _favoriteBranches
                  .where((b) => b != branchName)
                  .toList();
              if (newFavorites.isNotEmpty) {
                bloc.add(
                  LoadAllFavoriteBranchesAttendance(
                    favoriteBranches: newFavorites,
                    organizationId: widget.marketingUser.organizationUID,
                  ),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
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
              Icon(
                Icons.location_on_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
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
      final snapshot = await di
          .sl<FirebaseFirestore>()
          .collection('branches')
          .orderBy('branchName')
          .get();
      if (mounted) {
        setState(() {
          _allBranches = snapshot.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
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
                .where(
                  (b) => (b['branchName'] as String? ?? '')
                      .toLowerCase()
                      .contains(q),
                )
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
                Icon(
                  Icons.add_location_alt_rounded,
                  color: colorScheme.primary,
                ),
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
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
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
                        const Icon(Icons.error_outline, size: 48),
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
                      final name = branch['branchName'] as String? ?? 'فرع';
                      final isAlreadyAdded = widget.currentFavorites.contains(
                        name,
                      );

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
