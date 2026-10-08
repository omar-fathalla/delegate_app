import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_rule_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class PenaltyRulesSettingsPage extends StatefulWidget {
  final Delegate adminDelegate;

  const PenaltyRulesSettingsPage({
    super.key,
    required this.adminDelegate,
  });

  @override
  State<PenaltyRulesSettingsPage> createState() => _PenaltyRulesSettingsPageState();
}

class _PenaltyRulesSettingsPageState extends State<PenaltyRulesSettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rulesSubscription;

  List<PenaltyRuleModel> _rules = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', 'confidential', 'public'
  String _searchQuery = '';

  CollectionReference<Map<String, dynamic>> get _rulesRef =>
      FirebaseFirestore.instance.collection('penalty_rules');

  @override
  void initState() {
    super.initState();
    _startRealtimeListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _rulesSubscription?.cancel();
    super.dispose();
  }

  void _startRealtimeListener() {
    _rulesSubscription?.cancel();
    _rulesSubscription = _rulesRef.snapshots().listen((snapshot) async {
      if (snapshot.docs.isEmpty) {
        // Auto-seed if empty
        await _seedDefaultRules();
        return;
      }

      final list = snapshot.docs
          .map((doc) => PenaltyRuleModel.fromFirestore(doc))
          .toList();

      // Sort by creation date or title
      list.sort((a, b) => a.title.compareTo(b.title));

      if (mounted) {
        setState(() {
          _rules = list;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint('Error listening to penalty rules: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _seedDefaultRules() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final v in officialViolationsSchedule) {
        final docRef = _rulesRef.doc('standard_${v.id}');
        final model = PenaltyRuleModel(
          id: docRef.id,
          title: v.title,
          defaultFine: v.defaultFine,
          repeatedFine: v.repeatedFine,
          isConfidential: false,
          category: v.category,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: widget.adminDelegate.fullName.isNotEmpty
              ? widget.adminDelegate.fullName
              : 'النظام الافتراضي',
        );
        batch.set(docRef, model.toJson());
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding penalty rules: $e');
    }
  }

  Future<void> _toggleConfidentiality(PenaltyRuleModel rule, bool newValue) async {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      HapticFeedback.mediumImpact();
      await _rulesRef.doc(rule.id).update({
        'isConfidential': newValue,
        'updatedAt': Timestamp.now(),
      });

      // Synchronize all existing penalties in Firestore matching this rule's title
      try {
        final penaltiesSnap = await FirebaseFirestore.instance
            .collection('penalties')
            .where('title', isEqualTo: rule.title.trim())
            .get();
        if (penaltiesSnap.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in penaltiesSnap.docs) {
            batch.update(doc.reference, {
              'isConfidential': newValue,
              'updatedAt': Timestamp.now(),
            });
          }
          await batch.commit();
        }
      } catch (err) {
        debugPrint('Error syncing penalties on confidentiality toggle: $err');
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newValue ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: newValue ? colorScheme.onTertiaryContainer : colorScheme.onPrimaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  newValue
                      ? 'تم تقييد الغرامة (${rule.title}) لتصبح سرية ومحصورة لـ 4 أدوار فقط.'
                      : 'تم إلغاء تقييد الغرامة (${rule.title}) لتصبح عامة.',
                  style: TextStyle(
                    color: newValue ? colorScheme.onTertiaryContainer : colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: newValue ? colorScheme.tertiaryContainer : colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('فشل في تعديل حالة سرية الغرامة: $e'),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showAddEditRuleDialog({PenaltyRuleModel? ruleToEdit}) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final isEditing = ruleToEdit != null;
    final titleController = TextEditingController(text: ruleToEdit?.title ?? '');
    final fineController = TextEditingController(
      text: ruleToEdit != null ? ruleToEdit.defaultFine.toStringAsFixed(0) : '',
    );
    final repeatedFineController = TextEditingController(
      text: ruleToEdit?.repeatedFine != null
          ? ruleToEdit!.repeatedFine!.toStringAsFixed(0)
          : '',
    );
    bool isConfidential = ruleToEdit?.isConfidential ?? false;
    ViolationCategory selectedCategory =
        ruleToEdit?.category ?? ViolationCategory.protocolBreach;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConfidential
                          ? colorScheme.tertiaryContainer
                          : colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_rounded : Icons.add_circle_rounded,
                      color: isConfidential ? colorScheme.onTertiaryContainer : colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEditing ? 'تعديل بند الغرامة' : 'إضافة غرامة جديدة',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بيانات الغرامة والمخالفة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'اسم الغرامة / المخالفة *',
                          hintText: 'مثال: التأخر عن موعد العمل، عدم حيازة بطاقة تعريف...',
                          prefixIcon: const Icon(Icons.gavel_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال اسم الغرامة';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: fineController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: 'قيمة الغرامة الأولى *',
                                suffixText: 'ج.م',
                                prefixIcon: const Icon(Icons.attach_money_rounded),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'مطلوب';
                                }
                                final val = double.tryParse(value);
                                if (val == null || val <= 0) {
                                  return 'أدخل مبلغ صحيح';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: repeatedFineController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: 'قيمة التكرار (اختياري)',
                                suffixText: 'ج.م',
                                prefixIcon: const Icon(Icons.repeat_rounded),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<ViolationCategory>(
                        initialValue: selectedCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'تصنيف المخالفة',
                          prefixIcon: const Icon(Icons.category_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: ViolationCategory.values.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat.displayName, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedCategory = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isConfidential
                              ? colorScheme.tertiaryContainer.withValues(alpha: 0.25)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isConfidential ? colorScheme.tertiary.withValues(alpha: 0.4) : colorScheme.outlineVariant,
                          ),
                        ),
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Icon(
                                isConfidential ? Icons.lock_rounded : Icons.public_rounded,
                                size: 20,
                                color: isConfidential ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'غرامة سرية ومقيدة',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'عند التفعيل: لا تظهر إلا للسوبر أدمن، الدعم الفني، مشرف الشركة، والمندوب المعني.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isConfidential ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: isConfidential,
                          activeTrackColor: colorScheme.tertiaryContainer,
                          activeThumbColor: colorScheme.tertiary,
                          onChanged: (val) {
                            setDialogState(() {
                              isConfidential = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final title = titleController.text.trim();
                    final defaultFine = double.parse(fineController.text.trim());
                    final repeatedText = repeatedFineController.text.trim();
                    final double? repeatedFine =
                        repeatedText.isNotEmpty ? double.tryParse(repeatedText) : null;

                    Navigator.of(dialogContext).pop();

                    try {
                      if (isEditing) {
                        await _rulesRef.doc(ruleToEdit.id).update({
                          'title': title,
                          'defaultFine': defaultFine,
                          'repeatedFine': repeatedFine,
                          'category': selectedCategory.toFirestoreString(),
                          'isConfidential': isConfidential,
                          'updatedAt': Timestamp.now(),
                        });

                        // Synchronize penalties matching old or new title
                        try {
                          final penaltiesSnap = await FirebaseFirestore.instance
                              .collection('penalties')
                              .where('title', isEqualTo: ruleToEdit.title.trim())
                              .get();
                          if (penaltiesSnap.docs.isNotEmpty) {
                            final batch = FirebaseFirestore.instance.batch();
                            for (final doc in penaltiesSnap.docs) {
                              batch.update(doc.reference, {
                                'isConfidential': isConfidential,
                                if (title != ruleToEdit.title) 'title': title,
                                'updatedAt': Timestamp.now(),
                              });
                            }
                            await batch.commit();
                          }
                        } catch (err) {
                          debugPrint('Error syncing penalties on rule edit: $err');
                        }
                      } else {
                        final newDoc = _rulesRef.doc();
                        final newRule = PenaltyRuleModel(
                          id: newDoc.id,
                          title: title,
                          defaultFine: defaultFine,
                          repeatedFine: repeatedFine,
                          isConfidential: isConfidential,
                          category: selectedCategory,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                          createdBy: widget.adminDelegate.fullName.isNotEmpty
                              ? widget.adminDelegate.fullName
                              : 'سوبر أدمن',
                        );
                        await newDoc.set(newRule.toJson());
                      }

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            isEditing ? 'تم تحديث بيانات الغرامة بنجاح.' : 'تم إضافة بند الغرامة الجديد بنجاح.',
                            style: TextStyle(color: colorScheme.onPrimaryContainer),
                          ),
                          backgroundColor: colorScheme.primaryContainer,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('فشل في حفظ بند الغرامة: $e'),
                          backgroundColor: errorColor,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(isEditing ? 'حفظ التعديلات' : 'إضافة الغرامة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteRule(PenaltyRuleModel rule) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: colorScheme.error, size: 28),
            const SizedBox(width: 8),
            const Text('تأكيد الحذف', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف بند الغرامة:\n"${rule.title}" من اللائحة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _rulesRef.doc(rule.id).delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حذف بند الغرامة بنجاح.',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            backgroundColor: colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في حذف البند: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  List<PenaltyRuleModel> get _filteredRules {
    return _rules.where((r) {
      if (_selectedFilter == 'confidential' && !r.isConfidential) {
        return false;
      }
      if (_selectedFilter == 'public' && r.isConfidential) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = r.title.toLowerCase().contains(q);
        final matchCategory = r.category.displayName.toLowerCase().contains(q);
        return matchTitle || matchCategory;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredRules;

    final totalCount = _rules.length;
    final confidentialCount = _rules.where((r) => r.isConfidential).length;
    final publicCount = totalCount - confidentialCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'إعدادات ولائحة الغرامات',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'إدارة بنود المخالفات وضوابط السرية والظهور',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'مزامنة اللائحة الرسمية',
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('مزامنة اللائحة الرسمية'),
                  content: const Text(
                    'سيتم استيراد أي بنود مفقودة من اللائحة الرسمية المعتمدة (28 مخالفة). هل تود المتابعة؟',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مزامنة')),
                  ],
                ),
              );
              if (confirm == true) {
                await _seedDefaultRules();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تمت مزامنة اللائحة الرسمية بنجاح.',
                      style: TextStyle(color: colorScheme.onPrimaryContainer),
                    ),
                    backgroundColor: colorScheme.primaryContainer,
                  ),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditRuleDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة غرامة'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Stats Bar
                _buildStatsHeader(context, colorScheme, totalCount, confidentialCount, publicCount),

                // 2. Search & Filter Bar
                _buildSearchAndFilters(context, colorScheme),

                // 3. Main Rules List
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(context, colorScheme)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final rule = filtered[index];
                            return _buildRuleCard(context, rule, colorScheme, theme);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsHeader(
    BuildContext context,
    ColorScheme colorScheme,
    int total,
    int confidential,
    int public,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          _buildStatPill(
            context: context,
            title: 'إجمالي البنود',
            count: total,
            icon: Icons.format_list_numbered_rounded,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _buildStatPill(
            context: context,
            title: 'سرية ومقيدة',
            count: confidential,
            icon: Icons.lock_rounded,
            color: colorScheme.tertiary,
          ),
          const SizedBox(width: 8),
          _buildStatPill(
            context: context,
            title: 'عامة',
            count: public,
            icon: Icons.public_rounded,
            color: colorScheme.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required BuildContext context,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          // Search Field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'بحث في بنود الغرامات أو التصنيفات...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: colorScheme.surface,
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim();
              });
            },
          ),
          const SizedBox(height: 8),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: _selectedFilter == 'all',
                  onSelected: (val) {
                    setState(() => _selectedFilter = 'all');
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(Icons.lock_rounded, size: 16, color: colorScheme.tertiary),
                  label: const Text('سرية ومقيدة (4 أدوار فقط)'),
                  selected: _selectedFilter == 'confidential',
                  selectedColor: colorScheme.tertiaryContainer,
                  onSelected: (val) {
                    setState(() => _selectedFilter = 'confidential');
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(Icons.public_rounded, size: 16, color: colorScheme.secondary),
                  label: const Text('عامة'),
                  selected: _selectedFilter == 'public',
                  selectedColor: colorScheme.secondaryContainer,
                  onSelected: (val) {
                    setState(() => _selectedFilter = 'public');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConfidentialityExplanation(BuildContext context, bool isConfidential) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: Icon(
          isConfidential ? Icons.lock_rounded : Icons.public_rounded,
          color: isConfidential ? colorScheme.tertiary : colorScheme.secondary,
          size: 36,
        ),
        title: Text(
          isConfidential ? 'غرامة سرية ومقيدة' : 'غرامة عامة',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        content: Text(
          isConfidential
              ? 'هذه الغرامة مقيدة وسرية، ومرئية فقط لـ:\n• المشرف العام (Super Admin)\n• الدعم الفني (Technical Support)\n• أدمن / مشرف الشركة المعني\n• المندوب المعني بالمخالفة فقط.'
              : 'هذه الغرامة عامة وتظهر لكافة المشرفين ومديري تسويق الفروع المعنيين.',
          style: const TextStyle(fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    PenaltyRuleModel rule,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isConfidential = rule.isConfidential;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isConfidential
              ? colorScheme.tertiary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: isConfidential ? 1.2 : 0.8,
        ),
      ),
      color: isConfidential
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.10)
          : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 9.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Category badge + Compact Confidential status chip + Switch + Edit/Delete
            Row(
              children: [
                // Category Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isConfidential
                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.7)
                        : colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rule.category.displayName,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isConfidential ? colorScheme.onTertiaryContainer : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Confidential / Public indicator chip (Tap to view details)
                Tooltip(
                  message: isConfidential
                      ? 'غرامة سرية (اضغط للتفاصيل)'
                      : 'غرامة عامة (اضغط للتفاصيل)',
                  child: InkWell(
                    onTap: () => _showConfidentialityExplanation(context, isConfidential),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isConfidential
                            ? colorScheme.tertiary.withValues(alpha: 0.12)
                            : colorScheme.outlineVariant.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isConfidential ? Icons.lock_rounded : Icons.lock_open_rounded,
                            size: 13,
                            color: isConfidential ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isConfidential ? 'سرية ومقيدة' : 'عامة',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isConfidential ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Confidentiality Toggle Switch
                Tooltip(
                  message: isConfidential
                      ? 'إلغاء التقييد (تحويل لعامة)'
                      : 'تقييد الغرامة (تحويل لسرية ومقيدة)',
                  child: Transform.scale(
                    scale: 0.72,
                    child: Switch.adaptive(
                      value: isConfidential,
                      activeTrackColor: colorScheme.tertiaryContainer,
                      activeThumbColor: colorScheme.tertiary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (newVal) => _toggleConfidentiality(rule, newVal),
                    ),
                  ),
                ),

                // Edit Button
                IconButton(
                  tooltip: 'تعديل',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () => _showAddEditRuleDialog(ruleToEdit: rule),
                ),
                const SizedBox(width: 2),

                // Delete Button
                IconButton(
                  tooltip: 'حذف',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
                  onPressed: () => _confirmDeleteRule(rule),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Title
            Text(
              rule.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),

            // Amounts Row using Icons instead of long redundant text
            Row(
              children: [
                Tooltip(
                  message: 'الغرامة الأولى',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.payments_rounded, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${rule.defaultFine.toStringAsFixed(0)} ج.م',
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
                if (rule.repeatedFine != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'في حال التكرار',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay_rounded, size: 14, color: colorScheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            '${rule.repeatedFine!.toStringAsFixed(0)} ج.م',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 54, color: colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              'لا توجد بنود غرامات تطابق بحثك',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'يمكنك إضافة غرامة جديدة عبر الزر العائم بالأسفل أو مزامنة اللائحة الرسمية.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
