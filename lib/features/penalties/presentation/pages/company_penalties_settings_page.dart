import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/money.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/widgets/storage_resolved_image.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:delegate_app/features/penalties/presentation/utils/penalty_list_scope.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_create_penalty_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';

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
    } catch (e, st) {
      debugPrint('CompanyPenalties: _loadBranchesAndPinned failed: $e\n$st');
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
      showTashilSnackBar(context, AppLocalizations.of(context)!.penSelectBranchesFirst);
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
      showTashilSnackBar(context, AppLocalizations.of(context)!.penDefaultUnpinned);
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
          ? AppLocalizations.of(context)!.penBranchPinned
          : AppLocalizations.of(context)!.penBranchesPinned(count);

      showTashilSnackBar(context, msg);
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

            return Material(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
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
                              Text(
                                AppLocalizations.of(context)!.penSelectDisplayBranches,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                selectedCount == 0
                                    ? AppLocalizations.of(context)!.penShowingAllBranches
                                    : AppLocalizations.of(context)!.penBranchesSelected(selectedCount),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                            label: Text(AppLocalizations.of(context)!.clearSelection),
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
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.searchBranchName,
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
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(TashilRadius.medium),
                              borderSide: BorderSide(
                                  color: colorScheme.outlineVariant),
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
                              label: Text(AppLocalizations.of(context)!.allBranchesAll, style: Theme.of(context).textTheme.bodySmall),
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
                              label: Text(AppLocalizations.of(context)!.selectAll, style: Theme.of(context).textTheme.bodySmall),
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
                              AppLocalizations.of(context)!.noMatchingBranches,
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
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight:
                                              isChecked ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ),
                                    if (isPinned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          borderRadius: BorderRadius.circular(TashilRadius.small),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context)!.inDefault,
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  AppLocalizations.of(context)!.codeLabel(branchId),
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
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
                          color: colorScheme.outlineVariant,
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
                                borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
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
                                  ? AppLocalizations.of(context)!.confirmShowAllBranches
                                  : AppLocalizations.of(context)!.confirmFilterCount(tempSelection.length),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
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
        );
      },
    );
  }

  bool _isPenaltyForDelegate(PenaltyEntity p, Delegate delegate) {
    if (p.targetDelegateId != null && p.targetDelegateId!.trim().isNotEmpty) {
      final tid = p.targetDelegateId!.trim();
      if (tid == delegate.uid) return true;
      if (delegate.delegatePublicId.isNotEmpty && tid == delegate.delegatePublicId) return true;

      final cleanTid = tid.replaceAll(RegExp(r'\D'), '');
      final cleanDelPhone = delegate.phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (cleanTid.isNotEmpty && cleanDelPhone.isNotEmpty) {
        if (cleanTid == cleanDelPhone ||
            cleanTid.endsWith(cleanDelPhone) ||
            cleanDelPhone.endsWith(cleanTid)) {
          return true;
        }
      }
    }

    if (p.targetDelegateName != null && p.targetDelegateName!.trim().isNotEmpty) {
      final tName = p.targetDelegateName!.trim().toLowerCase();
      final delName = delegate.fullName.trim().toLowerCase();
      if (tName == delName) return true;

      final combined = '${delegate.firstName} ${delegate.lastName}'.trim().toLowerCase();
      if (combined.isNotEmpty && tName == combined) return true;
    }

    return false;
  }

  bool _canUserViewConfidentialPenalty(PenaltyEntity p, Delegate user) {
    // 1. Super Admin, Technical Support, Organization Admin
    if (user.role == UserRole.superAdmin ||
        user.role == UserRole.technicalSupport ||
        user.role == UserRole.organizationAdmin) {
      return true;
    }

    // 2. The Target Delegate himself
    if (user.role == UserRole.delegate) {
      return _isPenaltyForDelegate(p, user);
    }

    // 3. The Company Supervisor of that company
    if (user.role == UserRole.admin) {
      final compId = user.companyUID.isNotEmpty ? user.companyUID : user.organizationUID;
      if (compId.isNotEmpty && (compId == p.companyId || compId.toLowerCase() == p.companyName.toLowerCase())) {
        return true;
      }
    }

    // Strictly hidden from all other roles (Branches Marketing Manager, Marketing, other supervisors, etc.)
    return false;
  }

  void _loadData() {
    if (widget.delegate.role == UserRole.marketingPromotion) return;
    if (widget.delegate.role == UserRole.delegate) {
      context.read<PenaltyBloc>().add(LoadDelegatePenaltiesEvent(widget.delegate));
      return;
    }
    // Org-admin cannot list the whole penalties collection; rules require orgScoped.
    if (widget.delegate.role == UserRole.organizationAdmin) {
      final companyId = widget.delegate.companyUID;
      context.read<PenaltyBloc>().add(LoadCompanyPenaltiesEvent(
        companyId,
        organizationId: widget.delegate.organizationUID,
      ));
      return;
    }
    // TAS-73: global staff list everything; company staff their company;
    // org-scoped staff their organization (an org id is never a company id).
    context.read<PenaltyBloc>().add(penaltyListEventFor(widget.delegate));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.delegate.role == UserRole.marketingPromotion) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(AppLocalizations.of(context)!.finesSection),
                backgroundColor: colorScheme.surfaceContainer,
                elevation: 0,
                shape: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              )
            : null,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              AppLocalizations.of(context)!.promoNoFinesAccess,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    final isDelegate = widget.delegate.role == UserRole.delegate;
    final canCreatePenalty = widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.technicalSupport ||
        widget.delegate.role == UserRole.marketing;
    final isOrgAdmin = widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.technicalSupport;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: colorScheme.surfaceContainer,
              elevation: 0,
              shape: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              title: Text(
                isDelegate
                    ? AppLocalizations.of(context)!.myViolationsTitle
                    : AppLocalizations.of(context)!.violationsRecord,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: AppLocalizations.of(context)!.backAction,
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              actions: [
                IconButton(
                  icon: const Icon(Icons.menu_book_rounded),
                  tooltip: AppLocalizations.of(context)!.violationsPolicy,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PenaltyRulesCatalogPage(
                          currentDelegate: widget.delegate,
                        ),
                      ),
                    );
                  },
                ),
                // TAS-50: only a super-admin edits the shared catalog.
                if (widget.delegate.role == UserRole.superAdmin)
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: AppLocalizations.of(context)!.finesSettings,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PenaltyRulesSettingsPage(adminDelegate: widget.delegate),
                        ),
                      );
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: AppLocalizations.of(context)!.refreshPolicy,
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
              label: Text(AppLocalizations.of(context)!.recordViolation),
            )
          : null,
      // TAS-266: approve / reject emit PenaltyActionSuccessState. The page
      // had no case for it and went blank without reloading. Keep the list
      // on screen, confirm, and reload.
      body: BlocConsumer<PenaltyBloc, PenaltyState>(
        listenWhen: (_, state) => state is PenaltyActionSuccessState,
        listener: (context, state) {
          if (state is PenaltyActionSuccessState) {
            showTashilSnackBar(context, state.message);
            _loadData();
          }
        },
        buildWhen: (_, state) => state is! PenaltyActionSuccessState,
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
                  // TAS-357 (C-01): retry is a tonal button, not Elevated.
                  FilledButton.tonalIcon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            );
          }

          if (state is PenaltyLoadedState) {
            var penalties = state.penalties;

            // Strict personal isolation for delegate role
            if (isDelegate) {
              penalties = penalties
                  .where((p) => _isPenaltyForDelegate(p, widget.delegate))
                  .toList();
            }

            // Confidentiality filter: strictly isolated to the 4 permitted roles
            penalties = penalties.where((p) {
              if (!p.isConfidential) return true;
              return _canUserViewConfidentialPenalty(p, widget.delegate);
            }).toList();

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
                  p.companyName.isNotEmpty ? p.companyName : AppLocalizations.of(context)!.unknownCompany;
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
              branchLabel = AppLocalizations.of(context)!.allBranchesOverview;
            } else if (selectedCount == 1) {
              final singleId = _selectedBranchIds.first;
              final match = _availableBranches.firstWhere(
                (b) => b['id'] == singleId,
                orElse: () => {'name': singleId},
              );
              branchLabel = match['name'] ?? singleId;
            } else {
              branchLabel = AppLocalizations.of(context)!.selectedGroupCount(selectedCount);
            }

            return RefreshIndicator(
              onRefresh: () async {
                _loadData();
                await _loadBranchesAndPinned();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Official Rules Catalog Quick Link Banner
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PenaltyRulesCatalogPage(
                                currentDelegate: widget.delegate,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(TashilRadius.large),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(TashilRadius.large),
                            border: Border.all(
                              color: colorScheme.primary,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  color: colorScheme.onPrimary,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.violationsPolicy,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      AppLocalizations.of(context)!.finesPolicyCardSubtitle,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 0. Multi-Branch Selector & Pin Bar (Reserved for Supervisors & Admins)
                  if (!isDelegate)
                    SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(TashilRadius.large),
                          border: Border.all(
                            color: isPinned
                                ? _kSuccess(context)
                                : colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.storefront_rounded,
                                  color: isPinned ? _kSuccess(context) : colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context)!.showViolationsFor,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                IconButton.filledTonal(
                                  tooltip: isPinned
                                      ? AppLocalizations.of(context)!.unpinDefaultGroup
                                      : AppLocalizations.of(context)!.pinSelectedAsDefault,
                                  style: IconButton.styleFrom(
                                    backgroundColor: isPinned
                                        ? colorScheme.tertiaryContainer
                                        : colorScheme.surface,
                                    foregroundColor: isPinned
                                        ? colorScheme.onTertiaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(TashilRadius.small),
                                      side: BorderSide(
                                        color: isPinned
                                            ? colorScheme.tertiary
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.push_pin_rounded,
                                    size: 16,
                                    color: isPinned ? colorScheme.tertiary : null,
                                  ),
                                  onPressed: _togglePinCurrentBranches,
                                ),
                                const SizedBox(width: 6),
                                IconButton.filledTonal(
                                  tooltip: AppLocalizations.of(context)!.refreshFinesData,
                                  style: IconButton.styleFrom(
                                    backgroundColor: colorScheme.surface,
                                    foregroundColor: colorScheme.primary,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(TashilRadius.small),
                                      side: BorderSide(
                                        color: colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  onPressed: () {
                                    _loadData();
                                    _loadBranchesAndPinned();
                                    showTashilSnackBar(context, AppLocalizations.of(context)!.finesDataRefreshed);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          _isLoadingBranches
                              ? const LinearProgressIndicator()
                              : InkWell(
                                  onTap: _openMultiBranchPickerSheet,
                                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(TashilRadius.medium),
                                      border: Border.all(
                                        color: isPinned
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant,
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
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                              ),
                                              if (isPinned)
                                                Text(
                                                  AppLocalizations.of(context)!.pinnedDefaultGroup,
                                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
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
                                      padding: const EdgeInsetsDirectional.only(start: 6),
                                      child: Chip(
                                        avatar: Icon(Icons.location_on_rounded,
                                            size: 13, color: colorScheme.primary),
                                        label: Text(
                                          bObj['name'] ?? branchId,
                                          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
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
                                    padding: const EdgeInsetsDirectional.only(start: 6),
                                    child: ActionChip(
                                      label: Text(AppLocalizations.of(context)!.showAll, style: Theme.of(context).textTheme.labelMedium),
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
                      // TAS-357 (F-04): the summary is a filled surface card,
                      // not an error gradient; totals are not errors.
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          TashilRadius.extraLarge,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDelegate
                                    ? (filteredTotalFines > 0
                                        ? Icons.warning_amber_rounded
                                        : Icons.verified_user_rounded)
                                    : Icons.warning_amber_rounded,
                                color: isDelegate
                                    ? (filteredTotalFines > 0
                                        ? colorScheme.error
                                        : _kSuccess(context))
                                    : colorScheme.error,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isDelegate
                                      ? AppLocalizations.of(context)!.mySummary
                                      : (_selectedBranchIds.isNotEmpty
                                          ? AppLocalizations.of(context)!.finesSummaryOf(branchLabel)
                                          : (isOrgAdmin
                                              ? AppLocalizations.of(context)!.companiesFinesSummary
                                              : AppLocalizations.of(context)!.finesSummary)),
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
                                      isDelegate ? AppLocalizations.of(context)!.myTotalFines : AppLocalizations.of(context)!.totalFines,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      Money.formatEgp(filteredTotalFines),
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: filteredTotalFines > 0
                                            ? colorScheme.error
                                            : _kSuccess(context),
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
                                      isDelegate ? AppLocalizations.of(context)!.deductedFromMe : AppLocalizations.of(context)!.deducted,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      Money.formatEgp(filteredDeducted),
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: _kOnSuccessContainer(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isDelegate) ...[
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
                                        AppLocalizations.of(context)!.violationsCountLabel,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${penalties.length}',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isOrgAdmin) ...[
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
                                        AppLocalizations.of(context)!.companiesCount,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppLocalizations.of(context)!.companiesN(groupedByCompany.keys.length),
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
                            AppLocalizations.of(context)!.filterByCompany,
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
                                    AppLocalizations.of(context)!.allCompaniesCount(penalties.length),
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

                // 3. Company Breakdown Cards, Direct Delegate List, or Empty State
                if (penalties.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.verified_user_rounded,
                                size: 56,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isDelegate
                                  ? AppLocalizations.of(context)!.recordClean
                                  : (isOrgAdmin
                                      ? AppLocalizations.of(context)!.noViolationsAnyCompany
                                      : AppLocalizations.of(context)!.noViolationsThisCompany),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (isDelegate) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(context)!.noViolationsRecorded,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else if (isDelegate)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _PenaltyCard(
                            penalty: penalties[index],
                            currentDelegate: widget.delegate,
                          );
                        },
                        childCount: penalties.length,
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
            ),
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
                widget.currentDelegate?.role == UserRole.superAdmin ||
                widget.currentDelegate?.role == UserRole.technicalSupport) &&
            widget.penalty.status == PenaltyStatus.pendingGeneralManager);
    _isExpanded = requiresAction;
  }

  /// TAS-357: status colours from the scheme / TashilSemanticColors.
  /// Only a rejection is an error; pending is a warning, issued and
  /// deducted are success, the rest neutral or tertiary.
  Color _getStatusColor(PenaltyStatus status) {
    final cs = Theme.of(context).colorScheme;
    final sem = Theme.of(context).extension<TashilSemanticColors>();
    switch (status) {
      case PenaltyStatus.pendingBranchesMarketing:
      case PenaltyStatus.pendingGeneralManager:
        return sem?.warning ?? cs.tertiary;
      case PenaltyStatus.rejectedByBranchesMarketing:
      case PenaltyStatus.rejectedByGeneralManager:
        return cs.error;
      case PenaltyStatus.issued:
      case PenaltyStatus.deducted:
        return sem?.success ?? cs.primary;
      case PenaltyStatus.acknowledged:
        return cs.primary;
      case PenaltyStatus.disputed:
        return cs.tertiary;
      case PenaltyStatus.cancelled:
        return cs.onSurfaceVariant;
    }
  }

  void _showRejectionDialog(BuildContext context, PenaltyStatus nextStatus) {
    final controller = TextEditingController();
    // TAS-357 (C-27): kit dialog, text buttons, confirm last.
    showTashilDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.rejectionReason),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.rejectionReasonHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
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
            child: Text(AppLocalizations.of(context)!.confirmRejection),
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
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TashilRadius.large),
        side: BorderSide(
          color: _isExpanded
              ? colorScheme.primary
              : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(TashilRadius.large),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Compact mode)
              Row(
                children: [
                  Container(
                    // TAS-357: compact status label, no tint or border.
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: TashilSpacing.sm,
                      vertical: TashilSpacing.xs / 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(TashilRadius.small),
                    ),
                    child: Text(
                      widget.penalty.status.displayName,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: statusColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.penalty.isRepeated) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(TashilRadius.medium),
                        border: Border.all(color: colorScheme.error),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.repeatedViolation,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  if (widget.penalty.isConfidential) ...[
                    const SizedBox(width: 6),
                    // TAS-357: compact label in the tertiary pair.
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: TashilSpacing.sm,
                        vertical: TashilSpacing.xs / 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(TashilRadius.small),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 12,
                            color: colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: TashilSpacing.xs),
                          Text(
                            AppLocalizations.of(context)!.confidential,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    Money.formatEgp(widget.penalty.fineAmount),
                    // TAS-357 (F-04): an amount is not an error.
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
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
                        borderRadius: BorderRadius.circular(TashilRadius.small),
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
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold),
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
                      AppLocalizations.of(context)!.targetDelegate(widget.penalty.targetDelegateName ?? ''),
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
                    AppLocalizations.of(context)!.violationDetails,
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
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(TashilRadius.small),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.rejectReasonLabel(widget.penalty.rejectionReason ?? ''),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],

                // Audit Trail Info
                if (widget.penalty.branchesMarketingApprovedBy != null) ...[
                  Text(
                    AppLocalizations.of(context)!.branchesMarketingApproval(widget.penalty.branchesMarketingApprovedBy ?? ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _kOnSuccessContainer(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (widget.penalty.generalManagerApprovedBy != null) ...[
                  Text(
                    AppLocalizations.of(context)!.generalManagerApproval(widget.penalty.generalManagerApprovedBy ?? ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _kOnSuccessContainer(context),
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
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(TashilRadius.medium),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
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
                              AppLocalizations.of(context)!.attachmentsCount(widget.penalty.evidenceFiles.length),
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                            const Spacer(),
                            Text(
                              AppLocalizations.of(context)!.tapToPreview2,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                              borderRadius: BorderRadius.circular(TashilRadius.medium),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(TashilRadius.medium),
                                        child: isImage
                                            ? StorageResolvedImage(pathOrUrl: file.fileUrl, builder: (_, resolved) => CachedNetworkImage(
                                                imageUrl: resolved,
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
                                              ),)
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
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
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
                                            color: _kOverlay.scrim.withValues(alpha: 0.55),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.zoom_in_rounded,
                                            size: 13,
                                            color: _kOverlay.onSurface,
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
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(TashilRadius.small),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.attach_file_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.noViolationDocs,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                Row(
                  children: [
                    if (widget.penalty.createdByName.isNotEmpty) ...[
                      Icon(Icons.badge_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          AppLocalizations.of(context)!.editorName(widget.penalty.createdByName),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _callCreator(context, widget.penalty),
                        borderRadius: BorderRadius.circular(TashilRadius.small),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kSuccessContainer(context),
                            borderRadius: BorderRadius.circular(TashilRadius.small),
                            border: Border.all(color: _kSuccessContainer(context)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_in_talk_rounded, size: 11, color: _kOnSuccessContainer(context)),
                              const SizedBox(width: 3),
                              Text(
                                AppLocalizations.of(context)!.callAction,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: _kOnSuccessContainer(context)),
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
                            borderRadius: BorderRadius.circular(TashilRadius.medium),
                          ),
                        ),
                        onPressed: () => _showEvidenceSheet(context, widget.penalty),
                        icon: const Icon(Icons.attach_file_rounded, size: 15),
                        label: Text(
                          AppLocalizations.of(context)!.documentsCount(widget.penalty.evidenceFiles.length),
                          style: Theme.of(context).textTheme.labelMedium,
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
                        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
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
                                  borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
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
                                AppLocalizations.of(context)!.approveAction,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
                                  borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => _showRejectionDialog(
                                context,
                                PenaltyStatus.rejectedByBranchesMarketing,
                              ),
                              icon: const Icon(Icons.cancel_rounded, size: 18),
                              label: Text(
                                AppLocalizations.of(context)!.rejectAction,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Phase 2: General Manager / Super Admin Approval
                  if ((widget.currentDelegate!.role == UserRole.organizationAdmin ||
                          widget.currentDelegate!.role == UserRole.superAdmin ||
                          widget.currentDelegate!.role == UserRole.technicalSupport) &&
                      (widget.penalty.status == PenaltyStatus.pendingGeneralManager ||
                          widget.penalty.status == PenaltyStatus.pendingBranchesMarketing)) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
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
                                  borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
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
                              label: Text(
                                AppLocalizations.of(context)!.approveAction,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
                                  borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () => _showRejectionDialog(
                                context,
                                PenaltyStatus.rejectedByGeneralManager,
                              ),
                              icon: const Icon(Icons.cancel_rounded, size: 18),
                              label: Text(
                                AppLocalizations.of(context)!.rejectAction,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
          widget.currentDelegate?.role == UserRole.superAdmin ||
          widget.currentDelegate?.role == UserRole.technicalSupport) {
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
        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(TashilRadius.large),
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
                    borderRadius: BorderRadius.circular(TashilRadius.medium),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.violationsWithCount(widget.penalties.length),
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
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(TashilRadius.medium),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.totalWithValue(Money.formatEgp(totalFine)),
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
                      color: _kSuccessContainer(context),
                      borderRadius: BorderRadius.circular(TashilRadius.medium),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.deductedWithValue(Money.formatEgp(totalDeducted)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _kOnSuccessContainer(context),
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


// TAS-357: semantic colours with a fallback when a test theme has no
// TashilSemanticColors extension.
Color _kSuccess(BuildContext context) =>
    Theme.of(context).extension<TashilSemanticColors>()?.success ??
    Theme.of(context).colorScheme.primary;
Color _kSuccessContainer(BuildContext context) =>
    Theme.of(context).extension<TashilSemanticColors>()?.successContainer ??
    Theme.of(context).colorScheme.primaryContainer;
Color _kOnSuccessContainer(BuildContext context) =>
    Theme.of(context).extension<TashilSemanticColors>()?.onSuccessContainer ??
    Theme.of(context).colorScheme.onPrimaryContainer;

/// Content drawn over a photo: the dark theme's roles (TAS-357).
final ColorScheme _kOverlay = AppTheme.darkTheme().colorScheme;
