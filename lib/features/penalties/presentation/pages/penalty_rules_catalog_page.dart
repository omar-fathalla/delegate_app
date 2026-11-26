import 'package:delegate_app/core/design/money.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_rule_model.dart';

/// Item representation for the catalog that merges live Firestore rule data
/// with operational actions/details from the standard schedule.
class CatalogViolationItem {
  final String id;
  final int displayIndex;
  final String title;
  final double defaultFine;
  final double? repeatedFine;
  final ViolationCategory category;
  final bool isConfidential;
  final String? action1;
  final String? action2;

  const CatalogViolationItem({
    required this.id,
    required this.displayIndex,
    required this.title,
    required this.defaultFine,
    this.repeatedFine,
    required this.category,
    this.isConfidential = false,
    this.action1,
    this.action2,
  });
}

class PenaltyRulesCatalogPage extends StatefulWidget {
  final Delegate currentDelegate;

  const PenaltyRulesCatalogPage({
    super.key,
    required this.currentDelegate,
  });

  @override
  State<PenaltyRulesCatalogPage> createState() => _PenaltyRulesCatalogPageState();
}

class _PenaltyRulesCatalogPageState extends State<PenaltyRulesCatalogPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ViolationCategory? _selectedCategory;
  bool _isLoading = true;
  List<CatalogViolationItem> _allRules = [];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _canViewConfidentialRules {
    final role = widget.currentDelegate.role;
    return role == UserRole.superAdmin ||
        role == UserRole.technicalSupport ||
        role == UserRole.organizationAdmin ||
        role == UserRole.admin; // Company Supervisor
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('penalty_rules')
          .get();

      List<CatalogViolationItem> loaded = [];

      if (snapshot.docs.isNotEmpty) {
        final rulesList = snapshot.docs
            .map((doc) => PenaltyRuleModel.fromFirestore(doc))
            .toList();

        int counter = 1;
        for (final r in rulesList) {
          // Find matching entry in standard schedule for operational notes if available
          StandardViolation? matchedStandard;
          final cleanTitle = r.title.trim().toLowerCase();
          for (final std in officialViolationsSchedule) {
            if (std.title.trim().toLowerCase() == cleanTitle ||
                cleanTitle.contains(std.title.trim().toLowerCase()) ||
                std.title.trim().toLowerCase().contains(cleanTitle)) {
              matchedStandard = std;
              break;
            }
          }

          loaded.add(
            CatalogViolationItem(
              id: r.id,
              displayIndex: counter++,
              title: r.title,
              defaultFine: r.defaultFine,
              repeatedFine: r.repeatedFine ?? matchedStandard?.repeatedFine,
              category: r.category,
              isConfidential: r.isConfidential,
              action1: matchedStandard?.action1,
              action2: matchedStandard?.action2,
            ),
          );
        }
      } else {
        // Fallback to static official schedule if database collection is empty
        int counter = 1;
        for (final std in officialViolationsSchedule) {
          loaded.add(
            CatalogViolationItem(
              id: 'std_${std.id}',
              displayIndex: counter++,
              title: std.title,
              defaultFine: std.defaultFine,
              repeatedFine: std.repeatedFine,
              category: std.category,
              isConfidential: std.isConfidential,
              action1: std.action1,
              action2: std.action2,
            ),
          );
        }
      }

      // Filter by viewer authorization for confidential rules
      if (!_canViewConfidentialRules) {
        loaded = loaded.where((r) => !r.isConfidential).toList();
      }

      if (mounted) {
        setState(() {
          _allRules = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading rules for catalog: $e');
      // Offline fallback
      int counter = 1;
      final fallback = officialViolationsSchedule
          .where((std) => _canViewConfidentialRules || !std.isConfidential)
          .map(
            (std) => CatalogViolationItem(
              id: 'std_${std.id}',
              displayIndex: counter++,
              title: std.title,
              defaultFine: std.defaultFine,
              repeatedFine: std.repeatedFine,
              category: std.category,
              isConfidential: std.isConfidential,
              action1: std.action1,
              action2: std.action2,
            ),
          )
          .toList();

      if (mounted) {
        setState(() {
          _allRules = fallback;
          _isLoading = false;
        });
      }
    }
  }

  List<CatalogViolationItem> get _filteredRules {
    return _allRules.where((r) {
      if (_selectedCategory != null && r.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = r.title.toLowerCase().contains(q);
        final matchCategory = r.category.displayName.toLowerCase().contains(q);
        final matchAction1 = (r.action1 ?? '').toLowerCase().contains(q);
        final matchAction2 = (r.action2 ?? '').toLowerCase().contains(q);
        return matchTitle || matchCategory || matchAction1 || matchAction2;
      }
      return true;
    }).toList();
  }

  IconData _getCategoryIcon(ViolationCategory category) {
    switch (category) {
      case ViolationCategory.protocolBreach:
        return Icons.policy_rounded;
      case ViolationCategory.unauthorizedPhotography:
        return Icons.no_photography_rounded;
      case ViolationCategory.dataMissing:
        return Icons.data_usage_rounded;
      case ViolationCategory.theft:
        return Icons.warning_amber_rounded;
      case ViolationCategory.other:
        return Icons.assignment_late_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredRules;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.violationsPolicy,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              AppLocalizations.of(context)!.policyOfficialSubtitle,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: AppLocalizations.of(context)!.refreshPolicy,
            onPressed: _loadRules,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRules,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 1. Hero Summary Header Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: _buildHeroCard(theme, colorScheme),
                    ),
                  ),

                  // 2. Search Box
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSearchBar(colorScheme),
                    ),
                  ),

                  // 3. Category Filter Chips
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: _buildCategoryChips(colorScheme),
                    ),
                  ),

                  // 4. Counter & Category Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedCategory == null
                                ? AppLocalizations.of(context)!.allPolicyItems(filtered.length)
                                : '${_selectedCategory!.localizedName(AppLocalizations.of(context)!)} (${filtered.length})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 5. Items List or Empty State
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(theme, colorScheme),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = filtered[index];
                            return M3StaggeredItem(
                              index: index,
                              child: _buildViolationCard(
                                theme,
                                colorScheme,
                                item,
                              ),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
        border: Border.all(
          color: colorScheme.primary,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.gavel_rounded,
              color: colorScheme.onPrimary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.violationsPolicy,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.penPolicyCardBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAS-357 (C-09): the official M3 SearchBar filters the list in place
  // (no hand-made filled pill field).
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return SearchBar(
      key: const Key('penalty_rules_search'),
      controller: _searchController,
      hintText: AppLocalizations.of(context)!.searchPolicy,
      leading: const Icon(Icons.search_rounded),
      onChanged: (val) => setState(() => _searchQuery = val.trim()),
      trailing: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: const Icon(Icons.clear_rounded),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
      ],
    );
  }

  Widget _buildCategoryChips(ColorScheme colorScheme) {
    final categories = [
      null,
      ViolationCategory.protocolBreach,
      ViolationCategory.unauthorizedPhotography,
      ViolationCategory.dataMissing,
      ViolationCategory.theft,
      ViolationCategory.other,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          final label = cat == null ? AppLocalizations.of(context)!.allWithCount(_allRules.length) : cat.localizedName(AppLocalizations.of(context)!);
          final icon = cat == null ? Icons.apps_rounded : _getCategoryIcon(cat);

          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: FilterChip(
              avatar: Icon(
                icon,
                size: 16,
                color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
              ),
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = selected ? cat : null;
                });
              },
              backgroundColor: colorScheme.surfaceContainer,
              selectedColor: colorScheme.primary,
              labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
                side: BorderSide(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildViolationCard(
    ThemeData theme,
    ColorScheme colorScheme,
    CatalogViolationItem item,
  ) {
    final hasRepeated = item.repeatedFine != null && item.repeatedFine! > 0;
    final catIcon = _getCategoryIcon(item.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // TAS-357: the filled card look (surfaceContainerHighest), no border
      // or shadow.
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TashilRadius.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Category badge + (optional) Confidential badge
            Row(
              children: [
                // Category Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(TashilRadius.small),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(catIcon, size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        item.category.localizedName(AppLocalizations.of(context)!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (item.isConfidential)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.adminRestricted,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Title with Index Number
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${item.displayIndex}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Financial Values (First Fine vs Repeated Fine)
            Row(
              children: [
                // 1. First Fine Chip
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(TashilRadius.medium),
                      border: Border.all(
                        color: colorScheme.primary,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.firstTime,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                Money.formatEgp(item.defaultFine),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // 2. Repeated Fine Chip
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      // TAS-357 (F-04): a repeat fine is not an error.
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(TashilRadius.medium),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.replay_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.whenRepeated,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                hasRepeated
                                    ? Money.formatEgp(item.repeatedFine!)
                                    : AppLocalizations.of(context)!.perManagementDecision,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: hasRepeated
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Operational Action / Consequence Note (if available)
            if (item.action1 != null &&
                item.action1!.isNotEmpty &&
                !item.action1!.contains(item.defaultFine.toStringAsFixed(0))) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.plannedAction(item.action1 ?? ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              Icons.search_off_rounded,
              size: 54,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context)!.noResults,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)!.tryOtherSearch,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
