import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/entities/standard_violation.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/penalties/presentation/widgets/penalty_evidence_viewer.dart';

class AdminCreatePenaltyPage extends StatefulWidget {
  final Delegate adminDelegate;
  final PenaltyEntity? penaltyToEdit;
  final String? initialCompanyId;
  final String? initialCompanyName;
  final String? initialDelegateId;
  final String? initialDelegateName;
  final String? initialBranchId;
  final String? initialBranchName;
  final int? initialViolationId;
  final String? initialIncidentDetails;

  const AdminCreatePenaltyPage({
    super.key,
    required this.adminDelegate,
    this.penaltyToEdit,
    this.initialCompanyId,
    this.initialCompanyName,
    this.initialDelegateId,
    this.initialDelegateName,
    this.initialBranchId,
    this.initialBranchName,
    this.initialViolationId,
    this.initialIncidentDetails,
  });

  @override
  State<AdminCreatePenaltyPage> createState() => _AdminCreatePenaltyPageState();
}

class _AdminCreatePenaltyPageState extends State<AdminCreatePenaltyPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _fineAmountController = TextEditingController();
  final _picker = ImagePicker();

  bool get _isEditMode => widget.penaltyToEdit != null;

  String? _selectedCompanyId;
  String? _selectedCompanyName;
  ViolationCategory _selectedCategory = ViolationCategory.protocolBreach;

  StandardViolation? _selectedOfficialViolation;
  String? _selectedDelegateId;
  String? _selectedDelegateName;
  List<Map<String, String>> _companyDelegates = [];
  bool _isLoadingDelegates = false;

  String? _selectedBranchId;
  String? _selectedBranchName;
  List<Map<String, String>> _branches = [];
  List<String> _pinnedBranchIds = [];
  bool _isLoadingBranches = true;

  List<Map<String, String>> _companies = [];
  bool _isLoadingCompanies = true;

  List<EvidenceFile> _existingEvidenceFiles = [];
  final List<File> _attachedFiles = [];

  bool _isRepeated = false;

  String? get _effectiveCompanyId =>
      (widget.penaltyToEdit?.companyId.isNotEmpty == true)
          ? widget.penaltyToEdit!.companyId
          : widget.initialCompanyId;

  String? get _effectiveCompanyName =>
      (widget.penaltyToEdit?.companyName.isNotEmpty == true)
          ? widget.penaltyToEdit!.companyName
          : widget.initialCompanyName;

  String? get _effectiveBranchId =>
      (widget.penaltyToEdit?.branchId?.isNotEmpty == true)
          ? widget.penaltyToEdit!.branchId
          : widget.initialBranchId;

  String? get _effectiveBranchName =>
      (widget.penaltyToEdit?.branchName?.isNotEmpty == true)
          ? widget.penaltyToEdit!.branchName
          : widget.initialBranchName;

  String? get _effectiveDelegateId =>
      (widget.penaltyToEdit?.targetDelegateId?.isNotEmpty == true)
          ? widget.penaltyToEdit!.targetDelegateId
          : widget.initialDelegateId;

  String? get _effectiveDelegateName =>
      (widget.penaltyToEdit?.targetDelegateName?.isNotEmpty == true)
          ? widget.penaltyToEdit!.targetDelegateName
          : widget.initialDelegateName;

  @override
  void initState() {
    super.initState();
    if (widget.penaltyToEdit != null) {
      final p = widget.penaltyToEdit!;
      _selectedCompanyId = p.companyId.isNotEmpty ? p.companyId : null;
      _selectedCompanyName = p.companyName.isNotEmpty ? p.companyName : null;
      _selectedBranchId = (p.branchId?.isNotEmpty == true) ? p.branchId : null;
      _selectedBranchName = (p.branchName?.isNotEmpty == true) ? p.branchName : null;
      _selectedDelegateId = (p.targetDelegateId?.isNotEmpty == true) ? p.targetDelegateId : null;
      _selectedDelegateName = (p.targetDelegateName?.isNotEmpty == true) ? p.targetDelegateName : null;
      _selectedCategory = p.category;
      _titleController.text = p.title;
      _descriptionController.text = p.incidentDescription;
      _fineAmountController.text = p.fineAmount.toStringAsFixed(0);
      _isRepeated = p.isRepeated;
      _existingEvidenceFiles = List<EvidenceFile>.from(p.evidenceFiles);

      // Match official violation if possible
      final cleanTitle = p.title.replaceAll('(مخالفة مكررة)', '').trim();
      for (var v in officialViolationsSchedule) {
        if (v.title.trim().toLowerCase() == cleanTitle.toLowerCase() ||
            p.title.trim().toLowerCase() == v.title.trim().toLowerCase() ||
            cleanTitle.toLowerCase().contains(v.title.trim().toLowerCase()) ||
            v.title.trim().toLowerCase().contains(cleanTitle.toLowerCase())) {
          _selectedOfficialViolation = v;
          break;
        }
      }
    } else {
      if (widget.initialViolationId != null) {
        final violation = officialViolationsSchedule.firstWhere(
          (v) => v.id == widget.initialViolationId,
          orElse: () => officialViolationsSchedule.firstWhere(
            (v) => v.id == 28,
            orElse: () => officialViolationsSchedule.first,
          ),
        );
        _applyViolationSelection(violation, false);
      }
      if (widget.initialIncidentDetails != null && widget.initialIncidentDetails!.isNotEmpty) {
        _descriptionController.text = widget.initialIncidentDetails!;
      }
      if (widget.initialCompanyId != null && widget.initialCompanyId!.isNotEmpty) {
        _selectedCompanyId = widget.initialCompanyId;
        _selectedCompanyName = widget.initialCompanyName;
      }
      if (widget.initialBranchId != null && widget.initialBranchId!.isNotEmpty) {
        _selectedBranchId = widget.initialBranchId;
        _selectedBranchName = widget.initialBranchName;
      }
      if (widget.initialDelegateId != null && widget.initialDelegateId!.isNotEmpty) {
        _selectedDelegateId = widget.initialDelegateId;
        _selectedDelegateName = widget.initialDelegateName;
      }
    }
    _fetchCompanies();
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
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

      // Check for pinned branch from SharedPreferences (multi or single)
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

      final pinnedIds = <String>[];
      if (savedList != null) {
        for (final id in savedList) {
          if (list.any((b) => b['id'] == id)) {
            pinnedIds.add(id);
          }
        }
      }

      String? initialSelectedId;
      String? initialSelectedName;

      final targetBranchId = _selectedBranchId ?? _effectiveBranchId;
      final targetBranchName = _selectedBranchName ?? _effectiveBranchName;

      if (targetBranchId != null && targetBranchId.isNotEmpty) {
        final match = list.firstWhere(
          (b) => b['id'] == targetBranchId,
          orElse: () => list.firstWhere(
            (b) => (b['name'] ?? '').trim().toLowerCase() == (targetBranchName ?? '').trim().toLowerCase() ||
                   (targetBranchName != null && (b['name'] ?? '').trim().toLowerCase().contains(targetBranchName.trim().toLowerCase())),
            orElse: () => {
              'id': targetBranchId,
              'name': targetBranchName ?? targetBranchId,
            },
          ),
        );
        if (!list.any((b) => b['id'] == match['id'])) {
          list.add(match);
        }
        initialSelectedId = match['id'];
        initialSelectedName = match['name'];
      } else if (targetBranchName != null && targetBranchName.isNotEmpty) {
        final match = list.firstWhere(
          (b) => (b['name'] ?? '').trim().toLowerCase() == targetBranchName.trim().toLowerCase() ||
                 (b['name'] ?? '').trim().toLowerCase().contains(targetBranchName.trim().toLowerCase()),
          orElse: () => {
            'id': 'branch_$targetBranchName',
            'name': targetBranchName,
          },
        );
        if (!list.any((b) => b['id'] == match['id'])) {
          list.add(match);
        }
        initialSelectedId = match['id'];
        initialSelectedName = match['name'];
      } else if (pinnedIds.isNotEmpty) {
        initialSelectedId = pinnedIds.first;
        final match = list.firstWhere((b) => b['id'] == pinnedIds.first);
        initialSelectedName = match['name'];
      } else if (list.isNotEmpty) {
        initialSelectedId = list.first['id'];
        initialSelectedName = list.first['name'];
      }

      setState(() {
        _branches = list;
        _pinnedBranchIds = pinnedIds;
        _selectedBranchId = initialSelectedId;
        _selectedBranchName = initialSelectedName;
        _isLoadingBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBranches = false;
      });
    }
  }

  String _effectiveOrgUid = '';

  Future<String> _getEffectiveOrgUid() async {
    if (_effectiveOrgUid.isNotEmpty) return _effectiveOrgUid;
    if (widget.adminDelegate.organizationUID.isNotEmpty &&
        widget.adminDelegate.organizationUID != 'all') {
      _effectiveOrgUid = widget.adminDelegate.organizationUID;
      return _effectiveOrgUid;
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final orgsSnap = await firestore.collection('organizations').get();
      if (orgsSnap.docs.isNotEmpty) {
        final fathallaDoc = orgsSnap.docs.firstWhere(
          (doc) {
            final name = doc.data()['name']?.toString().toLowerCase() ?? '';
            return name.contains('fathalla');
          },
          orElse: () {
            var bestDoc = orgsSnap.docs.first;
            int maxCompanies = 0;
            for (final d in orgsSnap.docs) {
              final count = (d.data()['companies'] as num?)?.toInt() ?? 0;
              if (count > maxCompanies) {
                maxCompanies = count;
                bestDoc = d;
              }
            }
            return bestDoc;
          },
        );
        _effectiveOrgUid = fathallaDoc.id;
        return _effectiveOrgUid;
      }
    } catch (_) {}
    _effectiveOrgUid = 'PiioBFgxaHAeuRdjlDgj';
    return _effectiveOrgUid;
  }

  Future<void> _fetchCompanies() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final orgUid = await _getEffectiveOrgUid();

      final snapshot = await firestore
          .collection('organizations')
          .doc(orgUid)
          .collection('companies')
          .get();

      if (!mounted) return;

      final Map<String, Map<String, String>> compMap = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name']?.toString() ?? data['companyName']?.toString() ?? doc.id;
        compMap[doc.id] = {
          'id': doc.id,
          'name': name,
        };
      }

      // Also check root /companies in Firestore
      try {
        final rootCompSnap = await firestore.collection('companies').get();
        for (var doc in rootCompSnap.docs) {
          final data = doc.data();
          final name = data['name']?.toString() ?? data['companyName']?.toString() ?? doc.id;
          if (!compMap.containsKey(doc.id)) {
            compMap[doc.id] = {
              'id': doc.id,
              'name': name,
            };
          }
        }
      } catch (_) {}

      final list = compMap.values.toList();
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      String? targetCompId;
      String? targetCompName;

      final initCompId = _selectedCompanyId ?? _effectiveCompanyId;
      final initCompName = _selectedCompanyName ?? _effectiveCompanyName;

      if (initCompId != null && initCompId.isNotEmpty) {
        final match = list.firstWhere(
          (c) => c['id'] == initCompId,
          orElse: () => list.firstWhere(
            (c) => (c['name'] ?? '').trim().toLowerCase() == (initCompName ?? '').trim().toLowerCase() ||
                   (initCompName != null && (c['name'] ?? '').trim().toLowerCase().contains(initCompName.trim().toLowerCase())) ||
                   (initCompName != null && initCompName.trim().toLowerCase().contains((c['name'] ?? '').trim().toLowerCase())),
            orElse: () => {
              'id': initCompId,
              'name': initCompName?.isNotEmpty == true ? initCompName! : initCompId,
            },
          ),
        );
        if (!list.any((c) => c['id'] == match['id'])) {
          list.add(match);
        }
        targetCompId = match['id'];
        targetCompName = match['name'];
      } else if (initCompName != null && initCompName.isNotEmpty) {
        final match = list.firstWhere(
          (c) => (c['name'] ?? '').trim().toLowerCase() == initCompName.trim().toLowerCase() ||
                 (c['name'] ?? '').trim().toLowerCase().contains(initCompName.trim().toLowerCase()) ||
                 initCompName.trim().toLowerCase().contains((c['name'] ?? '').trim().toLowerCase()),
          orElse: () => {
            'id': 'comp_$initCompName',
            'name': initCompName,
          },
        );
        if (!list.any((c) => c['id'] == match['id'])) {
          list.add(match);
        }
        targetCompId = match['id'];
        targetCompName = match['name'];
      } else if (list.isNotEmpty) {
        targetCompId = list.first['id'];
        targetCompName = list.first['name'];
      }

      setState(() {
        _companies = list;
        _selectedCompanyId = targetCompId;
        _selectedCompanyName = targetCompName;
        _isLoadingCompanies = false;
      });

      if (targetCompId != null && targetCompId.isNotEmpty) {
        _fetchCompanyDelegates(targetCompId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCompanies = false;
      });
    }
  }

  Future<void> _fetchCompanyDelegates(String companyId, {bool resetSelection = false}) async {
    setState(() {
      _isLoadingDelegates = true;
      _companyDelegates = [];
      if (resetSelection) {
        _selectedDelegateId = null;
        _selectedDelegateName = null;
      }
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final Map<String, Map<String, String>> delegatesMap = {};
      final orgUid = await _getEffectiveOrgUid();

      // Strategy 1: Fetch from subcollection /organizations/{org}/companies/{comp}/delegates
      if (orgUid.isNotEmpty) {
        try {
          final subSnapshot = await firestore
              .collection('organizations')
              .doc(orgUid)
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
      try {
        final userSnapshot = await firestore
            .collection('users')
            .where('companyUID', isEqualTo: companyId)
            .get();

        for (var doc in userSnapshot.docs) {
          final data = doc.data();
          final role = data['role']?.toString().toLowerCase() ?? '';
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
      } catch (_) {}

      // Strategy 3: Also query users matching companyName
      if (_selectedCompanyName != null && _selectedCompanyName!.isNotEmpty) {
        try {
          final nameSnapshot = await firestore
              .collection('users')
              .where('companyName', isEqualTo: _selectedCompanyName)
              .get();

          for (var doc in nameSnapshot.docs) {
            final data = doc.data();
            final role = data['role']?.toString().toLowerCase() ?? '';
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
        } catch (_) {}
      }

      final list = delegatesMap.values.toList();
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

      String? targetDelId = resetSelection ? null : (_selectedDelegateId ?? _effectiveDelegateId);
      String? targetDelName = resetSelection ? null : (_selectedDelegateName ?? _effectiveDelegateName);

      if (targetDelId != null && targetDelId.isNotEmpty) {
        final nonNullId = targetDelId;
        final match = list.firstWhere(
          (d) => d['id'] == nonNullId,
          orElse: () => list.firstWhere(
            (d) => (targetDelName != null && (d['name'] ?? '').trim().toLowerCase() == targetDelName.trim().toLowerCase()) ||
                   (targetDelName != null && (d['name'] ?? '').trim().toLowerCase().contains(targetDelName.trim().toLowerCase())),
            orElse: () => {
              'id': nonNullId,
              'name': targetDelName ?? nonNullId,
            },
          ),
        );
        if (!list.any((d) => d['id'] == match['id'])) {
          list.add(match);
        }
        targetDelId = match['id'];
        targetDelName = match['name'];
      } else if (targetDelName != null && targetDelName.isNotEmpty) {
        final nonNullName = targetDelName;
        final match = list.firstWhere(
          (d) => (d['name'] ?? '').trim().toLowerCase() == nonNullName.trim().toLowerCase() ||
                 (d['name'] ?? '').trim().toLowerCase().contains(nonNullName.trim().toLowerCase()) ||
                 nonNullName.trim().toLowerCase().contains((d['name'] ?? '').trim().toLowerCase()),
          orElse: () => {
            'id': 'del_$nonNullName',
            'name': nonNullName,
          },
        );
        if (!list.any((d) => d['id'] == match['id'])) {
          list.add(match);
        }
        targetDelId = match['id'];
        targetDelName = match['name'];
      }

      if (!mounted) return;
      setState(() {
        _companyDelegates = list;
        _selectedDelegateId = targetDelId;
        _selectedDelegateName = targetDelName;
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
      if (violation.repeatedFine != null && violation.repeatedFine! > 0) {
        _fineAmountController.text = violation.repeatedFine!.toStringAsFixed(0);
      } else if (violation.defaultFine > 0) {
        _fineAmountController.text = violation.defaultFine.toStringAsFixed(0);
      } else {
        _fineAmountController.text = '0';
      }

      if (violation.action2 != null && violation.action2!.isNotEmpty) {
        _descriptionController.text = violation.action2!;
      } else {
        _descriptionController.text = '${violation.action1} (مخالفة مكررة)';
      }
    } else {
      _fineAmountController.text = violation.defaultFine > 0
          ? violation.defaultFine.toStringAsFixed(0)
          : '0';
      _descriptionController.text = violation.action1;
    }
  }

  Future<void> _pickFiles() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إرفاق إيصال / مستند المخالفة',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.camera_alt_rounded, color: Colors.green),
                ),
                title: const Text('التقاط صورة بالكاميرا'),
                subtitle: const Text('تصوير الإيصال أو الواقعة مباشرة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final photo = await _picker.pickImage(source: ImageSource.camera);
                  if (photo != null && mounted) {
                    setState(() {
                      _attachedFiles.add(File(photo.path));
                    });
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.photo_library_rounded, color: Colors.blue),
                ),
                title: const Text('اختيار من المعرض'),
                subtitle: const Text('تحديد صورة أو إيصال محفوظ بالجهاز'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final images = await _picker.pickMultiImage();
                  if (images.isNotEmpty && mounted) {
                    setState(() {
                      for (var img in images) {
                        _attachedFiles.add(File(img.path));
                      }
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
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
            _fetchCompanyDelegates(id, resetSelection: true);
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

    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار الفرع الذي حدثت به الواقعة')),
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

    if (_isEditMode) {
      final old = widget.penaltyToEdit!;
      final updatedPenalty = PenaltyEntity(
        penaltyId: old.penaltyId,
        companyId: _selectedCompanyId!,
        companyName: _selectedCompanyName ?? _selectedCompanyId!,
        branchId: _selectedBranchId,
        branchName: _selectedBranchName,
        createdById: old.createdById,
        createdByName: old.createdByName,
        createdByPhone: old.createdByPhone ??
            (widget.adminDelegate.phoneNumber.isNotEmpty ? widget.adminDelegate.phoneNumber : null),
        title: finalTitle,
        category: _selectedCategory,
        incidentDescription: _descriptionController.text.trim(),
        fineAmount: fineAmount,
        currency: old.currency,
        status: old.status,
        evidenceFiles: _existingEvidenceFiles,
        branchesMarketingApprovedBy: old.branchesMarketingApprovedBy,
        branchesMarketingApprovedAt: old.branchesMarketingApprovedAt,
        generalManagerApprovedBy: old.generalManagerApprovedBy,
        generalManagerApprovedAt: old.generalManagerApprovedAt,
        rejectionReason: old.rejectionReason,
        targetDelegateId: _selectedDelegateId,
        targetDelegateName: _selectedDelegateName,
        isRepeated: _isRepeated,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );

      context.read<PenaltyBloc>().add(
            UpdatePenaltyRequestedEvent(
              penalty: updatedPenalty,
              newEvidenceFilesToUpload: _attachedFiles,
            ),
          );
    } else {
      final penalty = PenaltyEntity(
        penaltyId: '',
        companyId: _selectedCompanyId!,
        companyName: _selectedCompanyName ?? _selectedCompanyId!,
        branchId: _selectedBranchId,
        branchName: _selectedBranchName,
        createdById: widget.adminDelegate.uid,
        createdByName: widget.adminDelegate.fullName,
        createdByPhone: widget.adminDelegate.phoneNumber.isNotEmpty
            ? widget.adminDelegate.phoneNumber
            : null,
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
        title: Text(
          _isEditMode ? 'تعديل بيانات ومستندات الغرامة' : 'تسجيل غرامة ومخالفة جديدة',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
                            key: ValueKey('delegate_${_selectedDelegateId}_${_companyDelegates.length}'),
                            initialValue: _companyDelegates.any((d) => d['id'] == _selectedDelegateId)
                                ? _selectedDelegateId
                                : null,
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

                  // 1.c Branch Selector (الفرع الذي حدثت به الواقعة)
                  Row(
                    children: [
                      Text(
                        'الفرع الذي حدثت به الواقعة',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_pinnedBranchIds.isNotEmpty) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'قطاعك المثبت 📌',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_pinnedBranchIds.length > 1) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _pinnedBranchIds.map((bId) {
                          final branchObj = _branches.firstWhere(
                            (b) => b['id'] == bId,
                            orElse: () => {'name': bId},
                          );
                          final isSelected = _selectedBranchId == bId;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(
                                branchObj['name'] ?? bId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) {
                                  setState(() {
                                    _selectedBranchId = bId;
                                    _selectedBranchName = branchObj['name'];
                                  });
                                }
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _isLoadingBranches
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          key: ValueKey(_selectedBranchId),
                          initialValue: _branches.any((b) => b['id'] == _selectedBranchId)
                              ? _selectedBranchId
                              : (_branches.isNotEmpty ? _branches.first['id'] : null),
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: 'اختر الفرع...',
                            prefixIcon: const Icon(Icons.storefront_rounded),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          items: _branches.map((b) {
                            final isPinned = _pinnedBranchIds.contains(b['id']);
                            return DropdownMenuItem<String>(
                              value: b['id'],
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      b['name'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (isPinned)
                                    Text(
                                      '📌',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedBranchId = val;
                              if (val != null) {
                                final selected = _branches.firstWhere(
                                  (b) => b['id'] == val,
                                  orElse: () => {'name': ''},
                                );
                                _selectedBranchName = selected['name'];
                              }
                            });
                          },
                          validator: (val) =>
                              (val == null || val.isEmpty) ? 'الرجاء اختيار الفرع' : null,
                        ),
                  const SizedBox(height: 20),

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
                          key: ValueKey('violation_${_selectedOfficialViolation?.id}'),
                          initialValue: _selectedOfficialViolation != null
                              ? officialViolationsSchedule.firstWhere(
                                  (v) => v.id == _selectedOfficialViolation!.id,
                                  orElse: () => _selectedOfficialViolation!,
                                )
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText:
                                'اختر المخالفة حسب اللائحة (1 - ${officialViolationsSchedule.length})...',
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
                            return DropdownMenuItem<StandardViolation>(
                              value: v,
                              child: Text(
                                '${v.id}. ${v.title}',
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
                    readOnly: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixText: 'ج.م (محدد باللائحة)',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                        return 'الرجاء اختيار المخالفة لتحديد المبلغ';
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

                  // Existing Files (In Edit Mode)
                  if (_existingEvidenceFiles.isNotEmpty) ...[
                    Text(
                      'المستندات الحالية المحفوظة (${_existingEvidenceFiles.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _existingEvidenceFiles.map((ev) {
                        final isImg = ev.fileType.toUpperCase() == 'IMAGE' ||
                            ev.fileType.toUpperCase() == 'IMG' ||
                            ev.fileName.toLowerCase().endsWith('.jpg') ||
                            ev.fileName.toLowerCase().endsWith('.jpeg') ||
                            ev.fileName.toLowerCase().endsWith('.png') ||
                            ev.fileName.toLowerCase().endsWith('.webp');

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  if (isImg) {
                                    PenaltyEvidenceViewer.showImageLightbox(
                                      context,
                                      imageUrl: ev.fileUrl,
                                      title: _titleController.text.isNotEmpty
                                          ? _titleController.text
                                          : 'معاينة المستند',
                                      fileName: ev.fileName,
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isImg)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: CachedNetworkImage(
                                          imageUrl: ev.fileUrl,
                                          width: 28,
                                          height: 28,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) => const Icon(Icons.broken_image_rounded, size: 20),
                                        ),
                                      )
                                    else
                                      Icon(
                                        ev.fileType == 'PDF'
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.insert_drive_file_rounded,
                                        size: 20,
                                        color: colorScheme.primary,
                                      ),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 130),
                                      child: Text(
                                        ev.fileName,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _existingEvidenceFiles.remove(ev);
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.cancel_rounded,
                                    size: 18,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // New Attached Files
                  if (_attachedFiles.isNotEmpty) ...[
                    if (_existingEvidenceFiles.isNotEmpty)
                      Text(
                        'الملفات الجديدة المضافة حديثاً (${_attachedFiles.length}):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    if (_existingEvidenceFiles.isNotEmpty) const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _attachedFiles.map((f) {
                        final name = f.path.split('/').last.split('\\').last;
                        final isImg = name.toLowerCase().endsWith('.jpg') ||
                            name.toLowerCase().endsWith('.jpeg') ||
                            name.toLowerCase().endsWith('.png') ||
                            name.toLowerCase().endsWith('.webp');

                        return InkWell(
                          onTap: () => PenaltyEvidenceViewer.showLocalImageLightbox(
                            context,
                            file: f,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isImg)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      f,
                                      width: 28,
                                      height: 28,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Icon(Icons.insert_drive_file_rounded,
                                      size: 20, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 140),
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _attachedFiles.remove(f);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: Icon(
                                      Icons.cancel_rounded,
                                      size: 18,
                                      color: colorScheme.error,
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

                  if (_existingEvidenceFiles.isEmpty && _attachedFiles.isEmpty)
                    Text(
                      'لم يتم إرفاق أي صور أو مستندات حتى الآن',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
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
                            backgroundColor: _isEditMode ? colorScheme.primary : null,
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
                                      _isEditMode
                                          ? 'جاري حفظ التعديلات والمستندات...'
                                          : 'جاري تسجيل الغرامة...',
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
                                      Icon(
                                        _isEditMode
                                            ? Icons.save_rounded
                                            : Icons.gavel_rounded,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _isEditMode
                                            ? 'حفظ التعديلات والمستندات'
                                            : 'تسجيل وإصدار الغرامة',
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
