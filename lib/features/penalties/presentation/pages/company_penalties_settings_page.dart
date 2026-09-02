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
import 'package:delegate_app/features/penalties/presentation/pages/admin_create_penalty_page.dart';

class CompanyPenaltiesSettingsPage extends StatefulWidget {
  final Delegate delegate;
  /// إظهار AppBar المخصص للصفحة (false عند الاستخدام داخل AdminMainScreen)
  final bool showAppBar;

  const CompanyPenaltiesSettingsPage({
    super.key,
    required this.delegate,
    this.showAppBar = false,
  });

  @override
  State<CompanyPenaltiesSettingsPage> createState() =>
      _CompanyPenaltiesSettingsPageState();
}

class _CompanyPenaltiesSettingsPageState
    extends State<CompanyPenaltiesSettingsPage> {
  String _selectedCompanyFilter = 'all';
  Set<String> _selectedBranchIds = {};
  Set<String> _pinnedBranchIds = {};
  List<Map<String, String>> _availableBranches = [];
  bool _isLoadingBranches = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBranchesAndPinned();
  }

  Future<void> _loadBranchesAndPinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyMulti = 'pinned_penalty_branch_ids_${widget.delegate.uid}';
      final keySingle = 'pinned_penalty_branch_id_${widget.delegate.uid}';

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
          _selectedBranchIds = {};
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
          content: Text('يرجى تحديد فرع أو أكثر لتثبيتها كقطاع افتراضي'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final keyMulti = 'pinned_penalty_branch_ids_${widget.delegate.uid}';
    final keySingle = 'pinned_penalty_branch_id_${widget.delegate.uid}';

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

      final count = _selectedBranchIds.length;
      final msg = count == 1
          ? '📌 تم تثبيت الفرع كفرع افتراضي لقسم الغرامات'
          : '📌 تم تثبيت ($count فروع) كقطاع افتراضي لقسم الغرامات';

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
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
                                _selectedCompanyFilter = 'all';
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

  void _loadData() {
    if (widget.delegate.role == UserRole.marketingPromotion) return;
    final canViewAll = widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.branchesMarketingManager ||
        widget.delegate.role == UserRole.marketing;
    if (canViewAll) {
      context.read<PenaltyBloc>().add(const LoadAllPenaltiesEvent());
    } else {
      final companyId = widget.delegate.companyUID.isNotEmpty
          ? widget.delegate.companyUID
          : widget.delegate.organizationUID;
      context.read<PenaltyBloc>().add(LoadCompanyPenaltiesEvent(companyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.delegate.role == UserRole.marketingPromotion) {
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(title: const Text('قسم الغرامات والمخالفات'))
            : null,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'غير مسموح لحسابات تسويق العروض الوصول لنظام الغرامات والمخالفات',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canCreatePenalty = widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.marketing;
    final isOrgAdmin = widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'سجل المخالفات والغرامات',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'تحديث',
                  onPressed: () {
                    _loadData();
                    _loadBranchesAndPinned();
                  },
                ),
              ],
            )
          : null,
      floatingActionButton: canCreatePenalty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final res = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<PenaltyBloc>(),
                      child: AdminCreatePenaltyPage(
                        adminDelegate: widget.delegate,
                      ),
                    ),
                  ),
                );
                if (res == true) {
                  _loadData();
                  _loadBranchesAndPinned();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسجيل مخالفة'),
            )
          : null,
      body: BlocBuilder<PenaltyBloc, PenaltyState>(
        builder: (context, state) {
          if (state is PenaltyLoadingState) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is PenaltyErrorState) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 54, color: colorScheme.error),
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
            );
          }

          if (state is PenaltyLoadedState) {
            var penalties = state.penalties;

            // Multi-Branch Filter
            if (_selectedBranchIds.isNotEmpty && !_selectedBranchIds.contains('all')) {
              penalties = penalties.where((p) =>
                (p.branchId != null && _selectedBranchIds.contains(p.branchId)) ||
                (p.branchName != null &&
                    _availableBranches.any((b) =>
                        _selectedBranchIds.contains(b['id']) &&
                        b['name'] == p.branchName))
              ).toList();
            }

            // Group penalties by company name
            final Map<String, List<PenaltyEntity>> groupedByCompany = {};
            for (var p in penalties) {
              final compName =
                  p.companyName.isNotEmpty ? p.companyName : 'شركة غير محددة';
              groupedByCompany.putIfAbsent(compName, () => []).add(p);
            }

            // Recalculate totals for the filtered subset
            final filteredTotalFines =
                penalties.fold<double>(0.0, (total, p) => total + p.fineAmount);
            final filteredDeducted = penalties
                .where((p) => p.status == PenaltyStatus.deducted)
                .fold<double>(0.0, (total, p) => total + p.fineAmount);

            // Filtered entries according to selection chip
            final entriesToDisplay = _selectedCompanyFilter == 'all'
                ? groupedByCompany.entries.toList()
                : groupedByCompany.entries
                    .where((e) => e.key == _selectedCompanyFilter)
                    .toList();

            final isPinned = _isCurrentSelectionPinned;
            final selectedCount = _selectedBranchIds.length;

            String branchLabel;
            if (selectedCount == 0) {
              branchLabel = 'جميع الفروع (عرض شامل)';
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

            return CustomScrollView(
              slivers: [
                // 0. Multi-Branch Selector & Pin Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isPinned
                              ? Colors.teal.shade600
                              : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                color: isPinned ? Colors.teal.shade700 : colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'عرض مخالفات الفرع / القطاع:',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              IconButton.filledTonal(
                                tooltip: isPinned
                                    ? 'إلغاء تثبيت القطاع الافتراضي'
                                    : 'تثبيت الفروع المحددة كقطاع افتراضي',
                                style: IconButton.styleFrom(
                                  backgroundColor: isPinned
                                      ? Colors.teal.shade100
                                      : colorScheme.surface,
                                  foregroundColor: isPinned
                                      ? Colors.teal.shade900
                                      : colorScheme.onSurfaceVariant,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isPinned
                                          ? Colors.teal.shade600
                                          : colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                icon: Icon(
                                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                  size: 16,
                                  color: isPinned ? Colors.teal.shade700 : null,
                                ),
                                onPressed: _togglePinCurrentBranches,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _isLoadingBranches
                              ? const LinearProgressIndicator()
                              : InkWell(
                                  onTap: _openMultiBranchPickerSheet,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isPinned
                                            ? Colors.teal.shade600
                                            : colorScheme.outlineVariant.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                branchLabel,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
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
                          if (_selectedBranchIds.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ..._selectedBranchIds.map((branchId) {
                                    final bObj = _availableBranches.firstWhere(
                                      (b) => b['id'] == branchId,
                                      orElse: () => {'name': branchId},
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Chip(
                                        avatar: Icon(Icons.location_on_outlined,
                                            size: 13, color: colorScheme.primary),
                                        label: Text(
                                          bObj['name'] ?? branchId,
                                          style: const TextStyle(
                                              fontSize: 11, fontWeight: FontWeight.bold),
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
                        ],
                      ),
                    ),
                  ),
                ),

                // 1. Overall Summary Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.errorContainer,
                            colorScheme.surfaceContainerHighest,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: colorScheme.error,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedBranchIds.isNotEmpty
                                      ? 'ملخص الغرامات ($branchLabel)'
                                      : (isOrgAdmin
                                          ? 'ملخص غرامات ومخالفات الشركات'
                                          : 'ملخص الغرامات والمخالفات'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إجمالي الغرامات',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      filteredTotalFines.toStringAsFixed(2),
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: colorScheme.outlineVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'المخصوم',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      filteredDeducted.toStringAsFixed(2),
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isOrgAdmin) ...[
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: colorScheme.outlineVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'عدد الشركات',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${groupedByCompany.keys.length} شركة',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Filter Chips Row by Company
                if (isOrgAdmin && groupedByCompany.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تصفية حسب الشركة:',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: Text(
                                    'جميع الشركات (${penalties.length})',
                                    style: TextStyle(
                                      color: _selectedCompanyFilter == 'all'
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurface,
                                      fontWeight: _selectedCompanyFilter == 'all'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: _selectedCompanyFilter == 'all',
                                  selectedColor: colorScheme.primary,
                                  checkmarkColor: colorScheme.onPrimary,
                                  onSelected: (val) {
                                    if (val) {
                                      setState(
                                          () => _selectedCompanyFilter = 'all');
                                    }
                                  },
                                ),
                                ...groupedByCompany.entries.map((entry) {
                                  final compName = entry.key;
                                  final count = entry.value.length;
                                  final isSelected =
                                      _selectedCompanyFilter == compName;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ChoiceChip(
                                      label: Text(
                                        '$compName ($count)',
                                        style: TextStyle(
                                          color: isSelected
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: colorScheme.primary,
                                      checkmarkColor: colorScheme.onPrimary,
                                      onSelected: (val) {
                                        if (val) {
                                          setState(() =>
                                              _selectedCompanyFilter =
                                                  compName);
                                        }
                                      },
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                // 3. Company Breakdown Cards or Empty State
                if (penalties.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 64,
                            color: colorScheme.primary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isOrgAdmin
                                ? 'لا توجد مخالفات مسجلة على أية شركة بعد'
                                : 'لا توجد مخالفات مسجلة على هذه الشركة',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entriesToDisplay[index];
                          return _CompanyPenaltiesGroupCard(
                            companyName: entry.key,
                            penalties: entry.value,
                            currentDelegate: widget.delegate,
                          );
                        },
                        childCount: entriesToDisplay.length,
                      ),
                    ),
                  ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _PenaltyCard extends StatefulWidget {
  final PenaltyEntity penalty;
  final Delegate? currentDelegate;

  const _PenaltyCard({
    required this.penalty,
    this.currentDelegate,
  });

  @override
  State<_PenaltyCard> createState() => _PenaltyCardState();
}

class _PenaltyCardState extends State<_PenaltyCard> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    final requiresAction = (widget.currentDelegate?.role == UserRole.branchesMarketingManager &&
            widget.penalty.status == PenaltyStatus.pendingBranchesMarketing) ||
        ((widget.currentDelegate?.role == UserRole.organizationAdmin ||
                widget.currentDelegate?.role == UserRole.superAdmin) &&
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

  void _showRejectionDialog(BuildContext context, PenaltyStatus nextStatus) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'يرجى كتابة سبب رفض المخالفة...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<PenaltyBloc>().add(
                    UpdatePenaltyStatusEvent(
                      penaltyId: widget.penalty.penaltyId,
                      status: nextStatus,
                      rejectionReason: controller.text.trim(),
                      reviewerName: widget.currentDelegate?.fullName,
                    ),
                  );
            },
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
  }

  Future<void> _callCreator(BuildContext context, PenaltyEntity penalty) async {
    await PenaltyCreatorHelper.callCreator(context, penalty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor(widget.penalty.status);
    final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(widget.penalty.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Compact mode)
              Row(
                children: [
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.penalty.isRepeated) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'مخالفة مكررة',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    widget.penalty.fineAmount.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
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

              // Category tag line & Branch badge
              Row(
                children: [
                  Text(
                    widget.penalty.category.displayName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.penalty.branchName != null &&
                      widget.penalty.branchName!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 12,
                            color: colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            widget.penalty.branchName!,
                            style: TextStyle(
                              color: colorScheme.onSecondaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.penalty.targetDelegateName != null &&
                  widget.penalty.targetDelegateName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person_pin_rounded,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'المندوب المستهدف: ${widget.penalty.targetDelegateName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],

              // Expanded Section (Shows on Tap)
              if (_isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                if (widget.penalty.incidentDescription.isNotEmpty) ...[
                  Text(
                    'تفاصيل المخالفة:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.penalty.incidentDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Rejection Reason Notice
                if (widget.penalty.rejectionReason != null &&
                    widget.penalty.rejectionReason!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'سبب الرفض: ${widget.penalty.rejectionReason}',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                // Audit Trail Info
                if (widget.penalty.branchesMarketingApprovedBy != null) ...[
                  Text(
                    'موافقة مدير تسويق الفروع: ${widget.penalty.branchesMarketingApprovedBy}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (widget.penalty.generalManagerApprovedBy != null) ...[
                  Text(
                    'اعتماد المدير العام: ${widget.penalty.generalManagerApprovedBy}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                                  _showEvidenceSheet(context, widget.penalty);
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

                Row(
                  children: [
                    if (widget.penalty.createdByName.isNotEmpty) ...[
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
                    ],
                    Icon(Icons.calendar_today_rounded,
                        size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    if (widget.penalty.createdByName.isEmpty) const Spacer(),
                    if (widget.penalty.evidenceFiles.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _showEvidenceSheet(context, widget.penalty),
                        icon: const Icon(Icons.attach_file_rounded, size: 15),
                        label: Text(
                          'المستندات (${widget.penalty.evidenceFiles.length})',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),

                // Approval Action Buttons per Role
                if (widget.currentDelegate != null) ...[
                  // Phase 1: Branch Marketing Manager Approval
                  if (widget.currentDelegate!.role == UserRole.branchesMarketingManager &&
                      widget.penalty.status == PenaltyStatus.pendingBranchesMarketing) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(28),
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
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
                                        reviewerName: widget.currentDelegate!.fullName,
                                      ),
                                    );
                              },
                              icon: Icon(
                                widget.penalty.fineAmount <= 1000.0
                                    ? Icons.verified_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(
                                widget.penalty.fineAmount <= 1000.0
                                    ? 'اعتماد وإصدار فوري (≤ 1000 ج.م)'
                                    : 'موافقة وتمرير للمدير العام (> 1000 ج.م)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.errorContainer,
                                foregroundColor: colorScheme.onErrorContainer,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => _showRejectionDialog(
                                context,
                                PenaltyStatus.rejectedByBranchesMarketing,
                              ),
                              icon: const Icon(Icons.cancel_rounded, size: 18),
                              label: const Text(
                                'رفض المخالفة',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Phase 2: General Manager / Super Admin Approval
                  if ((widget.currentDelegate!.role == UserRole.organizationAdmin ||
                          widget.currentDelegate!.role == UserRole.superAdmin) &&
                      (widget.penalty.status == PenaltyStatus.pendingGeneralManager ||
                          widget.penalty.status == PenaltyStatus.pendingBranchesMarketing)) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(28),
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () {
                                context.read<PenaltyBloc>().add(
                                      UpdatePenaltyStatusEvent(
                                        penaltyId: widget.penalty.penaltyId,
                                        status: PenaltyStatus.issued,
                                        reviewerName: widget.currentDelegate!.fullName,
                                      ),
                                    );
                              },
                              icon: const Icon(Icons.verified_rounded, size: 18),
                              label: const Text(
                                'اعتماد وإصدار',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.errorContainer,
                                foregroundColor: colorScheme.onErrorContainer,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => _showRejectionDialog(
                                context,
                                PenaltyStatus.rejectedByGeneralManager,
                              ),
                              icon: const Icon(Icons.cancel_rounded, size: 18),
                              label: const Text(
                                'رفض المخالفة',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEvidenceSheet(BuildContext context, PenaltyEntity penalty) {
    PenaltyEvidenceViewer.showEvidence(context, penalty: penalty);
  }
}

class _CompanyPenaltiesGroupCard extends StatefulWidget {
  final String companyName;
  final List<PenaltyEntity> penalties;
  final Delegate? currentDelegate;

  const _CompanyPenaltiesGroupCard({
    required this.companyName,
    required this.penalties,
    this.currentDelegate,
  });

  @override
  State<_CompanyPenaltiesGroupCard> createState() =>
      _CompanyPenaltiesGroupCardState();
}

class _CompanyPenaltiesGroupCardState
    extends State<_CompanyPenaltiesGroupCard> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    final hasPendingAction = widget.penalties.any((p) {
      if (widget.currentDelegate?.role == UserRole.branchesMarketingManager) {
        return p.status == PenaltyStatus.pendingBranchesMarketing;
      }
      if (widget.currentDelegate?.role == UserRole.organizationAdmin ||
          widget.currentDelegate?.role == UserRole.superAdmin) {
        return p.status == PenaltyStatus.pendingGeneralManager ||
            p.status == PenaltyStatus.pendingBranchesMarketing;
      }
      return false;
    });
    _isExpanded = hasPendingAction;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    double totalFine = 0.0;
    double totalDeducted = 0.0;

    for (var p in widget.penalties) {
      if (p.status != PenaltyStatus.cancelled) {
        totalFine += p.fineAmount;
      }
      if (p.status == PenaltyStatus.deducted) {
        totalDeducted += p.fineAmount;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.business_rounded,
              color: colorScheme.error,
              size: 24,
            ),
          ),
          title: Text(
            widget.companyName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'المخالفات: ${widget.penalties.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'الإجمالي: ${totalFine.toStringAsFixed(2)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (totalDeducted > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'المخصوم: ${totalDeducted.toStringAsFixed(2)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          children: widget.penalties
              .map(
                (p) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: _PenaltyCard(
                    penalty: p,
                    currentDelegate: widget.currentDelegate,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
