import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/penalties/presentation/widgets/penalty_evidence_viewer.dart';
import 'package:delegate_app/features/penalties/presentation/utils/penalty_creator_helper.dart';
import 'admin_create_penalty_page.dart';

class AdminPenaltiesListPage extends StatefulWidget {
  final Delegate adminDelegate;
  final bool showAppBar;

  const AdminPenaltiesListPage({
    super.key,
    required this.adminDelegate,
    this.showAppBar = true,
  });

  @override
  State<AdminPenaltiesListPage> createState() => _AdminPenaltiesListPageState();
}

class _AdminPenaltiesListPageState extends State<AdminPenaltiesListPage> {
  // Multi-branch selection state
  Set<String> _selectedBranchIds = {};
  Set<String> _pinnedBranchIds = {};
  List<Map<String, String>> _availableBranches = [];
  bool _isLoadingBranches = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // all, pending, issued, deducted, rejected

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBranchesAndPinned();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    if (widget.adminDelegate.role == UserRole.admin) {
      context.read<PenaltyBloc>().add(LoadCompanyPenaltiesEvent(widget.adminDelegate.companyUID));
    } else {
      context.read<PenaltyBloc>().add(const LoadAllPenaltiesEvent());
    }
  }

  Future<void> _loadBranchesAndPinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyMulti = 'pinned_penalty_branch_ids_${widget.adminDelegate.uid}';
      final keySingle = 'pinned_penalty_branch_id_${widget.adminDelegate.uid}';

      List<String>? savedList = prefs.getStringList(keyMulti);
      if (savedList == null || savedList.isEmpty) {
        final single = prefs.getString(keySingle);
        if (single != null && single.isNotEmpty && single != 'all') {
          savedList = [single];
        }
      }

      final snapshot = await FirebaseFirestore.instance.collection('branches').get();
      if (!mounted) return;

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        final name = (data['branchName'] as String?) ??
            (data['name'] as String?) ??
            (data['title'] as String?) ??
            doc.id;
        return {
          'id': doc.id,
          'name': name,
        };
      }).toList();
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      final pinnedSet = <String>{};
      if (savedList != null) {
        for (final id in savedList) {
          if (list.any((b) => b['id'] == id)) {
            pinnedSet.add(id);
          }
        }
      }

      setState(() {
        _availableBranches = list;
        _pinnedBranchIds = pinnedSet;
        if (pinnedSet.isNotEmpty) {
          _selectedBranchIds = Set.from(pinnedSet);
        } else {
          _selectedBranchIds = {}; // empty represents all branches
        }
        _isLoadingBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBranches = false;
      });
    }
  }

  bool get _isCurrentSelectionPinned {
    if (_selectedBranchIds.isEmpty) return false;
    return _selectedBranchIds.length == _pinnedBranchIds.length &&
        _selectedBranchIds.containsAll(_pinnedBranchIds);
  }

  Future<void> _togglePinCurrentBranches() async {
    if (_selectedBranchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد فرع أو أكثر من نافذة الفروع لتثبيتها كقطاع افتراضي'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final keyMulti = 'pinned_penalty_branch_ids_${widget.adminDelegate.uid}';
    final keySingle = 'pinned_penalty_branch_id_${widget.adminDelegate.uid}';

    if (_isCurrentSelectionPinned) {
      // Unpin
      await prefs.remove(keyMulti);
      await prefs.remove(keySingle);
      if (!mounted) return;
      setState(() {
        _pinnedBranchIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء تثبيت القطاع الافتراضي للفروع'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Pin
      final listToSave = _selectedBranchIds.toList();
      await prefs.setStringList(keyMulti, listToSave);
      if (listToSave.isNotEmpty) {
        await prefs.setString(keySingle, listToSave.first);
      }
      if (!mounted) return;
      setState(() {
        _pinnedBranchIds = Set.from(_selectedBranchIds);
      });

      final branchCount = _selectedBranchIds.length;
      final msg = branchCount == 1
          ? '📌 تم تثبيت الفرع المختار كفرع افتراضي لسجل المخالفات'
          : '📌 تم تثبيت ($branchCount فروع) كقطاع افتراضي لسجل المخالفات';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openMultiBranchPickerSheet() {
    final tempSelection = Set<String>.from(_selectedBranchIds);
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final query = searchController.text.trim().toLowerCase();

            final filteredBranches = _availableBranches.where((b) {
              if (query.isEmpty) return true;
              return (b['name'] ?? '').toLowerCase().contains(query);
            }).toList();

            final selectedCount = tempSelection.length;
            final isAllSelected = tempSelection.isEmpty ||
                (tempSelection.length == _availableBranches.length &&
                    _availableBranches.isNotEmpty);

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.hub_rounded, color: colorScheme.primary, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تحديد فروع العرض (قطاع الفروع)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                selectedCount == 0
                                    ? 'يتم عرض جميع الفروع حالياً'
                                    : 'تم تحديد $selectedCount فرع للفلترة',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selectedCount > 0)
                          TextButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                tempSelection.clear();
                              });
                            },
                            icon: const Icon(Icons.clear_all_rounded, size: 18),
                            label: const Text('مسح التحديد'),
                          ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Search + Quick Actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: searchController,
                          onChanged: (_) => setSheetState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'بحث باسم الفرع...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      searchController.clear();
                                      setSheetState(() {});
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ActionChip(
                              avatar: Icon(
                                isAllSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 16,
                                color: isAllSelected ? colorScheme.primary : null,
                              ),
                              label: const Text('جميع الفروع (الكل)', style: TextStyle(fontSize: 12)),
                              backgroundColor: isAllSelected
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHigh,
                              onPressed: () {
                                setSheetState(() {
                                  tempSelection.clear();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.select_all_rounded, size: 16),
                              label: const Text('تحديد الكل', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setSheetState(() {
                                  tempSelection.clear();
                                  for (final b in _availableBranches) {
                                    tempSelection.add(b['id']!);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Branches List
                  Expanded(
                    child: filteredBranches.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد فروع مطابقة للبحث',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredBranches.length,
                            itemBuilder: (context, index) {
                              final b = filteredBranches[index];
                              final branchId = b['id']!;
                              final branchName = b['name'] ?? '';
                              final isChecked = tempSelection.contains(branchId);
                              final isPinned = _pinnedBranchIds.contains(branchId);

                              return CheckboxListTile(
                                value: isChecked,
                                activeColor: colorScheme.primary,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        branchName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight:
                                              isChecked ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isPinned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'ضمن الافتراضي 📌',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  'كود: $branchId',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  ),
                                ),
                                onChanged: (val) {
                                  setSheetState(() {
                                    if (val == true) {
                                      tempSelection.add(branchId);
                                    } else {
                                      tempSelection.remove(branchId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),

                  // Bottom Action Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              setState(() {
                                _selectedBranchIds = Set.from(tempSelection);
                              });
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(
                              tempSelection.isEmpty
                                  ? 'تأكيد (عرض جميع الفروع)'
                                  : 'تأكيد الفلترة (${tempSelection.length} فروع)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
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

  Future<void> _confirmAndDeletePenalty(
    BuildContext context,
    PenaltyEntity penalty,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تأكيد حذف المخالفة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف المخالفة "${penalty.title}" نهائياً؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<PenaltyBloc>().add(DeletePenaltyEvent(penalty.penaltyId));
    }
  }

  List<PenaltyEntity> _filterPenalties(List<PenaltyEntity> all) {
    return all.where((p) {
      // 1. Multi-Branch filter
      if (_selectedBranchIds.isNotEmpty && !_selectedBranchIds.contains('all')) {
        final matchesBranchId = p.branchId != null && _selectedBranchIds.contains(p.branchId);
        final matchesBranchName = p.branchName != null &&
            _availableBranches.any((b) =>
                _selectedBranchIds.contains(b['id']) && b['name'] == p.branchName);
        if (!matchesBranchId && !matchesBranchName) {
          return false;
        }
      }

      // 2. Status filter
      if (_selectedStatusFilter != 'all') {
        switch (_selectedStatusFilter) {
          case 'pending':
            final isPending = p.status == PenaltyStatus.pendingBranchesMarketing ||
                p.status == PenaltyStatus.pendingGeneralManager;
            if (!isPending) return false;
            break;
          case 'issued':
            final isIssued = p.status == PenaltyStatus.issued ||
                p.status == PenaltyStatus.acknowledged;
            if (!isIssued) return false;
            break;
          case 'deducted':
            if (p.status != PenaltyStatus.deducted) return false;
            break;
          case 'rejected':
            final isRejected = p.status == PenaltyStatus.rejectedByBranchesMarketing ||
                p.status == PenaltyStatus.rejectedByGeneralManager ||
                p.status == PenaltyStatus.cancelled;
            if (!isRejected) return false;
            break;
        }
      }

      // 3. Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = p.title.toLowerCase().contains(q);
        final matchCompany = p.companyName.toLowerCase().contains(q);
        final matchBranch = (p.branchName ?? '').toLowerCase().contains(q);
        final matchDelegate = (p.targetDelegateName ?? '').toLowerCase().contains(q);
        final matchCreator = p.createdByName.toLowerCase().contains(q);
        final matchDesc = p.incidentDescription.toLowerCase().contains(q);
        if (!matchTitle &&
            !matchCompany &&
            !matchBranch &&
            !matchDelegate &&
            !matchCreator &&
            !matchDesc) {
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

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'سجل المخالفات والغرامات',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  tooltip: 'تحديث البيانات',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    _loadData();
                    _loadBranchesAndPinned();
                  },
                ),
              ],
            )
          : null,
      floatingActionButton: widget.adminDelegate.role == UserRole.admin
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final res = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<PenaltyBloc>(),
                      child: AdminCreatePenaltyPage(
                        adminDelegate: widget.adminDelegate,
                      ),
                    ),
                  ),
                );
                if (res == true) {
                  _loadData();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسجيل غرامة جديدة'),
            ),
      body: Column(
        children: [
          // 1. Top Multi-Branch & Filter Section
          _buildFilterHeader(context, colorScheme),

          // 2. Main List Body
          Expanded(
            child: BlocConsumer<PenaltyBloc, PenaltyState>(
              listener: (context, state) {
                if (state is PenaltyActionSuccessState) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  _loadData();
                } else if (state is PenaltyErrorState) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is PenaltyLoadingState) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is PenaltyErrorState) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 54, color: colorScheme.error),
                          const SizedBox(height: 12),
                          Text(
                            state.message,
                            style: TextStyle(color: colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is PenaltyLoadedState) {
                  final filteredList = _filterPenalties(state.penalties);

                  // Statistics summary calculations
                  final totalCount = filteredList.length;
                  final totalFines = filteredList.fold<double>(
                    0.0,
                    (acc, item) => acc + item.fineAmount,
                  );
                  final pendingCount = filteredList.where((p) =>
                      p.status == PenaltyStatus.pendingBranchesMarketing ||
                      p.status == PenaltyStatus.pendingGeneralManager).length;

                  return Column(
                    children: [
                      // Statistics Summary Card
                      _buildStatsBar(colorScheme, totalCount, totalFines, pendingCount),

                      // List of cards
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            _loadData();
                            await _loadBranchesAndPinned();
                          },
                          child: filteredList.isEmpty
                              ? SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: Container(
                                    height: MediaQuery.of(context).size.height * 0.45,
                                    alignment: Alignment.center,
                                    child: _buildEmptyState(theme, colorScheme),
                                  ),
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 85),
                                  itemCount: filteredList.length,
                                  itemBuilder: (context, index) {
                                    final p = filteredList[index];
                                    return _AdminPenaltyCard(
                                      penalty: p,
                                      currentDelegate: widget.adminDelegate,
                                      isReadOnly: widget.adminDelegate.role == UserRole.admin,
                                      onStatusChanged: (newStatus) {
                                        context.read<PenaltyBloc>().add(
                                              UpdatePenaltyStatusEvent(
                                                penaltyId: p.penaltyId,
                                                status: newStatus,
                                              ),
                                            );
                                      },
                                      onDelete: () => _confirmAndDeletePenalty(context, p),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  );
                }

                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context, ColorScheme colorScheme) {
    final isPinned = _isCurrentSelectionPinned;
    final selectedCount = _selectedBranchIds.length;

    String branchLabel;
    if (selectedCount == 0) {
      branchLabel = 'جميع الفروع (الكل)';
    } else if (selectedCount == 1) {
      final singleId = _selectedBranchIds.first;
      final match = _availableBranches.firstWhere(
        (b) => b['id'] == singleId,
        orElse: () => {'name': singleId},
      );
      branchLabel = match['name'] ?? singleId;
    } else {
      branchLabel = 'قطاع محدد: ($selectedCount فروع)';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Multi-Branch Selector Bar + Default Pin Action
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _isLoadingBranches ? null : _openMultiBranchPickerSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPinned
                            ? Colors.teal.shade600
                            : colorScheme.outlineVariant.withValues(alpha: 0.6),
                        width: isPinned ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 20,
                          color: isPinned ? Colors.teal.shade700 : colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                branchLabel,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isPinned)
                                Text(
                                  'القطاع الافتراضي المثبت 📌',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Pin / Default Button
              IconButton.filledTonal(
                tooltip: isPinned
                    ? 'إلغاء تثبيت القطاع الافتراضي'
                    : 'تثبيت الفروع المحددة كقطاع افتراضي عند الفتح',
                style: IconButton.styleFrom(
                  backgroundColor: isPinned
                      ? Colors.teal.shade100
                      : colorScheme.surfaceContainerHigh,
                  foregroundColor: isPinned
                      ? Colors.teal.shade900
                      : colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isPinned
                          ? Colors.teal.shade600
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                icon: Icon(
                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 20,
                  color: isPinned ? Colors.teal.shade700 : null,
                ),
                onPressed: _togglePinCurrentBranches,
              ),
              const SizedBox(width: 8),
              // Refresh Button (زرار التحديث السريع للغرامات)
              IconButton.filledTonal(
                tooltip: 'تحديث بيانات وسجلات الغرامات',
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                ),
                onPressed: () {
                  _loadData();
                  _loadBranchesAndPinned();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تحديث بيانات وسجلات الغرامات بنجاح 🔄'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),

          // 2. Selected Branch Active Chips Row (Horizontal Scroll)
          if (_selectedBranchIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._selectedBranchIds.map((branchId) {
                    final branchObj = _availableBranches.firstWhere(
                      (b) => b['id'] == branchId,
                      orElse: () => {'name': branchId},
                    );
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Chip(
                        avatar: Icon(Icons.location_on_outlined, size: 14, color: colorScheme.primary),
                        label: Text(
                          branchObj['name'] ?? branchId,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        onDeleted: () {
                          setState(() {
                            _selectedBranchIds.remove(branchId);
                          });
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        backgroundColor: colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ActionChip(
                      label: const Text('عرض الكل', style: TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () {
                        setState(() {
                          _selectedBranchIds.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // 3. Search Box
          TextFormField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'بحث باسم المندوب، الشركة، أو المخالفة...',
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 4. Quick Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('الكل', 'all', colorScheme),
                const SizedBox(width: 6),
                _buildStatusChip('بانتظار الموافقة ⏳', 'pending', colorScheme),
                const SizedBox(width: 6),
                _buildStatusChip('معتمدة ومحررة ✅', 'issued', colorScheme),
                const SizedBox(width: 6),
                _buildStatusChip('تم الخصم 💸', 'deducted', colorScheme),
                const SizedBox(width: 6),
                _buildStatusChip('مرفوضة / ملغاة ❌', 'rejected', colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String key, ColorScheme colorScheme) {
    final isSelected = _selectedStatusFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        ),
      ),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() => _selectedStatusFilter = key);
        }
      },
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }

  Widget _buildStatsBar(
    ColorScheme colorScheme,
    int totalCount,
    double totalFines,
    int pendingCount,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('العدد', '$totalCount', Icons.receipt_long_rounded, colorScheme.primary),
          Container(
            height: 24,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          _buildStatItem(
            'الإجمالي',
            '${totalFines.toStringAsFixed(0)} ج.م',
            Icons.monetization_on_outlined,
            Colors.red.shade700,
          ),
          Container(
            height: 24,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          _buildStatItem(
            'بانتظار الإجراء',
            '$pendingCount',
            Icons.hourglass_top_rounded,
            pendingCount > 0 ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: valueColor),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 54,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مخالفات مطابقة لخيارات الفلترة الحالية',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'جرّب تعديل الفروع المختارة أو إزالة شروط البحث لتصفح باقي السجلات',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPenaltyCard extends StatefulWidget {
  final PenaltyEntity penalty;
  final Delegate currentDelegate;
  final bool isReadOnly;
  final ValueChanged<PenaltyStatus> onStatusChanged;
  final VoidCallback? onDelete;

  const _AdminPenaltyCard({
    required this.penalty,
    required this.currentDelegate,
    required this.isReadOnly,
    required this.onStatusChanged,
    this.onDelete,
  });

  @override
  State<_AdminPenaltyCard> createState() => _AdminPenaltyCardState();
}

class _AdminPenaltyCardState extends State<_AdminPenaltyCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    final requiresAction = (widget.currentDelegate.role == UserRole.branchesMarketingManager &&
            widget.penalty.status == PenaltyStatus.pendingBranchesMarketing) ||
        ((widget.currentDelegate.role == UserRole.organizationAdmin ||
                widget.currentDelegate.role == UserRole.superAdmin) &&
            widget.penalty.status == PenaltyStatus.pendingGeneralManager);
    _isExpanded = requiresAction;
  }

  Color _getStatusColor(PenaltyStatus status) {
    switch (status) {
      case PenaltyStatus.pendingBranchesMarketing:
        return Colors.orange.shade800;
      case PenaltyStatus.rejectedByBranchesMarketing:
        return Colors.red.shade800;
      case PenaltyStatus.pendingGeneralManager:
        return Colors.amber.shade900;
      case PenaltyStatus.rejectedByGeneralManager:
        return Colors.red.shade900;
      case PenaltyStatus.issued:
        return Colors.green.shade700;
      case PenaltyStatus.acknowledged:
        return Colors.blue.shade700;
      case PenaltyStatus.deducted:
        return Colors.teal.shade700;
      case PenaltyStatus.disputed:
        return Colors.purple.shade700;
      case PenaltyStatus.cancelled:
        return Colors.grey.shade600;
    }
  }

  Future<void> _callCreator(BuildContext context, PenaltyEntity penalty) async {
    await PenaltyCreatorHelper.callCreator(context, penalty);
  }

  Future<void> _editPenalty(BuildContext context, PenaltyEntity penalty) async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<PenaltyBloc>(),
          child: AdminCreatePenaltyPage(
            adminDelegate: widget.currentDelegate,
            penaltyToEdit: penalty,
          ),
        ),
      ),
    );
    if (res == true) {
      if (context.mounted) {
        if (widget.currentDelegate.role == UserRole.admin) {
          context.read<PenaltyBloc>().add(LoadCompanyPenaltiesEvent(widget.currentDelegate.companyUID));
        } else {
          context.read<PenaltyBloc>().add(const LoadAllPenaltiesEvent());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor(widget.penalty.status);
    final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(widget.penalty.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Status badge, Company badge, Branch badge, Fine amount, Chevron
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            widget.penalty.status.displayName,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // Company Badge
                        if (widget.penalty.companyName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.penalty.companyName,
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ),

                        // Branch Badge (if available)
                        if (widget.penalty.branchName != null &&
                            widget.penalty.branchName!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.storefront_rounded,
                                  size: 11,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  widget.penalty.branchName!,
                                  style: TextStyle(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (widget.penalty.isRepeated)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'مكررة',
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Fine Amount
                  Text(
                    '${widget.penalty.fineAmount.toStringAsFixed(0)} ج.م',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Animated Arrow
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Title: Elegant, readable, well-proportioned font size (13.5)
              Text(
                widget.penalty.title,
                maxLines: _isExpanded ? null : 2,
                overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 4),

              // Category tag line + Target delegate
              Row(
                children: [
                  Text(
                    widget.penalty.category.displayName,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.penalty.targetDelegateName != null &&
                      widget.penalty.targetDelegateName!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 12, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            widget.penalty.targetDelegateName!,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              // Expanded Details Section
              if (_isExpanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                if (widget.penalty.incidentDescription.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل الواقعة / الملاحظات:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.penalty.incidentDescription,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Attachments / Evidence Section
                if (widget.penalty.evidenceFiles.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.attach_file_rounded,
                              size: 15,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'المرفقات والمستندات (${widget.penalty.evidenceFiles.length})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'اضغط للمعاينة والتكبير',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.penalty.evidenceFiles.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final file = entry.value;
                            final isImage = file.fileType.toUpperCase() == 'IMAGE' ||
                                file.fileType.toUpperCase() == 'IMG' ||
                                file.fileName.toLowerCase().endsWith('.jpg') ||
                                file.fileName.toLowerCase().endsWith('.jpeg') ||
                                file.fileName.toLowerCase().endsWith('.png') ||
                                file.fileName.toLowerCase().endsWith('.webp');

                            return InkWell(
                              onTap: () {
                                if (isImage) {
                                  PenaltyEvidenceViewer.showImageLightbox(
                                    context,
                                    imageUrl: file.fileUrl,
                                    title: widget.penalty.title,
                                    subtitle:
                                        '${widget.penalty.companyName} (${idx + 1}/${widget.penalty.evidenceFiles.length})',
                                    fileName: file.fileName,
                                  );
                                } else {
                                  PenaltyEvidenceViewer.showEvidence(
                                    context,
                                    penalty: widget.penalty,
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: isImage
                                            ? CachedNetworkImage(
                                                imageUrl: file.fileUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Center(
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                                errorWidget: (context, url, err) => Center(
                                                  child: Icon(
                                                    Icons.broken_image_rounded,
                                                    size: 24,
                                                    color: colorScheme.error,
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      file.fileType == 'PDF'
                                                          ? Icons.picture_as_pdf_rounded
                                                          : Icons.insert_drive_file_rounded,
                                                      color: colorScheme.primary,
                                                      size: 26,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      file.fileType,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: colorScheme.primary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (isImage)
                                      Positioned(
                                        top: 3,
                                        right: 3,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.55),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in_rounded,
                                            size: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.attach_file_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'لا توجد مستندات أو صور مرفقة بهذه المخالفة',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Metadata Row
                Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'المحرر: ${widget.penalty.createdByName}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _callCreator(context, widget.penalty),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_in_talk_rounded, size: 11, color: Colors.green.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'اتصال',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.schedule_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Action / Evidence Row
                Row(
                  children: [
                    if (!widget.isReadOnly &&
                        (widget.currentDelegate.role == UserRole.superAdmin ||
                            widget.currentDelegate.role == UserRole.organizationAdmin))
                      Flexible(
                        child: PopupMenuButton<PenaltyStatus>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tooltip: 'تغيير حالة المخالفة',
                          onSelected: widget.onStatusChanged,
                          itemBuilder: (context) => PenaltyStatus.values.map((st) {
                            return PopupMenuItem(
                              value: st,
                              child: Text(st.displayName, style: const TextStyle(fontSize: 12.5)),
                            );
                          }).toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.penalty.status.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down_rounded, size: 18, color: statusColor),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(width: 6),

                    // Call creator action button
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                        foregroundColor: Colors.green.shade700,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.phone_forwarded_rounded, size: 18),
                      tooltip: 'اتصال بمحرر المخالفة (${widget.penalty.createdByName})',
                      onPressed: () => _callCreator(context, widget.penalty),
                    ),

                    if (!widget.isReadOnly &&
                        (widget.currentDelegate.role == UserRole.superAdmin ||
                            widget.currentDelegate.role == UserRole.organizationAdmin ||
                            widget.currentDelegate.role == UserRole.branchesMarketingManager ||
                            widget.penalty.createdById == widget.currentDelegate.uid)) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          foregroundColor: Colors.blue.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 20),
                        tooltip: 'تعديل بيانات ومستندات الغرامة',
                        onPressed: () => _editPenalty(context, widget.penalty),
                      ),
                    ],

                    if (!widget.isReadOnly && widget.onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          foregroundColor: Colors.red.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        tooltip: 'حذف المخالفة',
                        onPressed: widget.onDelete,
                      ),
                    ],

                    const Spacer(),

                    if (widget.penalty.evidenceFiles.isNotEmpty)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => PenaltyEvidenceViewer.showEvidence(
                          context,
                          penalty: widget.penalty,
                        ),
                        icon: const Icon(Icons.attach_file_rounded, size: 15),
                        label: Text(
                          'المستندات (${widget.penalty.evidenceFiles.length})',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
                ),

                // Approvals by Branches Marketing Manager
                if (widget.currentDelegate.role == UserRole.branchesMarketingManager &&
                    widget.penalty.status == PenaltyStatus.pendingBranchesMarketing) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final isDirectApproval = widget.penalty.fineAmount <= 1000.0;
                              final nextStatus = isDirectApproval
                                  ? PenaltyStatus.issued
                                  : PenaltyStatus.pendingGeneralManager;
                              context.read<PenaltyBloc>().add(
                                    UpdatePenaltyStatusEvent(
                                      penaltyId: widget.penalty.penaltyId,
                                      status: nextStatus,
                                      reviewerName: widget.currentDelegate.fullName,
                                    ),
                                  );
                            },
                            icon: Icon(
                              widget.penalty.fineAmount <= 1000.0
                                  ? Icons.verified_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                            label: Text(
                              widget.penalty.fineAmount <= 1000.0
                                  ? 'اعتماد فوري (≤ 1000 ج.م)'
                                  : 'تمرير للمدير العام (> 1000 ج.م)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.errorContainer,
                              foregroundColor: colorScheme.onErrorContainer,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () => _showRejectionDialog(
                              context,
                              PenaltyStatus.rejectedByBranchesMarketing,
                            ),
                            icon: const Icon(Icons.cancel_rounded, size: 16),
                            label: const Text(
                              'رفض المخالفة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showRejectionDialog(BuildContext context, PenaltyStatus rejectStatus) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب رفض المخالفة', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'أدخل سبب رفض المخالفة...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              context.read<PenaltyBloc>().add(
                    UpdatePenaltyStatusEvent(
                      penaltyId: widget.penalty.penaltyId,
                      status: rejectStatus,
                      rejectionReason: reason,
                      reviewerName: widget.currentDelegate.fullName,
                    ),
                  );
            },
            child: const Text('تأكيد الرفض', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
