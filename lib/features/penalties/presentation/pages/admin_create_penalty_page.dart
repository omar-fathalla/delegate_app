import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';

class AdminCreatePenaltyPage extends StatefulWidget {
  final Delegate adminDelegate;

  const AdminCreatePenaltyPage({super.key, required this.adminDelegate});

  @override
  State<AdminCreatePenaltyPage> createState() => _AdminCreatePenaltyPageState();
}

class _AdminCreatePenaltyPageState extends State<AdminCreatePenaltyPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _fineAmountController = TextEditingController();
  final _picker = ImagePicker();

  String? _selectedCompanyId;
  String? _selectedCompanyName;
  ViolationCategory _selectedCategory = ViolationCategory.protocolBreach;

  StandardViolation? _selectedOfficialViolation;
  String? _selectedDelegateId;
  String? _selectedDelegateName;
  List<Map<String, String>> _companyDelegates = [];
  bool _isLoadingDelegates = false;

  List<Map<String, String>> _companies = [];
  bool _isLoadingCompanies = true;

  final List<File> _attachedFiles = [];

  bool _isRepeated = false;

  @override
  void initState() {
    super.initState();
    _fetchCompanies();
  }

  Future<void> _fetchCompanies() async {
    try {
      final firestore = FirebaseFirestore.instance;
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (widget.adminDelegate.organizationUID.isNotEmpty) {
        snapshot = await firestore
            .collection('organizations')
            .doc(widget.adminDelegate.organizationUID)
            .collection('companies')
            .get();
      } else {
        snapshot = await firestore.collectionGroup('companies').get();
      }

      if (!mounted) return;

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? data['companyName']?.toString() ?? doc.id,
        };
      }).toList();

      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      setState(() {
        _companies = list;
        if (list.isNotEmpty) {
          _selectedCompanyId = list.first['id'];
          _selectedCompanyName = list.first['name'];
          _fetchCompanyDelegates(list.first['id']!);
        }
        _isLoadingCompanies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCompanies = false;
      });
    }
  }

  Future<void> _fetchCompanyDelegates(String companyId) async {
    setState(() {
      _isLoadingDelegates = true;
      _companyDelegates = [];
      _selectedDelegateId = null;
      _selectedDelegateName = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final Map<String, Map<String, String>> delegatesMap = {};

      // Strategy 1: Fetch from subcollection /organizations/{org}/companies/{comp}/delegates
      if (widget.adminDelegate.organizationUID.isNotEmpty) {
        try {
          final subSnapshot = await firestore
              .collection('organizations')
              .doc(widget.adminDelegate.organizationUID)
              .collection('companies')
              .doc(companyId)
              .collection('delegates')
              .get();

          for (var doc in subSnapshot.docs) {
            final data = doc.data();
            final name = data['displayName']?.toString() ??
                data['fullName']?.toString() ??
                data['name']?.toString() ??
                doc.id;
            final phone = data['phoneNumber']?.toString() ?? data['phone']?.toString() ?? '';
            delegatesMap[doc.id] = {
              'id': doc.id,
              'name': name,
              'phone': phone,
            };
          }
        } catch (_) {}
      }

      // Strategy 2: Fetch from users collection filtering out supervisors/admins
      final userSnapshot = await firestore
          .collection('users')
          .where('companyUID', isEqualTo: companyId)
          .get();

      for (var doc in userSnapshot.docs) {
        final data = doc.data();
        final role = data['role']?.toString().toLowerCase() ?? '';
        // Skip supervisors, admins, company_admins
        if (role.contains('admin') || role.contains('supervisor') || role.contains('manager')) {
          continue;
        }

        final name = data['displayName']?.toString() ??
            data['fullName']?.toString() ??
            data['name']?.toString() ??
            doc.id;
        final phone = data['phoneNumber']?.toString() ?? data['phone']?.toString() ?? '';

        delegatesMap[doc.id] = {
          'id': doc.id,
          'name': name,
          'phone': phone,
        };
      }

      final list = delegatesMap.values.toList();
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      if (!mounted) return;
      setState(() {
        _companyDelegates = list;
        _isLoadingDelegates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingDelegates = false;
      });
    }
  }

  void _applyViolationSelection(StandardViolation violation, bool repeated) {
    _selectedOfficialViolation = violation;
    _selectedCategory = violation.category;
    _titleController.text = violation.title;

    if (repeated) {
      if (violation.action2 != null && violation.action2!.isNotEmpty) {
        _descriptionController.text = violation.action2!;
        if (violation.id == 8) {
          _fineAmountController.text = '5000';
        } else if (violation.id == 9) {
          _fineAmountController.text = '3000';
        } else if (violation.id == 23 || violation.id == 24) {
          _fineAmountController.text = '100';
        } else {
          _fineAmountController.text = violation.defaultFine > 0
              ? violation.defaultFine.toStringAsFixed(0)
              : '0';
        }
      } else {
        _descriptionController.text = '${violation.action1} (مخالفة مكررة)';
        _fineAmountController.text = violation.defaultFine > 0
            ? violation.defaultFine.toStringAsFixed(0)
            : '0';
      }
    } else {
      _fineAmountController.text = violation.defaultFine > 0
          ? violation.defaultFine.toStringAsFixed(0)
          : '0';
      _descriptionController.text = violation.action1;
    }
  }

  Future<void> _pickFiles() async {
    final images = await _picker.pickMultiImage();
    if (!mounted) return;
    
    if (images.isNotEmpty) {
      setState(() {
        for (var img in images) {
          _attachedFiles.add(File(img.path));
        }
      });
    }
  }

  void _showCompanySearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _CompanySearchBottomSheet(
          companies: _companies,
          selectedCompanyId: _selectedCompanyId,
          onCompanySelected: (id, name) {
            setState(() {
              _selectedCompanyId = id;
              _selectedCompanyName = name;
            });
            _fetchCompanyDelegates(id);
          },
        );
      },
    );
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompanyId == null || _selectedCompanyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار الشركة المستهدفة')),
      );
      return;
    }

    final rawTitle = _selectedOfficialViolation != null
        ? _selectedOfficialViolation!.title
        : _titleController.text.trim();

    if (rawTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار المخالفة من اللائحة الرسمية')),
      );
      return;
    }

    final finalTitle = _isRepeated ? '$rawTitle (مخالفة مكررة)' : rawTitle;
    final fineAmount = double.tryParse(_fineAmountController.text) ?? 0.0;

    final penalty = PenaltyEntity(
      penaltyId: '',
      companyId: _selectedCompanyId!,
      companyName: _selectedCompanyName ?? _selectedCompanyId!,
      createdById: widget.adminDelegate.uid,
      createdByName: widget.adminDelegate.fullName,
      title: finalTitle,
      category: _selectedCategory,
      incidentDescription: _descriptionController.text.trim(),
      fineAmount: fineAmount,
      currency: 'EGP',
      status: PenaltyStatus.pendingBranchesMarketing,
      evidenceFiles: const [],
      targetDelegateId: _selectedDelegateId,
      targetDelegateName: _selectedDelegateName,
      isRepeated: _isRepeated,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    context.read<PenaltyBloc>().add(
          CreatePenaltyRequestedEvent(
            penalty: penalty,
            evidenceFilesToUpload: _attachedFiles,
          ),
        );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _fineAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تسجيل غرامة ومخالفة جديدة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocListener<PenaltyBloc, PenaltyState>(
        listener: (context, state) {
          if (state is PenaltyActionSuccessState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true);
          } else if (state is PenaltyErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Target Company Selector with Search
                  Text(
                    'الشركة المستهدفة بالشأن',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _isLoadingCompanies
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : InkWell(
                          onTap: _showCompanySearchSheet,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.outline.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  color: colorScheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _selectedCompanyName ?? 'اختر الشركة...',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _selectedCompanyName != null
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        size: 16,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'بحث',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),

                  // 1.b Target Delegate Selector (Optional)
                  if (_selectedCompanyId != null) ...[
                    Text(
                      'المندوب المستهدف بالشركة (اختياري)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _isLoadingDelegates
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : DropdownButtonFormField<String?>(
                            initialValue: _selectedDelegateId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              hintText: 'بدون تحديد مندوب (على الشركة فقط)',
                              prefixIcon: const Icon(Icons.person_pin_rounded),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'بدون تحديد مندوب (تطبيق المخالفة على الشركة بالكامل)',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ..._companyDelegates.map((d) {
                                return DropdownMenuItem<String?>(
                                  value: d['id'],
                                  child: Text(d['name'] ?? ''),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedDelegateId = val;
                                if (val != null) {
                                  final selected = _companyDelegates.firstWhere(
                                    (d) => d['id'] == val,
                                    orElse: () => {'name': ''},
                                  );
                                  _selectedDelegateName = selected['name'];
                                } else {
                                  _selectedDelegateName = null;
                                }
                              });
                            },
                          ),
                    const SizedBox(height: 20),
                  ],

                  // 2. Official Violations Schedule Dropdown (لائحة المخالفات الرسمية)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.gavel_rounded,
                                color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'اختيار المخالفة من اللائحة الرسمية',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<StandardViolation>(
                          initialValue: _selectedOfficialViolation,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: 'اختر المخالفة حسب اللائحة (1 - 24)...',
                            fillColor: colorScheme.surface,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          items: officialViolationsSchedule.map((v) {
                            final fineLabel = v.defaultFine > 0
                                ? '${v.defaultFine.toStringAsFixed(0)} ج.م'
                                : 'لفت نظر';
                            return DropdownMenuItem<StandardViolation>(
                              value: v,
                              child: Text(
                                '${v.id}. ${v.title} ($fineLabel)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _applyViolationSelection(val, _isRepeated);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Repeated Violation Selector (طبيعة المخالفة)
                  Text(
                    'طبيعة وقوع المخالفة',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'المرة الأولى (أول واقعة)',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          selected: !_isRepeated,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _isRepeated = false;
                                if (_selectedOfficialViolation != null) {
                                  _applyViolationSelection(
                                      _selectedOfficialViolation!, false);
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'مخالفة مكررة (المرة الثانية)',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          selected: _isRepeated,
                          selectedColor: colorScheme.errorContainer,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _isRepeated = true;
                                if (_selectedOfficialViolation != null) {
                                  _applyViolationSelection(
                                      _selectedOfficialViolation!, true);
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Fine Amount
                  Text(
                    'قيمة الغرامة المستحقة',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _fineAmountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '5000.00',
                      prefixIcon: const Icon(Icons.attach_money_rounded),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'الرجاء أدخل مبلغ الغرامة';
                      }
                      if (double.tryParse(val) == null) return 'مبلغ غير صحيح';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 5. Incident Description
                  Text(
                    'تفاصيل الواقعة',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'أدخل تفاصيل الواقعة وملاحظات المخالفة...',
                      alignLabelWithHint: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'الرجاء ادخل تفاصيل الواقعة'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // 6. Evidence Attachments
                  Row(
                    children: [
                      Text(
                        'المستندات والأدلة المرفقة',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: const Text('إضافة ملفات'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_attachedFiles.isEmpty)
                    Text(
                      'لم يتم إرفاق أي صور أو مستندات حتى الآن',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _attachedFiles.map((f) {
                        final name = f.path.split('/').last.split('\\').last;
                        return Chip(
                          avatar: const Icon(Icons.insert_drive_file_rounded,
                              size: 16),
                          label: Text(name),
                          onDeleted: () {
                            setState(() {
                              _attachedFiles.remove(f);
                            });
                          },
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 32),

                  // 7. Submit Button (Responsive & Fully Styled)
                  BlocBuilder<PenaltyBloc, PenaltyState>(
                    builder: (context, state) {
                      final isLoading = state is PenaltyLoadingState;

                      return SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: isLoading ? null : _submitForm,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                          ),
                          child: isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'جاري تسجيل الغرامة...',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.gavel_rounded, size: 22),
                                      const SizedBox(width: 10),
                                      Text(
                                        'تسجيل وإصدار الغرامة',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanySearchBottomSheet extends StatefulWidget {
  final List<Map<String, String>> companies;
  final String? selectedCompanyId;
  final Function(String id, String name) onCompanySelected;

  const _CompanySearchBottomSheet({
    required this.companies,
    required this.selectedCompanyId,
    required this.onCompanySelected,
  });

  @override
  State<_CompanySearchBottomSheet> createState() =>
      _CompanySearchBottomSheetState();
}

class _CompanySearchBottomSheetState
    extends State<_CompanySearchBottomSheet> {
  final _searchController = TextEditingController();
  List<Map<String, String>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.companies;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.companies;
      } else {
        _filtered = widget.companies.where((c) {
          final name = (c['name'] ?? '').toLowerCase();
          return name.contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'اختر الشركة المستهدفة (${widget.companies.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'ابحث باسم الشركة...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لم يتم العثور على أي شركة بهذا الاسم',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final company = _filtered[index];
                      final isSelected = company['id'] == widget.selectedCompanyId;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? colorScheme.primary
                              : colorScheme.primaryContainer.withValues(alpha: 0.5),
                          child: Icon(
                            Icons.business_rounded,
                            color: isSelected
                                ? Colors.white
                                : colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          company['name']!,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle_rounded,
                                color: colorScheme.primary)
                            : null,
                        onTap: () {
                          widget.onCompanySelected(
                            company['id']!,
                            company['name']!,
                          );
                          Navigator.of(context).pop();
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
